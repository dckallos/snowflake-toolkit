#!/usr/bin/env python3
"""Thin privilege preflight for the OpenAccess Artwork Medallion Pipeline IaC.

The bash orchestrator scripts/orchestrate.sh now owns the execution model
(manifest iteration, phase classification, create_ -> drop_ paired-drop
derivation, forward/rollback symmetry, filename/path-based single-script
rollback, and secret-stdout suppression). This module is the one piece kept in
Python (H4, 2026-05-29; operator chose "bash driver + thin Python preflight"):
the account-level privilege preflight, because it parses SHOW GRANTS JSON and
does set logic that bash handles poorly. No new dependency is introduced.

Subcommands (invoked by orchestrate.sh):
  verify-contract
      Static check, run before any DDL: parse the active
      "GRANT ... ON ACCOUNT TO ROLE ARTWORK_ADMIN" statements in
      infrastructure/create_roles.sql and assert they match
      REQUIRED_ADMIN_ACCOUNT_PRIVILEGES, so the two copies never drift.
  assert-account-privileges --connection NAME
      Runtime check, run the moment infrastructure/create_roles.sql applies
      and BEFORE create_warehouses.sql issues the first ARTWORK_ADMIN-owned
      CREATE WAREHOUSE: run scripts/sql/show_admin_account_grants.sql via
      `snow sql --filename ... --format json`, keep the ACCOUNT-scoped rows,
      and assert ARTWORK_ADMIN holds every required account-level privilege.

This module authors no SQL: the only statement it runs lives in a
version-controlled .sql file. .env is read via dotenv_values purely so the
snow CLI inherits any SNOWFLAKE_* vars; it sets no credentials itself.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import subprocess
from pathlib import Path
from typing import Dict

from dotenv import dotenv_values

REPO_ROOT = Path(__file__).resolve().parent.parent
INFRA_DIR = REPO_ROOT / "infrastructure"
# Authoritative account-grant source for the static privilege cross-check.
# verify_privilege_contract parses the active "GRANT ... ON ACCOUNT TO ROLE
# ARTWORK_ADMIN" statements here and asserts they match
# REQUIRED_ADMIN_ACCOUNT_PRIVILEGES, so the two copies never drift.
ROLES_SQL = INFRA_DIR / "create_roles.sql"
# Read-only preflight probe: the SHOW GRANTS statement lives in this
# version-controlled .sql file (never an inline Python string) so Python
# stays a pure executor. assert_admin_account_privileges runs it via
# `snow sql --filename ... --format json` and parses the ACCOUNT-scoped rows.
PREFLIGHT_GRANTS_SQL = REPO_ROOT / "scripts" / "sql" / "show_admin_account_grants.sql"

DEFAULT_CONNECTION = "admin"

# Single source of truth for the global (account-level) privileges that
# ARTWORK_ADMIN must hold. Keep this in lockstep with the
# "GRANT ... ON ACCOUNT TO ROLE ARTWORK_ADMIN" statements in
# infrastructure/create_roles.sql. The orchestrator runs the runtime preflight
# (assert-account-privileges) immediately after create_roles.sql applies and
# before create_warehouses.sql issues the first ARTWORK_ADMIN-owned CREATE
# WAREHOUSE, so any drift between this set and create_roles.sql fails fast with
# the exact remediation GRANT instead of a cryptic 003001 (42501) several
# scripts deep.
REQUIRED_ADMIN_ACCOUNT_PRIVILEGES = frozenset({
    "CREATE WAREHOUSE",
    "CREATE DATABASE",
    # "EXECUTE TASK",  # enable in lockstep with create_roles.sql for create_tasks.sql
})

logger = logging.getLogger("preflight")


def configure_logging(verbose: bool) -> None:
    """
    Configure stdlib logging at INFO, or DEBUG when verbose.
    """
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def load_env() -> Dict[str, str]:
    """
    Return .env values as a dict so child processes inherit them.
    """
    return {k: v for k, v in dotenv_values(REPO_ROOT / ".env").items() if v is not None}


def _show_grants_account_privileges(env: Dict[str, str], conn: str) -> frozenset:
    """
    Return the set of ACCOUNT-level privileges currently held by ARTWORK_ADMIN.

    Invokes the snow CLI on the version-controlled query file
    scripts/sql/show_admin_account_grants.sql (run as
    snow sql -c <conn> --filename <file> --format json). The SHOW GRANTS
    statement lives in that .sql file rather than an inline Python string, so
    Python never authors SQL
    -- it only executes a file and parses the result. Keeps the uppercased
    `privilege` value of every row whose
    `granted_on` column equals 'ACCOUNT'. stdout is captured (never echoed),
    so this probe honors the SNOW_SUPPRESS_STDOUT convention and cannot leak
    anything to the terminal or chat scrollback. Raises SystemExit if the snow
    CLI call fails or its output is not parseable, so the preflight surfaces
    connectivity / auth problems immediately instead of silently treating the
    held privilege set as empty.
    """
    merged_env = {**os.environ, **env, "SNOW_CONNECTION": conn,
                  "SNOW_SUPPRESS_STDOUT": "1"}
    result = subprocess.run(
        ["snow", "sql", "-c", conn,
         "--filename", str(PREFLIGHT_GRANTS_SQL),
         "--format", "json"],
        cwd=str(REPO_ROOT),
        env=merged_env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            "Privilege preflight could not query grants for ARTWORK_ADMIN "
            "(snow sql exit %d on connection %r):\n%s"
            % (result.returncode, conn, (result.stderr or "").strip())
        )
    try:
        rows = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise SystemExit(
            "Privilege preflight could not parse SHOW GRANTS output as JSON: %s"
            % exc
        )
    held = {
        str(row.get("privilege", "")).upper()
        for row in rows
        if str(row.get("granted_on", "")).upper() == "ACCOUNT"
    }
    return frozenset(held)


def assert_admin_account_privileges(env: Dict[str, str], conn: str) -> None:
    """
    Fail fast if ARTWORK_ADMIN is missing any required account-level
    privilege, BEFORE any object DDL runs.

    Runs SHOW GRANTS TO ROLE ARTWORK_ADMIN, keeps rows whose granted_on is
    ACCOUNT, and compares the held privilege set against
    REQUIRED_ADMIN_ACCOUNT_PRIVILEGES. On any gap it raises with the exact
    remediation GRANT statements, so a missing privilege is reported once,
    immediately, instead of surfacing as a cryptic 003001 (42501) several
    scripts later.
    """
    held = _show_grants_account_privileges(env, conn)
    missing = REQUIRED_ADMIN_ACCOUNT_PRIVILEGES - held
    if missing:
        fixes = "\n".join(
            "  GRANT %s ON ACCOUNT TO ROLE ARTWORK_ADMIN;" % priv
            for priv in sorted(missing)
        )
        raise SystemExit(
            "ARTWORK_ADMIN is missing required account-level privileges: %s"
            "\nRun as ACCOUNTADMIN (or fix "
            "infrastructure/create_roles.sql):\n%s"
            % (", ".join(sorted(missing)), fixes)
        )
    logger.info(
        "Privilege preflight OK: ARTWORK_ADMIN holds %s",
        ", ".join(sorted(REQUIRED_ADMIN_ACCOUNT_PRIVILEGES)),
    )


def _grants_declared_in_roles_sql() -> frozenset:
    """
    Return the account-level privileges granted to ARTWORK_ADMIN in create_roles.sql.

    Parses infrastructure/create_roles.sql for active (non-commented)
    "GRANT <privilege> ON ACCOUNT TO ROLE ARTWORK_ADMIN" statements and
    returns the uppercased privilege set. SQL line-comments (-- ...) are
    stripped first, so the commented EXECUTE TASK grant is ignored until
    create_roles.sql actually enables it. This only READS existing SQL; it authors none.
    """
    try:
        raw = ROLES_SQL.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(
            "Privilege contract check could not read %s: %s" % (ROLES_SQL, exc)
        )
    privileges = set()
    pattern = re.compile(
        r"GRANT\s+(.+?)\s+ON\s+ACCOUNT\s+TO\s+ROLE\s+ARTWORK_ADMIN",
        re.IGNORECASE,
    )
    for line in raw.splitlines():
        code = line.split("--", 1)[0]
        match = pattern.search(code)
        if match:
            privileges.add(match.group(1).strip().upper())
    return frozenset(privileges)


def verify_privilege_contract() -> None:
    """
    Fail fast if REQUIRED_ADMIN_ACCOUNT_PRIVILEGES and the account grants in
    create_roles.sql have drifted apart.

    The Python frozenset (used by the runtime preflight) and the
    "GRANT ... ON ACCOUNT" block in create_roles.sql are two copies of one
    contract. This static check parses create_roles.sql and asserts the two
    sets are identical, so a
    grant added in one place but not the other is caught before any DDL runs
    -- not several scripts deep as a cryptic 003001 (42501).
    """
    declared = _grants_declared_in_roles_sql()
    expected = REQUIRED_ADMIN_ACCOUNT_PRIVILEGES
    if declared != expected:
        only_py = ", ".join(sorted(expected - declared)) or "(none)"
        only_sql = ", ".join(sorted(declared - expected)) or "(none)"
        raise SystemExit(
            "Account-privilege contract drift between the preflight and "
            "infrastructure/create_roles.sql.\n"
            "  In REQUIRED_ADMIN_ACCOUNT_PRIVILEGES but not granted in create_roles.sql: %s\n"
            "  Granted in create_roles.sql but not in REQUIRED_ADMIN_ACCOUNT_PRIVILEGES: %s\n"
            "Reconcile the two so both list the same account-level privileges."
            % (only_py, only_sql)
        )
    logger.info(
        "Privilege contract OK: preflight and create_roles.sql agree on %s",
        ", ".join(sorted(expected)),
    )


def parse_args(argv=None) -> argparse.Namespace:
    """
    Parse CLI arguments for the two preflight subcommands.
    """
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    contract = sub.add_parser(
        "verify-contract",
        help="Static account-privilege contract check vs create_roles.sql.",
    )
    contract.add_argument("-v", "--verbose", action="store_true")

    account = sub.add_parser(
        "assert-account-privileges",
        help="Runtime SHOW GRANTS preflight for ARTWORK_ADMIN.",
    )
    account.add_argument("--connection", default=DEFAULT_CONNECTION,
                         help='snow CLI connection name (default: "admin").')
    account.add_argument("-v", "--verbose", action="store_true")

    return parser.parse_args(argv)


def main(argv=None) -> int:
    """
    CLI entry point: dispatch the requested preflight subcommand.
    """
    args = parse_args(argv)
    configure_logging(getattr(args, "verbose", False))
    command = getattr(args, "command", None)
    if command == "verify-contract":
        verify_privilege_contract()
    elif command == "assert-account-privileges":
        env = load_env()
        assert_admin_account_privileges(env, args.connection)
    else:
        raise SystemExit(
            "Specify a subcommand: verify-contract | assert-account-privileges"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
