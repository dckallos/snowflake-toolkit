#!/usr/bin/env bash
# ============================================================
# 09_setup_transformer_keypair.sh -- Establish KEY-PAIR auth for the
# ARTWORK_TRANSFORMER_SVC service user (the dbt / artwork_pipeline identity).
# Mirrors 06_setup_loader_keypair.sh. Fully automated; invoked by
# `setup.sh --phase transformer`.
#
# Three actions, in order:
#   1. Generate the transformer RSA key pair LAZILY (only if missing):
#         ~/.snowflake/keys/<TRANSFORMER_CONN>_rsa_key.p8   (PKCS#8, chmod 600)
#         ~/.snowflake/keys/<TRANSFORMER_CONN>_rsa_key.pub  (PEM,     chmod 644)
#   2. Register the public key on the service user by applying
#      git-setup/operator/register_transformer_public_key.sql via the ADMIN JWT
#      connection (`snow sql -c <admin> ...`). No password one-shot is needed --
#      a working admin JWT connection already exists.
#   3. Rewrite [connections.<TRANSFORMER_CONN>] in ~/.snowflake/config.toml to use
#      key-pair auth (authenticator = SNOWFLAKE_JWT, private_key_file = the .p8),
#      using the insert-if-missing helper (additive; other sections untouched).
#
# Prerequisites:
#   - `make iac` must have already applied create_service_user.sql so
#     ARTWORK_TRANSFORMER_SVC (TYPE = SERVICE) exists.
#   - The admin JWT connection must already work (setup.sh --phase admin).
#
# Optional env:
#   TRANSFORMER_USER          defaults to ARTWORK_TRANSFORMER_SVC
#   TRANSFORMER_PRIVATE_KEY   defaults to ~/.snowflake/keys/<conn>_rsa_key.p8
#   TRANSFORMER_PUBLIC_KEY    defaults to ~/.snowflake/keys/<conn>_rsa_key.pub
#   OVERWRITE_TRANSFORMER_KEY set to 1 to force-rotate an existing private key
#   SQL_FILE                  defaults to
#                             git-setup/operator/register_transformer_public_key.sql
#
# Idempotent: re-running with an unchanged key is a no-op. Re-running with
# OVERWRITE_TRANSFORMER_KEY=1 rotates the credential.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

TRANSFORMER_USER="${TRANSFORMER_USER:-ARTWORK_TRANSFORMER_SVC}"
KEY_DIR="${SNOW_LIB_KEY_DIR}"
PRIVATE_KEY="${TRANSFORMER_PRIVATE_KEY:-$(transformer_key_path p8)}"
PUBLIC_KEY="${TRANSFORMER_PUBLIC_KEY:-$(transformer_key_path pub)}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_transformer_public_key.sql}"
CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"

[[ -f "${SQL_FILE}" ]] || { echo "error: SQL file not found: ${SQL_FILE}" >&2; exit 66; }

# --- 1. Generate the transformer key pair lazily -------------------------------
mkdir -p "${KEY_DIR}"
if [[ -f "${PRIVATE_KEY}" && "${OVERWRITE_TRANSFORMER_KEY:-0}" != "1" ]]; then
    echo "==> transformer private key already exists at ${PRIVATE_KEY} (set OVERWRITE_TRANSFORMER_KEY=1 to rotate)"
else
    echo "==> generating PKCS#8 transformer RSA key pair"
    openssl genrsa 2048 \
        | openssl pkcs8 -topk8 -inform PEM -out "${PRIVATE_KEY}" -nocrypt
    openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"
    chmod 600 "${PRIVATE_KEY}"
    chmod 644 "${PUBLIC_KEY}"
    ls -l "${PRIVATE_KEY}" "${PUBLIC_KEY}"
fi

[[ -f "${PUBLIC_KEY}" ]] || { echo "error: transformer public key not found: ${PUBLIC_KEY}" >&2; exit 66; }

# Strip PEM header/footer/newlines so the key body fits in a single
# --variable value (same transform as the admin/loader scripts).
PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY}")"

# --- 2. Register the public key via the admin JWT connection --------------
echo "==> registering transformer public key for user '${TRANSFORMER_USER}' via -c ${SNOW_LIB_ADMIN_CONN}"
snow sql -c "${SNOW_LIB_ADMIN_CONN}" \
    --filename "${SQL_FILE}" \
    --variable "transformer_user=${TRANSFORMER_USER}" \
    --variable "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

# --- 3. Point [connections.<transformer>] at key-pair auth ----------------
# Resolve the account from the admin connection (the transformer shares it).
ACCOUNT="$(resolve_admin_account)"

echo "==> updating [connections.${SNOW_LIB_TRANSFORMER_CONN}] in ${CONFIG_TOML} for key-pair auth"
upsert_toml_value_in_section "connections.${SNOW_LIB_TRANSFORMER_CONN}" 'account'          "${ACCOUNT}"           "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_TRANSFORMER_CONN}" 'user'             "${TRANSFORMER_USER}" "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_TRANSFORMER_CONN}" 'authenticator'    'SNOWFLAKE_JWT'       "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_TRANSFORMER_CONN}" 'private_key_file' "${PRIVATE_KEY}"      "${CONFIG_TOML}"

cat <<EOF

==> transformer key-pair auth established.
    User:            ${TRANSFORMER_USER} (TYPE = SERVICE, key-pair only)
    Private key:     ${PRIVATE_KEY}
    config.toml:     [connections.${SNOW_LIB_TRANSFORMER_CONN}] now uses authenticator = SNOWFLAKE_JWT

    For dbt (artwork_pipeline), set in .env (no password at rest):
        DBT_SNOWFLAKE_USER=${TRANSFORMER_USER}
        DBT_SNOWFLAKE_PRIVATE_KEY_PATH=${PRIVATE_KEY}
        DBT_SNOWFLAKE_ROLE=ARTWORK_TRANSFORMER
EOF
