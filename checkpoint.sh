#!/usr/bin/env bash
# ============================================================
# scripts/checkpoint.sh -- WRITE a durable run checkpoint into BRONZE.RUN_CONTROL.
# Standalone: NOT part of `make infra` / the orchestrator (this is operational
# DML, not DDL). The companion read-side is scripts/sql/show_run_control.sql.
#
# Usage:
#   scripts/checkpoint.sh <run_id> <step> [status] [note]
#
# Examples:
#   scripts/checkpoint.sh 2026-05-31-recon audit        in_progress "started provenance audit"
#   scripts/checkpoint.sh 2026-05-31-recon audit        done        "18 files clean, 0 off-spec"
#   scripts/checkpoint.sh 2026-05-31-recon apply        done        "make infra applied; control/snapshot/worklist/task created"
#
# Defaults: status=in_progress, note="" (empty).
# Connection: ARTWORK_SNOW_CONN env var, else "admin".
# Requires BRONZE.RUN_CONTROL to exist -> run `make infra` first.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONN="${ARTWORK_SNOW_CONN:-admin}"

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "usage: $0 <run_id> <step> [status] [note]" >&2
  echo "  status default: in_progress   note default: (empty)" >&2
  exit 64
fi

RUN_ID="$1"
STEP="$2"
STATUS="${3:-in_progress}"
NOTE="${4:-}"
SQL_FILE="${REPO_ROOT}/scripts/sql/checkpoint.sql"

if [[ ! -f "${SQL_FILE}" ]]; then
  echo "ERROR: SQL file not found: ${SQL_FILE}" >&2
  exit 66
fi

echo "==> checkpoint.sh [conn:${CONN}] run_id=${RUN_ID} step=${STEP} status=${STATUS}"
exec snow sql \
  --connection "${CONN}" \
  --filename "${SQL_FILE}" \
  -D "run_id=${RUN_ID}" \
  -D "step=${STEP}" \
  -D "status=${STATUS}" \
  -D "note=${NOTE}" \
  --enhanced-exit-codes
