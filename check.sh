#!/usr/bin/env bash
# =============================================================================
# check.sh -- Run an ad-hoc, READ-ONLY SQL check against Snowflake.
# =============================================================================
# Standalone utility. NOT part of `make infra` or the orchestrator.
# Keep SQL files read-only; this is for inspection, not DDL.
#
# USAGE:
#   check <sql-file>                         # uses snow CLI default connection
#   check <sql-file> --connection mk07348    # explicit connection
#   check                                    # default: sql/show_active_sessions.sql
#
# PATH RESOLUTION:
#   Relative paths resolve from your current working directory.
#   Absolute paths are used as-is.
#   If no file is given, falls back to the toolkit's own default check.
#
# CONNECTION RESOLUTION (priority order):
#   1. --connection <name>         (explicit flag)
#   2. Snow CLI default connection (from ~/.snowflake/config.toml)
#   3. ARTWORK_SNOW_CONN env var   (legacy fallback)
#
# SHELL FUNCTION (add to ~/.bashrc or ~/.zshrc):
#   check() { bash ~/dev/snowflake-toolkit/check.sh "$@"; }
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
SQL_ARG=""
CONN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --connection|-c)
            CONN="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '/^# USAGE:/,/^# =====/{ /^# =====/d; s/^# \{0,2\}//; p }' "$0"
            exit 0
            ;;
        *)
            SQL_ARG="$1"
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Resolve connection
# -----------------------------------------------------------------------------
if [[ -z "${CONN}" ]]; then
    # Try snow CLI default connection
    if command -v snow >/dev/null 2>&1; then
        CONN=$(snow connection list --format json 2>/dev/null \
            | python3 -c "import sys,json; conns=json.load(sys.stdin); print(next((c['connection_name'] for c in conns if c.get('is_default')), ''))" 2>/dev/null) || CONN=""
    fi
fi

# Legacy fallback
if [[ -z "${CONN}" ]]; then
    CONN="${ARTWORK_SNOW_CONN:-}"
fi

if [[ -z "${CONN}" ]]; then
    echo "ERROR: No connection resolved." >&2
    echo "  Options:" >&2
    echo "    check <file> --connection <name>" >&2
    echo "    snow connection set-default <name>" >&2
    echo "    export ARTWORK_SNOW_CONN=<name>" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Resolve SQL file path
# -----------------------------------------------------------------------------
if [[ -z "${SQL_ARG}" ]]; then
    # Default: toolkit's own active-sessions check
    SQL_FILE="${SCRIPT_DIR}/sql/show_active_sessions.sql"
elif [[ "${SQL_ARG}" = /* ]]; then
    # Absolute path: use as-is
    SQL_FILE="${SQL_ARG}"
else
    # Relative path: resolve from caller's CWD
    SQL_FILE="$(pwd)/${SQL_ARG}"
fi

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "ERROR: SQL file not found: ${SQL_FILE}" >&2
    echo "  Looked for: ${SQL_ARG}" >&2
    echo "  Resolved from CWD: $(pwd)" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Execute
# -----------------------------------------------------------------------------
echo "==> check [${CONN}] $(basename "${SQL_FILE}")"
exec snow sql --connection "${CONN}" --filename "${SQL_FILE}" --enhanced-exit-codes
