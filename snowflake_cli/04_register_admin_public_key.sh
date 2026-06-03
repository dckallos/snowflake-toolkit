#!/usr/bin/env bash
# ============================================================
# 04_register_admin_public_key.sh -- One-shot bootstrap: register the admin
# RSA public key against the admin Snowflake user using password auth.
#
# This is the ONLY snow CLI call in the project that uses password auth and
# the ONLY call that bypasses ~/.snowflake/config.toml for connection
# definition (every connection parameter is passed on the command line).
# After this call succeeds, the JWT-based 'admin' connection in
# config.toml works end-to-end and every subsequent snow sql call uses
# '-c admin --filename ...'.
#
# Zero-export resolution order (handled by _lib.sh helpers):
#   SNOWFLAKE_ACCOUNT     env var -> [connections.admin].account in config.toml
#   SNOWFLAKE_ADMIN_USER  env var -> [connections.admin].user in config.toml
#   SNOWFLAKE_WAREHOUSE   env var -> [connections.admin].warehouse in
#                         config.toml -> default 'ARTWORK_WH'
#   SNOWFLAKE_PASSWORD    env var -> interactive `read -rs` prompt
#
# The admin password is needed 1-3 times per year (bootstrap + key
# rotations) and is intentionally never written to disk. After this script
# returns, JWT auth takes over for every subsequent snow CLI invocation.
#
# Why `--temporary-connection`: without it, `snow sql` loads the default
# connection from ~/.snowflake/config.toml ([connections.admin], which
# already references private_key_file) and merges the CLI flags on top.
# The CLI then refuses to combine a populated private_key_file with
# `--authenticator snowflake` ("Private Key authentication requires
# authenticator set to SNOWFLAKE_JWT"). `--temporary-connection` (alias
# `-x`) builds the connection PURELY from CLI flags and ignores every
# named connection in config.toml, which is exactly the semantic we want
# for this single password-auth bootstrap call.
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
#
# Idempotent: ALTER USER ... SET RSA_PUBLIC_KEY with the same value is a
# no-op; re-running with a new key value rotates the credential.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

# Preflight: config.toml must exist with a seeded [connections.admin] block so
# the resolve_* helpers have something to read. A missing file yields the
# actionable init-profile hint rather than three separate bare resolve errors.
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

# Prompt for the admin password if it was not pre-set (CI may pre-set it).
resolve_admin_password_interactive

echo "==> registering admin public key for user '${ADMIN_USER}' on account '${ACCOUNT}'"
SNOWFLAKE_PASSWORD="${SNOWFLAKE_PASSWORD}" \
snow sql \
    --temporary-connection \
    --account       "${ACCOUNT}" \
    --user          "${ADMIN_USER}" \
    --role          ACCOUNTADMIN \
    --warehouse     "${WAREHOUSE}" \
    --authenticator snowflake \
    --filename      "${SQL_FILE}" \
    --variable      "admin_user=${ADMIN_USER}" \
    --variable      "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

echo "==> admin public key registered; RSA_PUBLIC_KEY_FP populated"
