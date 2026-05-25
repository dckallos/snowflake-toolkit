#!/usr/bin/env bash
# ============================================================
# 05_verify_admin_jwt.sh -- Verify the JWT-based 'admin' connection.
#
# Three independent checks:
#   1. Re-apply register_admin_public_key.sql via `snow sql -c admin`
#      (forces the JWT auth path; the ALTER USER is a no-op when the key
#      is unchanged).
#   2. `snow connection test -c admin` (full handshake + role/warehouse).
#   3. Round-trip a CURRENT_USER / CURRENT_ROLE query.
#
# If all three succeed, key-pair auth is healthy and `make iac` will work
# end-to-end.
#
# Required env:
#   SNOWFLAKE_ADMIN_USER  admin user (used for the idempotency re-run)
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${SNOWFLAKE_ADMIN_USER:?SNOWFLAKE_ADMIN_USER is required}"

PUBLIC_KEY_FILE="${ADMIN_PUBLIC_KEY_FILE:-${HOME}/.snowflake/keys/admin_rsa_key.pub}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"

[[ -f "${PUBLIC_KEY_FILE}" ]] || { echo "error: public key not found: ${PUBLIC_KEY_FILE}" >&2; exit 66; }
[[ -f "${SQL_FILE}" ]]        || { echo "error: SQL file not found: ${SQL_FILE}"   >&2; exit 66; }

PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY_FILE}")"

echo "==> JWT auth check: re-apply register_admin_public_key.sql via -c admin"
snow sql -c admin \
    --filename "${SQL_FILE}" \
    --variable "admin_user=${SNOWFLAKE_ADMIN_USER}" \
    --variable "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

echo
echo "==> snow connection test -c admin"
snow connection test -c admin

echo
echo "==> CURRENT_USER / CURRENT_ROLE round-trip"
snow sql -c admin -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"

echo
echo "==> admin JWT connection verified"
