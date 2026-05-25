#!/usr/bin/env bash
# ============================================================
# 06_rotate_loader_password.sh -- Rotate the ARTWORK_LOADER_SVC password
# via the admin (JWT) connection.
#
# Applies git-setup/operator/rotate_loader_password.sql with the new
# password passed as a runtime --variable. The .sql file itself never sees
# a literal credential; the variable is supplied from the operator's shell.
#
# Required env:
#   LOADER_NEW_PASSWORD   strong random value (also copy to .env afterwards)
#
# Optional env:
#   LOADER_USER           defaults to artwork_loader_svc
#   SQL_FILE              defaults to git-setup/operator/rotate_loader_password.sql
#
# Prerequisite:
#   `make iac` must have already applied V008__create_service_user.sql so
#   the user exists. This script does NOT create the user; it only rotates.
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${LOADER_NEW_PASSWORD:?LOADER_NEW_PASSWORD is required}"

LOADER_USER="${LOADER_USER:-artwork_loader_svc}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/rotate_loader_password.sql}"

[[ -f "${SQL_FILE}" ]] || { echo "error: SQL file not found: ${SQL_FILE}" >&2; exit 66; }

echo "==> rotating password for ${LOADER_USER}"
snow sql -c admin \
    --filename "${SQL_FILE}" \
    --variable "loader_user=${LOADER_USER}" \
    --variable "loader_password=${LOADER_NEW_PASSWORD}" \
    --enhanced-exit-codes

cat <<EOF

==> loader password rotated.
    Update .env with:
        SNOWFLAKE_PASSWORD=${LOADER_NEW_PASSWORD}
    (consumed by the Phase 1A extractor AND the snow CLI 'loader' connection
    via env-var precedence).
EOF
