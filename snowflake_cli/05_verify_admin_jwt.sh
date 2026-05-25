#!/usr/bin/env bash
# ============================================================
# 05_verify_admin_jwt.sh -- Verify the JWT-based 'admin' connection.
#
# Warehouse-independent verification. This script runs BEFORE `make iac`
# creates ARTWORK_WH, so it deliberately avoids any operation that would
# trigger an implicit USE WAREHOUSE during session establishment.
#
# Two checks:
#   1. Re-apply register_admin_public_key.sql via `snow sql -c admin<br>#      --filename ...`. Exercises the JWT auth path end-to-end. ALTER
#      USER and DESCRIBE USER are metadata commands that do not require
#      compute, so they succeed even when [connections.admin].warehouse
#      points at a not-yet-created warehouse. The ALTER USER itself is
#      a no-op when the key is unchanged.
#   2. `snow sql -c admin -q "SHOW USERS LIKE '<admin>'"`. A metadata
#      command (no warehouse compute) that confirms the authenticated
#      session can see the user via ACCOUNTADMIN.
#
# What this script intentionally does NOT do:
#   - `snow connection test -c admin`. This command issues a warehouse-
#     using probe and fails before ARTWORK_WH exists with:
#       "Could not use warehouse 'ARTWORK_WH'. Object does not exist."
#     Run it manually AFTER `make iac` to get the friendly Status: OK
#     summary.
#   - `SELECT CURRENT_USER(), CURRENT_ROLE()`. Snowflake routes scalar
#     SELECT through a warehouse even when the projection is session-
#     context only, so this also fails pre-iac. The same identity is
#     visible in the SHOW USERS metadata output.
#
# Zero-export resolution order (handled by _lib.sh helpers):
#   SNOWFLAKE_ADMIN_USER  env var -> [connections.admin].user in config.toml
#
# No password is needed -- this script exercises JWT auth via the 'admin'
# connection defined in ~/.snowflake/config.toml.
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

ADMIN_USER="$(resolve_admin_user)"

PUBLIC_KEY_FILE="${ADMIN_PUBLIC_KEY_FILE:-${HOME}/.snowflake/keys/admin_rsa_key.pub}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"

[[ -f "${PUBLIC_KEY_FILE}" ]] || { echo "error: public key not found: ${PUBLIC_KEY_FILE}" >&2; exit 66; }
[[ -f "${SQL_FILE}" ]]        || { echo "error: SQL file not found: ${SQL_FILE}"   >&2; exit 66; }

PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY_FILE}")"

echo "==> JWT auth check 1/2: re-apply register_admin_public_key.sql via -c admin"
snow sql -c admin \
    --filename "${SQL_FILE}" \
    --variable "admin_user=${ADMIN_USER}" \
    --variable "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

echo
echo "==> JWT auth check 2/2: SHOW USERS LIKE '${ADMIN_USER}' (metadata only, no warehouse)"
snow sql -c admin -q "SHOW USERS LIKE '${ADMIN_USER}';"

echo
echo "==> admin JWT connection verified (warehouse-independent)."
echo "    note: 'snow connection test -c admin' is intentionally skipped here"
echo "    because it requires ARTWORK_WH, which is created by 'make iac'."
echo "    Run it after 'make iac' to get the full Status: OK handshake."
