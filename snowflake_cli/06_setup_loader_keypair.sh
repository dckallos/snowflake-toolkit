#!/usr/bin/env bash
# ============================================================
# 06_setup_loader_keypair.sh -- Establish KEY-PAIR auth for the
# ARTWORK_LOADER_SVC service user. Replaces the retired password-rotation
# step. Fully automated; invoked by `setup.sh --phase loader`.
#
# Three actions, in order:
#   1. Generate the loader RSA key pair LAZILY (only if missing), mirroring
#      02_generate_admin_keypair.sh:
#         ~/.snowflake/keys/loader_rsa_key.p8   (unencrypted PKCS#8, chmod 600)
#         ~/.snowflake/keys/loader_rsa_key.pub  (PEM public key,   chmod 644)
#   2. Register the public key on the service user by applying
#      git-setup/operator/register_loader_public_key.sql via the ADMIN JWT
#      connection (`snow sql -c admin ...`). This is the key difference from
#      the admin bootstrap: the loader has NO chicken-and-egg problem because a
#      working admin JWT connection already exists, so the loader never needs a
#      password one-shot at all.
#   3. Rewrite [connections.loader] in ~/.snowflake/config.toml to use
#      key-pair auth (authenticator = SNOWFLAKE_JWT, private_key_file = the .p8),
#      using the insert-if-missing helper so the lines are created if absent.
#
# Prerequisites:
#   - `make iac` must have already applied create_service_user.sql so
#     ARTWORK_LOADER_SVC (TYPE = SERVICE) exists.
#   - The admin JWT connection must already work (setup.sh --phase admin).
#
# Optional env:
#   LOADER_USER            defaults to ARTWORK_LOADER_SVC
#   LOADER_PRIVATE_KEY     defaults to ~/.snowflake/keys/loader_rsa_key.p8
#   LOADER_PUBLIC_KEY      defaults to ~/.snowflake/keys/loader_rsa_key.pub
#   OVERWRITE_LOADER_KEY   set to 1 to force-rotate an existing private key
#   SQL_FILE               defaults to
#                          git-setup/operator/register_loader_public_key.sql
#
# Idempotent: re-running with an unchanged key is a no-op (ALTER USER ... SET
# RSA_PUBLIC_KEY with the same value, and a config.toml upsert that writes the
# same values). Re-running with OVERWRITE_LOADER_KEY=1 rotates the credential.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

LOADER_USER="${LOADER_USER:-ARTWORK_LOADER_SVC}"
KEY_DIR="${SNOW_LIB_KEY_DIR}"
PRIVATE_KEY="${LOADER_PRIVATE_KEY:-$(loader_key_path p8)}"
PUBLIC_KEY="${LOADER_PUBLIC_KEY:-$(loader_key_path pub)}"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_loader_public_key.sql}"
CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"

[[ -f "${SQL_FILE}" ]] || { echo "error: SQL file not found: ${SQL_FILE}" >&2; exit 66; }

# --- 1. Generate the loader key pair lazily -------------------------------
mkdir -p "${KEY_DIR}"
if [[ -f "${PRIVATE_KEY}" && "${OVERWRITE_LOADER_KEY:-0}" != "1" ]]; then
    echo "==> loader private key already exists at ${PRIVATE_KEY} (set OVERWRITE_LOADER_KEY=1 to rotate)"
else
    echo "==> generating PKCS#8 loader RSA key pair"
    openssl genrsa 2048 \
        | openssl pkcs8 -topk8 -inform PEM -out "${PRIVATE_KEY}" -nocrypt
    openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"
    chmod 600 "${PRIVATE_KEY}"
    chmod 644 "${PUBLIC_KEY}"
    ls -l "${PRIVATE_KEY}" "${PUBLIC_KEY}"
fi

[[ -f "${PUBLIC_KEY}" ]] || { echo "error: loader public key not found: ${PUBLIC_KEY}" >&2; exit 66; }

# Strip PEM header/footer/newlines so the key body fits in a single
# --variable value (same transform as the admin scripts).
PUBKEY="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${PUBLIC_KEY}")"

# --- 2. Register the public key via the admin JWT connection --------------
echo "==> registering loader public key for user '${LOADER_USER}' via -c ${SNOW_LIB_ADMIN_CONN}"
snow sql -c "${SNOW_LIB_ADMIN_CONN}" \
    --filename "${SQL_FILE}" \
    --variable "loader_user=${LOADER_USER}" \
    --variable "rsa_public_key=${PUBKEY}" \
    --enhanced-exit-codes

# --- 3. Point [connections.<loader>] at key-pair auth ---------------------
# Resolve the account from the admin connection (loader shares the account).
ACCOUNT="$(resolve_admin_account)"

echo "==> updating [connections.${SNOW_LIB_LOADER_CONN}] in ${CONFIG_TOML} for key-pair auth"
upsert_toml_value_in_section "connections.${SNOW_LIB_LOADER_CONN}" 'account'          "${ACCOUNT}"      "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_LOADER_CONN}" 'user'             "${LOADER_USER}"  "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_LOADER_CONN}" 'authenticator'    'SNOWFLAKE_JWT'   "${CONFIG_TOML}"
upsert_toml_value_in_section "connections.${SNOW_LIB_LOADER_CONN}" 'private_key_file' "${PRIVATE_KEY}"  "${CONFIG_TOML}"

cat <<EOF

==> loader key-pair auth established.
    User:            ${LOADER_USER} (TYPE = SERVICE, key-pair only)
    Private key:     ${PRIVATE_KEY}
    config.toml:     [connections.${SNOW_LIB_LOADER_CONN}] now uses authenticator = SNOWFLAKE_JWT

    Any stale 'password' line left in [connections.${SNOW_LIB_LOADER_CONN}] is ignored
    under SNOWFLAKE_JWT, but you may delete it for cleanliness.

    For the Python extractor, set in .env (no password at rest):
        SNOWFLAKE_PRIVATE_KEY_FILE=${PRIVATE_KEY}
EOF
