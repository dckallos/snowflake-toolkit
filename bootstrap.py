#!/usr/bin/env python3
"""Thin orchestrator for the OpenAccess Artwork Medallion Pipeline IaC.

Does NOT execute SQL. Discovers .sql files in sorted order and shells out
to scripts/apply_sql.sh (forward) or scripts/rollback_sql.sh (paired drop),
one file at a time. The Snowflake CLI (snow) is the only thing that talks to
Snowflake; it reads connection details from ~/.snowflake/config.toml.

Phases (ordering per the 2026-05-29 design decision "IaC Phase Ordering +
Role Model: Git mirror runs last"):
  bootstrap   Apply git-setup/B*__create_*.sql in sorted order. OPTIONAL
              in-Snowflake Git-mirror layer; presumes infra roles exist.
  infra       Apply infrastructure/V*__create_*.sql then R*.sql in order
  all         infra (V then R) FIRST, then bootstrap (B) LAST
  down        Apply paired drop scripts in REVERSE order: Git mirror (B)
              dropped FIRST, then infra (V) in reverse
              (combine with --from V005 to start from a given prefix)

Per-script rollback (no phase needed):
  --down --file V005   Apply scripts/rollback_sql.sh on V005's paired drop

Connection selection:
  --connection NAME    Pick the snow CLI connection (default: "admin").
                       B/V/R migrations all run as ACCOUNTADMIN via "admin".

.env is loaded via dotenv_values so child processes inherit any SNOWFLAKE_*
env vars (e.g., SNOWFLAKE_PASSWORD for the loader connection). The orchestrator
itself does not require any specific env vars; all connection credentials live
in ~/.snowflake/config.toml or are pulled from env by the snow CLI directly.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

from dotenv import dotenv_values

REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_SETUP_DIR = REPO_ROOT / "git-setup"
INFRA_DIR = REPO_ROOT / "infrastructure"
APPLY_SH = REPO_ROOT / "scripts" / "apply_sql.sh"
ROLLBACK_SH = REPO_ROOT / "scripts" / "rollback_sql.sh"
# Read-only preflight probe: the SHOW GRANTS statement lives in this
# version-controlled .sql file (never an inline Python string) so Python
# stays a pure executor. assert_admin_account_privileges runs it via
# `snow sql --filename ... --format json` and parses the ACCOUNT-scoped rows.
PREFLIGHT_GRANTS_SQL = REPO_ROOT / "scripts" / "sql" / "show_admin_account_grants.sql"

DEFAULT_CONNECTION = "admin"

# Single source of truth for the global (account-level) privileges that
# ARTWORK_ADMIN must hold. Keep this in lockstep with the
# "GRANT ... ON ACCOUNT TO ROLE ARTWORK_ADMIN" statements in
# infrastructure/V001__create_roles.sql. The bootstrap preflight
# (assert_admin_account_privileges) asserts this set immediately after V001
# applies and before V002 issues the first ARTWORK_ADMIN-owned CREATE
# WAREHOUSE, so any drift between this set and V001 fails fast with the exact
# remediation GRANT instead of a cryptic 003001 (42501) several scripts deep.
REQUIRED_ADMIN_ACCOUNT_PRIVILEGES = frozenset({
    "CREATE WAREHOUSE",
    "CREATE DATABASE",
    # "EXECUTE TASK",  # enable in lockstep with V001 for V009
})

logger = logging.getLogger("bootstrap")


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


def forward_scripts(phase: str) -> List[Path]:
    """
    Return ordered forward .sql files for the requested phase.

    Ordering rationale (2026-05-29 design decision "IaC Phase Ordering +
    Role Model: Git mirror runs last"):
      Core infrastructure (V then R) is applied BEFORE git-setup (B) so the
      role hierarchy created by infrastructure/V001__create_roles.sql exists
      before git-setup/B003__create_git_repository.sql runs its trailing
      "GRANT READ ON GIT REPOSITORY artwork_db TO ROLE ARTWORK_ADMIN;". The
      Snowflake GIT REPOSITORY object is an optional in-Snowflake execution
      convenience, not a change-tracking mechanism (GitHub already tracks
      every file), so it is layered on LAST. The locked B###/V###/R###
      filename convention is unchanged; only the apply order changed.
    """
    files: List[Path] = []
    if phase in ("infra", "all"):
        files.extend(sorted(INFRA_DIR.glob("V*__create_*.sql")))
        files.extend(sorted(INFRA_DIR.glob("R*.sql")))
    if phase in ("bootstrap", "all"):
        files.extend(sorted(GIT_SETUP_DIR.glob("B*__create_*.sql")))
    return files


def all_creates_reverse() -> List[Path]:
    """
    Return every B###/V### create script in REVERSE of the forward order.

    Teardown mirrors the 2026-05-29 design decision: because the forward
    "all" phase now applies infrastructure (V) first and the Git mirror (B)
    last, teardown must drop the Git mirror (B) FIRST, then infrastructure
    (V) in reverse. Building the list in forward create order (V creates,
    then B creates) and reversing yields exactly that: B003 -> B002 -> B001,
    then V009 -> ... -> V001. R*.sql scripts are repeatable and have no
    paired drop, so they are intentionally excluded here.
    """
    forward = sorted(INFRA_DIR.glob("V*__create_*.sql"))
    forward += sorted(GIT_SETUP_DIR.glob("B*__create_*.sql"))
    return list(reversed(forward))


def paired_drop_script(create_script: Path) -> Path:
    """
    Return the drop-script path paired with a given create-script.
    """
    return create_script.with_name(create_script.name.replace("__create_", "__drop_", 1))


def find_create_script(prefix: str) -> Path:
    """
    Locate the create script matching a prefix like 'V005' or 'B001'.
    """
    for directory in (GIT_SETUP_DIR, INFRA_DIR):
        matches = sorted(directory.glob(f"{prefix}__create_*.sql"))
        if matches:
            return matches[0]
    raise SystemExit(f"No create script found for prefix {prefix!r}")


def is_secret_bearing(sql_file: Path) -> bool:
    """
    Return True if a SQL file renders a secret (e.g. the GitHub PAT) inline.

    The Snowflake CLI echoes each rendered statement to stdout, so a script
    that substitutes the github_pat template into a CREATE/ALTER SECRET would
    print the PAT in cleartext. Detecting such scripts lets the apply path
    suppress stdout for them. See the 2026-05-29 design decision, section 6
    (PAT exposure). git-setup/B001__create_git_ops_db.sql is the only such
    script today, but matching on content keeps this robust to renames.
    """
    try:
        text = sql_file.read_text(encoding="utf-8")
    except OSError:
        return False
    return "secret" in text.lower() and "<% github_pat %>" in text


def run_script(
    wrapper: Path,
    sql_file: Path,
    env: Dict[str, str],
    conn: str,
    suppress_stdout: bool = False,
) -> None:
    """
    Invoke a bash wrapper on one .sql file; raise on non-zero exit.

    When suppress_stdout is True the wrapper is told (via SNOW_SUPPRESS_STDOUT)
    to discard the Snowflake CLI's stdout so a rendered secret statement never
    leaks the PAT to the terminal. stderr is preserved for genuine errors.
    """
    rel = sql_file.relative_to(REPO_ROOT)
    logger.info("==> %s [%s] %s", wrapper.name, conn, rel)
    merged_env = {**os.environ, **env, "SNOW_CONNECTION": conn}
    if suppress_stdout:
        merged_env["SNOW_SUPPRESS_STDOUT"] = "1"
        logger.info("    (stdout suppressed: secret-bearing script)")
    result = subprocess.run(
        [str(wrapper), str(sql_file), conn],
        cwd=str(REPO_ROOT),
        env=merged_env,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"{wrapper.name} failed on {rel} (exit {result.returncode})")
    logger.info("    OK")


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
            "infrastructure/V001__create_roles.sql):\n%s"
            % (", ".join(sorted(missing)), fixes)
        )
    logger.info(
        "Privilege preflight OK: ARTWORK_ADMIN holds %s",
        ", ".join(sorted(REQUIRED_ADMIN_ACCOUNT_PRIVILEGES)),
    )


def apply_phase(phase: str, env: Dict[str, str], conn: str) -> None:
    """
    Apply every forward script in the requested phase, in order.

    Secret-bearing scripts (see is_secret_bearing) are applied with stdout
    suppressed so the rendered PAT is never echoed.

    Account-level privilege preflight (2026-05-29 design decision, role
    model): the moment infrastructure/V001__create_roles.sql applies -- which
    is where ARTWORK_ADMIN and its account-level grants are created -- and
    BEFORE V002 issues the first ARTWORK_ADMIN-owned CREATE WAREHOUSE,
    assert_admin_account_privileges checks ARTWORK_ADMIN against
    REQUIRED_ADMIN_ACCOUNT_PRIVILEGES. This converts a cryptic 003001 (42501)
    several scripts deep into a single, immediate error carrying the exact
    remediation GRANT statements.
    """
    scripts = forward_scripts(phase)
    if not scripts:
        logger.warning("No forward scripts matched phase=%s", phase)
        return
    for script in scripts:
        run_script(
            APPLY_SH,
            script,
            env,
            conn,
            suppress_stdout=is_secret_bearing(script),
        )
        # Assert the account-level privilege contract as soon as V001 has
        # created ARTWORK_ADMIN, before V002 runs its first CREATE WAREHOUSE.
        if script.name.startswith("V001__create_"):
            assert_admin_account_privileges(env, conn)
    logger.info("Phase '%s' complete (%d script(s)).", phase, len(scripts))


def teardown(from_prefix: Optional[str], env: Dict[str, str], conn: str) -> None:
    """
    Apply paired drop scripts in REVERSE order, optionally from a prefix.
    """
    creates = all_creates_reverse()
    if from_prefix:
        creates = [c for c in creates if c.name >= f"{from_prefix}__"]
    applied = 0
    for create in creates:
        drop = paired_drop_script(create)
        if not drop.exists():
            logger.warning("Skipping %s: no paired drop script", create.name)
            continue
        run_script(ROLLBACK_SH, drop, env, conn)
        applied += 1
    logger.info("Teardown complete (%d script(s)).", applied)


def rollback_one(prefix: str, env: Dict[str, str], conn: str) -> None:
    """
    Apply the paired drop script for a single create-script prefix.
    """
    create = find_create_script(prefix)
    drop = paired_drop_script(create)
    if not drop.exists():
        raise SystemExit(f"No paired drop script for {create.name}")
    run_script(ROLLBACK_SH, drop, env, conn)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    """
    Parse CLI arguments.
    """
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--phase", choices=("bootstrap", "infra", "all", "down"))
    parser.add_argument("--from", dest="from_prefix",
                        help="Prefix to start teardown from (e.g. V005).")
    parser.add_argument("--down", action="store_true",
                        help="Roll back a single script paired with --file.")
    parser.add_argument("--file", dest="file_prefix",
                        help="Prefix for --down, e.g. V005 or B001.")
    parser.add_argument("--connection", default=DEFAULT_CONNECTION,
                        help='snow CLI connection name (default: "admin").')
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    """
    CLI entry point.
    """
    args = parse_args(argv)
    configure_logging(args.verbose)
    env = load_env()
    if args.down and args.file_prefix:
        rollback_one(args.file_prefix, env, args.connection)
    elif args.phase == "down":
        teardown(args.from_prefix, env, args.connection)
    elif args.phase in ("bootstrap", "infra", "all"):
        apply_phase(args.phase, env, args.connection)
    else:
        raise SystemExit(
            "Specify --phase {bootstrap|infra|all|down} "
            "or --down --file <PREFIX>."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
