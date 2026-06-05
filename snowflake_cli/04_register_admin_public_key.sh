#!/usr/bin/env bash
# ============================================================
# 04_register_admin_public_key.sh -- Register the admin RSA public key
# into the first available slot (dual-device aware).
#
# This script uses password auth via --temporary-connection to break the
# chicken-and-egg: the key pair we are registering cannot authenticate
# until this script succeeds. After it succeeds, JWT auth works end-to-end.
#
# Dual-device support:
#   Each Mac (or CI runner) generates its own RSA key pair. This script
#   computes the SHA-256 fingerprint of the local public key and passes it
#   to register_admin_public_key.sql, which uses Snowflake Scripting to:
#     1. Check if this key is already registered (no-op if so).
#     2. Pick the first empty slot (RSA_PUBLIC_KEY or RSA_PUBLIC_KEY_2).
#     3. If both slots are occupied by OTHER keys, overwrite slot 2.
#   Result: two devices can independently run --phase admin / --phase all
#   and both will authenticate without interfering with each other.
#
# Zero-export resolution order (handled by _lib.sh helpers):
#   SNOWFLAKE_ACCOUNT     env var -> [connections.admin].account in config.toml
#   SNOWFLAKE_ADMIN_USER  env var -> [connections.admin].user in config.toml
#   SNOWFLAKE_WAREHOUSE   env var -> [connections.admin].warehouse in
#                         config.toml -> default 'ARTWORK_WH'
#   SNOWFLAKE_PASSWORD    env var -> interactive `read -rs` prompt
#
# The admin password is needed 1-3 times per year (bootstrap + key
# rotations) and is intentionally never written to disk.
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/<profile>_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
#
# Idempotent: re-running with the same key is a no-op (fingerprint match).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

# Preflight: config.toml must exist with a seeded [connections.admin] block so
# the resolve_* helpers have something to read.
if [[ ! -f "${SNOW_LIB_CONFIG_TOML}" ]]; then
    echo "error: config.toml not found: ${SNOW_LIB_CONFIG_TOML}" >&2
    echo "       seed it first with:" >&2
    echo "           ./scripts/snowflake_cli/setup.sh --phase init-profile" >&2
    echo "       (or run --phase prereq / --phase all, which include it), then re-run." >&2
    exit 66
fi

ACCOUNT="$(resolve_admin_account)"
ADMIN_USER="$(resolve_admin_user)"
WAREHOUSE="$(resolve_admin_warehouse)"

PUBLIC_KEY_FILE="${ADMIN_PUBLIC_KEY_FILE:-$(admin_key_path pub)}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"

[[ -f "${PUBLIC_KEY_FILE}" ]] || { echo "error: public key not found: ${PUBLIC_KEY_FILE}" >&2; exit 66; }
[[ -f "${SQL_FILE}" ]]        || { echo "error: SQL file not found: ${SQL_FILE}"   >&2; exit 66; }

# Strip PEM header/footer/newlines so the key body fits in a single
# --variable value.
PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY_FILE}")"

# Compute the SHA-256 fingerprint matching Snowflake's format:
#   SHA256:<base64(sha256(DER-encoded-public-key))>
# The .pub file is PEM; openssl converts it to DER, then we hash + base64.
PUBKEY_FP="SHA256:$(openssl rsa -pubin -in "${PUBLIC_KEY_FILE}" -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | openssl base64 -A)"

echo "==> local public key fingerprint: ${PUBKEY_FP}"

# Prompt for the admin password if it was not pre-set (CI may pre-set it).
resolve_admin_password_interactive

echo "==> registering admin public key for user '${ADMIN_USER}' on account '${ACCOUNT}' (dual-slot aware)"
# Unset env vars that the snow CLI interprets as key-pair auth directives.
# Without this, --temporary-connection + --authenticator snowflake fails when
# the shell has SNOWFLAKE_PRIVATE_KEY_FILE exported (e.g. from sourcing .env
# for the loader). The env command creates a clean subprocess environment
# with ONLY the variables we explicitly pass.
#
# We pipe the SQL file via --stdin (-i) rather than --filename because snow sql
# v3.18+ splits --filename content on semicolons, which breaks Snowflake Scripting
# blocks (DECLARE...BEGIN...END). --stdin sends the entire content as one unit.
# The --variable / -D template engine still works with --stdin.
cat "${SQL_FILE}" | \
env -u SNOWFLAKE_PRIVATE_KEY_FILE \
    -u SNOWFLAKE_PRIVATE_KEY_PATH \
    -u PRIVATE_KEY_FILE \
    -u PRIVATE_KEY_PATH \
    -u SNOWFLAKE_ACCOUNT \
    -u SNOWFLAKE_USER \
    -u SNOWFLAKE_ROLE \
    -u SNOWFLAKE_WAREHOUSE \
    -u SNOWFLAKE_DATABASE \
    -u SNOWFLAKE_AUTHENTICATOR \
    SNOWFLAKE_PASSWORD="${SNOWFLAKE_PASSWORD}" \
snow sql \
    --stdin \
    --temporary-connection \
    --account       "${ACCOUNT}" \
    --user          "${ADMIN_USER}" \
    --role          ACCOUNTADMIN \
    --warehouse     "${WAREHOUSE}" \
    --authenticator snowflake \
    --variable      "admin_user=${ADMIN_USER}" \
    --variable      "rsa_public_key=${PUBKEY}" \
    --variable      "rsa_public_key_fp=${PUBKEY_FP}" \
    --enhanced-exit-codes

echo "==> admin public key registered (dual-slot); check output above for slot assignment"
