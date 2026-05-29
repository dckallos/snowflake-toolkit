#!/usr/bin/env bash
# ============================================================
# apply_sql.sh -- Apply one forward .sql file via the Snowflake CLI.
#
# Usage:
#   scripts/apply_sql.sh path/to/V005__create_stages.sql [connection]
#
# Connection selection precedence:
#   1. $2 (CLI argument)
#   2. $SNOW_CONNECTION (env var)
#   3. "admin" (default; B###/V###/R### all run as ACCOUNTADMIN)
#
# The Snowflake CLI reads its connection definition (account, user, role,
# warehouse, authenticator, private_key_file) from ~/.snowflake/config.toml.
# See the Snowflake CLI config.toml setup sub-page linked from Phase 0.6.
#
# --enhanced-exit-codes returns 5 on any query execution failure; without it,
# `snow sql --filename` only reports the exit status of the LAST statement,
# which is unsafe for multi-statement migration files. Refs:
#   https://docs.snowflake.com/en/developer-guide/snowflake-cli/command-reference/sql-commands/sql
#   https://github.com/snowflakedb/snowflake-cli/issues/2071
# ============================================================
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <path/to/file.sql> [connection_name]" >&2
    exit 64
fi

SQL_FILE="$1"
CONN="${2:-${SNOW_CONNECTION:-admin}}"

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "error: file not found: ${SQL_FILE}" >&2
    exit 66
fi

# Secret-bearing applies (e.g. B001 renders the GitHub PAT into a
# CREATE OR REPLACE SECRET) set SNOW_SUPPRESS_STDOUT=1 so the Snowflake CLI's
# per-statement echo -- which would otherwise print the rendered PAT in
# cleartext to the terminal and chat scrollback -- is discarded. stderr is
# preserved so genuine errors stay visible; Snowflake compilation/permission
# errors reference object names, not the secret value. scripts/bootstrap.py
# sets this flag automatically for any script that substitutes the github_pat
# template into a SECRET statement. See the 2026-05-29 design decision,
# section 6 (PAT exposure).
if [[ "${SNOW_SUPPRESS_STDOUT:-0}" == "1" ]]; then
    echo "==> snow sql --connection ${CONN} --filename ${SQL_FILE}  [secret apply: stdout suppressed]"
    if ! snow sql \
        --connection "${CONN}" \
        --filename "${SQL_FILE}" \
        -D "github_pat=${GITHUB_PAT}" \
        --enhanced-exit-codes \
        >/dev/null; then
        echo "error: secret apply failed for ${SQL_FILE}." >&2
        echo "       stdout was suppressed to avoid leaking the PAT; inspect" >&2
        echo "       the Snowflake query history for the failing statement." >&2
        exit 5
    fi
else
    echo "==> snow sql --connection ${CONN} --filename ${SQL_FILE}"
    exec snow sql \
        --connection "${CONN}" \
        --filename "${SQL_FILE}" \
        -D "github_pat=${GITHUB_PAT}" \
        --enhanced-exit-codes
fi
