#!/usr/bin/env bash
# ============================================================
# rollback_sql.sh -- Apply one drop (rollback) .sql file via the Snowflake CLI.
#
# Usage:
#   scripts/rollback_sql.sh path/to/V005__drop_stages.sql [connection]
#
# Every drop script is idempotent (DROP IF EXISTS / DROP ROLE IF EXISTS),
# so this is always safe to invoke, even if the paired create script was
# never applied. Connection selection mirrors apply_sql.sh.
# ============================================================
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <path/to/drop_file.sql> [connection_name]" >&2
    exit 64
fi

SQL_FILE="$1"
CONN="${2:-${SNOW_CONNECTION:-admin}}"

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "error: file not found: ${SQL_FILE}" >&2
    exit 66
fi

echo "==> snow sql --connection ${CONN} --filename ${SQL_FILE}  [ROLLBACK]"
exec snow sql \
    --connection "${CONN}" \
    --filename "${SQL_FILE}" \
    -D "github_pat=${GITHUB_PAT}" \
    --enhanced-exit-codes
