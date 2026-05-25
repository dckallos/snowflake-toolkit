#!/usr/bin/env bash
# ============================================================
# 04_register_admin_public_key.sh -- One-shot bootstrap: register the admin
# RSA public key against the admin Snowflake user using password auth.
#
# This is the ONLY snow CLI call in the project that uses password auth and
# the ONLY call that bypasses ~/.snowflake/config.toml (every connection
# parameter is passed on the command line). After this call succeeds, the
# JWT-based 'admin' connection in config.toml works end-to-end and every
# subsequent snow sql call uses '-c admin --filename ...'.
#
# Required env:
#   SNOWFLAKE_ACCOUNT     account locator (no protocol, no .snowflakecomputing.com)
#   SNOWFLAKE_ADMIN_USER  admin user that owns the ACCOUNTADMIN grant
#   SNOWFLAKE_PASSWORD    admin temporary password (used ONLY for this call)
#
# Optional env:
#   SNOWFLAKE_WAREHOUSE   defaults to ARTWORK_WH
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
#
# Idempotent: ALTER USER ... SET RSA_PUBLIC_KEY with the same value is a
# no-op; re-running with a new key value rotates the credential.
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT is required}"
: "${SNOWFLAKE_ADMIN_USER:?SNOWFLAKE_ADMIN_USER is required}"
: "${SNOWFLAKE_PASSWORD:?SNOWFLAKE_PASSWORD (admin temp password) is required}"

WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-ARTWORK_WH}"
PUBLIC_KEY_FILE="${ADMIN_PUBLIC_KEY_FILE:-${HOME}/.snowflake/keys/admin_rsa_key.pub}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"

[[ -f "${PUBLIC_KEY_FILE}" ]] || { echo "error: public key not found: ${PUBLIC_KEY_FILE}" >&2; exit 66; }
[[ -f "${SQL_FILE}" ]]        || { echo "error: SQL file not found: ${SQL_FILE}"   >&2; exit 66; }

# Strip PEM header/footer/newlines so the key body fits in a single
# --variable value.
PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY_FILE}")"

echo "==> registering admin public key for user '${SNOWFLAKE_ADMIN_USER}' on account '${SNOWFLAKE_ACCOUNT}'"
SNOWFLAKE_PASSWORD="${SNOWFLAKE_PASSWORD}" \
snow sql \
    --account       "${SNOWFLAKE_ACCOUNT}" \
    --user          "${SNOWFLAKE_ADMIN_USER}" \
    --role          ACCOUNTADMIN \
    --warehouse     "${WAREHOUSE}" \
    --authenticator snowflake \
    --filename      "${SQL_FILE}" \
    --variable      "admin_user=${SNOWFLAKE_ADMIN_USER}" \
    --variable      "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

echo "==> admin public key registered; RSA_PUBLIC_KEY_FP populated"
