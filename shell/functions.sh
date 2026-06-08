#!/usr/bin/env bash
# =============================================================================
# shell/functions.sh -- Sourceable shell functions for snowflake-toolkit
# =============================================================================
# Source this file in your .zshrc or .bashrc:
#
#   source ~/dev/snowflake-toolkit/shell/functions.sh
#
# Provides:
#   check <sql-file> [--connection <name>]   -- Run a read-only SQL check
#   checkpoint <run_id> <step> [status] [note] -- Write a run checkpoint
#
# Design principles:
#   - Paths resolve relative to CWD (not toolkit root)
#   - Uses snow CLI default connection unless --connection is passed
#   - Zero configuration beyond the source line
#   - Works from any project directory (artwork-db, other repos, etc.)
# =============================================================================

# ---------------------------------------------------------------------------
# check -- Run a read-only SQL file against Snowflake
# ---------------------------------------------------------------------------
# Usage:
#   check scripts/sql/check_aic_bronze.sql
#   check scripts/sql/check_aic_bronze.sql --connection mk07348
#   check  (no args = list available SQL files in scripts/sql/)
#
# Path resolution:
#   - Absolute paths: used as-is
#   - Relative paths: resolved from CWD
#   - Bare filenames (no /): searched in ./scripts/sql/ then CWD
# ---------------------------------------------------------------------------
check() {
  local sql_file=""
  local connection=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --connection|-c)
        connection="$2"
        shift 2
        ;;
      -*)
        echo "check: unknown option $1" >&2
        echo "Usage: check <sql-file> [--connection <name>]" >&2
        return 1
        ;;
      *)
        sql_file="$1"
        shift
        ;;
    esac
  done

  # No file argument: list available checks
  if [[ -z "${sql_file}" ]]; then
    echo "Available SQL checks in ./scripts/sql/:"
    if [[ -d "./scripts/sql" ]]; then
      ls -1 ./scripts/sql/*.sql 2>/dev/null | sed 's|^\./||' || echo "  (none found)"
    else
      echo "  (no scripts/sql/ directory in CWD)"
    fi
    echo ""
    echo "Usage: check <sql-file> [--connection <name>]"
    return 0
  fi

  # Resolve path
  local resolved=""
  if [[ "${sql_file}" = /* ]]; then
    # Absolute path
    resolved="${sql_file}"
  elif [[ "${sql_file}" == */* ]]; then
    # Relative path with directory component -- resolve from CWD
    resolved="$(pwd)/${sql_file}"
  else
    # Bare filename -- search scripts/sql/ first, then CWD
    if [[ -f "./scripts/sql/${sql_file}" ]]; then
      resolved="$(pwd)/scripts/sql/${sql_file}"
    elif [[ -f "./${sql_file}" ]]; then
      resolved="$(pwd)/${sql_file}"
    else
      resolved="$(pwd)/${sql_file}"
    fi
  fi

  if [[ ! -f "${resolved}" ]]; then
    echo "check: file not found: ${resolved}" >&2
    echo "Hint: run from repo root, or pass an absolute path" >&2
    return 1
  fi

  # Build snow command
  local cmd=(snow sql --filename "${resolved}" --enhanced-exit-codes)
  if [[ -n "${connection}" ]]; then
    cmd+=(--connection "${connection}")
  fi

  echo "==> check [${connection:-default}] ${resolved##*/}"
  "${cmd[@]}"
}

# ---------------------------------------------------------------------------
# checkpoint -- Write a run checkpoint to BRONZE.RUN_CONTROL
# ---------------------------------------------------------------------------
# Usage:
#   checkpoint <run_id> <step> [status] [note]
#   checkpoint abc123 extract_start running "Starting AIC extraction"
#   checkpoint abc123 extract_end done
# ---------------------------------------------------------------------------
checkpoint() {
  local run_id="${1:-}"
  local step="${2:-}"
  local status="${3:-running}"
  local note="${4:-}"
  local connection=""

  if [[ -z "${run_id}" || -z "${step}" ]]; then
    echo "Usage: checkpoint <run_id> <step> [status] [note] [--connection <name>]" >&2
    return 1
  fi

  # Check for trailing --connection
  shift 2  # consumed run_id and step
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --connection|-c)
        connection="$2"
        shift 2
        ;;
      *)
        if [[ -z "${status}" || "${status}" == "running" ]]; then
          status="$1"
        else
          note="$1"
        fi
        shift
        ;;
    esac
  done

  local sql="MERGE INTO ARTWORK_DB.BRONZE.RUN_CONTROL t
USING (SELECT '${run_id}' AS run_id, '${step}' AS step) s
  ON t.run_id = s.run_id AND t.step = s.step
WHEN MATCHED THEN UPDATE SET status='${status}', note='${note}', updated_at=CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (run_id, step, status, note) VALUES (s.run_id, s.step, '${status}', '${note}');"

  local cmd=(snow sql --query "${sql}")
  if [[ -n "${connection}" ]]; then
    cmd+=(--connection "${connection}")
  fi

  echo "==> checkpoint [${run_id}/${step}] ${status}"
  "${cmd[@]}"
}
