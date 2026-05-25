#!/usr/bin/env python3
"""Thin orchestrator for the OpenAccess Artwork Medallion Pipeline IaC.

Does NOT execute SQL. Discovers .sql files in sorted order and shells out
to scripts/apply_sql.sh (forward) or scripts/rollback_sql.sh (paired drop),
one file at a time. The Snowflake CLI (snow) is the only thing that talks to
Snowflake; it reads connection details from ~/.snowflake/config.toml.

Phases:
  bootstrap   Apply git-setup/B*__create_*.sql in sorted order
  infra       Apply infrastructure/V*__create_*.sql then R*.sql in order
  all         bootstrap, then infra
  down        Apply paired drop scripts in REVERSE order
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

DEFAULT_CONNECTION = "admin"

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
    """
    files: List[Path] = []
    if phase in ("bootstrap", "all"):
        files.extend(sorted(GIT_SETUP_DIR.glob("B*__create_*.sql")))
    if phase in ("infra", "all"):
        files.extend(sorted(INFRA_DIR.glob("V*__create_*.sql")))
        files.extend(sorted(INFRA_DIR.glob("R*.sql")))
    return files


def all_creates_reverse() -> List[Path]:
    """
    Return every B###/V### create script in REVERSE order (for teardown).
    """
    files = sorted(INFRA_DIR.glob("V*__create_*.sql"))
    files += sorted(GIT_SETUP_DIR.glob("B*__create_*.sql"))
    return list(reversed(files))


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


def run_script(wrapper: Path, sql_file: Path, env: Dict[str, str], conn: str) -> None:
    """
    Invoke a bash wrapper on one .sql file; raise on non-zero exit.
    """
    rel = sql_file.relative_to(REPO_ROOT)
    logger.info("==> %s [%s] %s", wrapper.name, conn, rel)
    merged_env = {**os.environ, **env, "SNOW_CONNECTION": conn}
    result = subprocess.run(
        [str(wrapper), str(sql_file), conn],
        cwd=str(REPO_ROOT),
        env=merged_env,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"{wrapper.name} failed on {rel} (exit {result.returncode})")
    logger.info("    OK")


def apply_phase(phase: str, env: Dict[str, str], conn: str) -> None:
    """
    Apply every forward script in the requested phase, in order.
    """
    scripts = forward_scripts(phase)
    if not scripts:
        logger.warning("No forward scripts matched phase=%s", phase)
        return
    for script in scripts:
        run_script(APPLY_SH, script, env, conn)
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
