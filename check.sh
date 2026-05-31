#!/usr/bin/env bash
# scripts/check.sh -- run an ad-hoc, READ-ONLY SQL check against Snowflake via the
# Snowflake CLI. Standalone: NOT part of `make infra` / the orchestrator.
#
# Usage:
#   scripts/check.sh                          # default check: scripts/sql/show_active_sessions.sql
#   scripts/check.sh scripts/sql/foo.sql      # run any SQL file (path relative to repo root or absolute)
#   ARTWORK_SNOW_CONN=myconn scripts/check.sh # override connection (default: admin)
#
# Drop new *.sql checks into scripts/sql/ and pass the path. Keep them read-only;
# this wrapper is for inspection, not for DDL (DDL goes through `make infra`).
set -euo pipefail

# Resolve repo root from this script's location so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONN="${ARTWORK_SNOW_CONN:-admin}"
SQL_ARG="${1:-scripts/sql/show_active_sessions.sql}"

# Accept absolute paths as-is; otherwise resolve relative to the repo root.
if [[ "${SQL_ARG}" = /* ]]; then
  SQL_FILE="${SQL_ARG}"
else
  SQL_FILE="${REPO_ROOT}/${SQL_ARG}"
fi

if [[ ! -f "${SQL_FILE}" ]]; then
  echo "ERROR: SQL file not found: ${SQL_FILE}" >&2
  echo "Hint: pass a path relative to the repo root, e.g. scripts/sql/show_active_sessions.sql" >&2
  exit 1
fi

echo "==> check.sh [connection: ${CONN}] ${SQL_FILE}"
exec snow sql --connection "${CONN}" --filename "${SQL_FILE}" --enhanced-exit-codes
