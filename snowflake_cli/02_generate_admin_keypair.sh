#!/usr/bin/env bash
# ============================================================
# 02_generate_admin_keypair.sh -- Generate the admin RSA key pair used by
# the snow CLI 'admin' connection (authenticator = SNOWFLAKE_JWT).
#
# Produces (paths derive from the active admin connection name; default 'admin'
# yields the historical admin_rsa_key.* paths):
#   ~/.snowflake/keys/${ADMIN_CONN}_rsa_key.p8   (unencrypted PKCS#8, chmod 600)
#   ~/.snowflake/keys/${ADMIN_CONN}_rsa_key.pub  (PEM public key,   chmod 644)
#
# Idempotent: refuses to overwrite an existing private key unless
# OVERWRITE_ADMIN_KEY=1 is set in the environment (force rotation).
#
# Note: SNOWFLAKE_JWT expects an UNENCRYPTED PKCS#8 key. If you generate an
# encrypted key by dropping -nocrypt, you must also set 'private_key_file_pwd'
# in [connections.<admin>] (ideally sourced from the macOS keychain).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

KEY_DIR="${SNOW_LIB_KEY_DIR}"
PRIVATE_KEY="$(admin_key_path p8)"
PUBLIC_KEY="$(admin_key_path pub)"

mkdir -p "${KEY_DIR}"

if [[ -f "${PRIVATE_KEY}" && "${OVERWRITE_ADMIN_KEY:-0}" != "1" ]]; then
    echo "private key already exists at ${PRIVATE_KEY}"
    echo "set OVERWRITE_ADMIN_KEY=1 to force rotation"
    exit 0
fi

echo "==> generating PKCS#8 admin RSA key pair"
openssl genrsa 2048 \
    | openssl pkcs8 -topk8 -inform PEM -out "${PRIVATE_KEY}" -nocrypt
openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"

chmod 600 "${PRIVATE_KEY}"
chmod 644 "${PUBLIC_KEY}"

ls -l "${PRIVATE_KEY}" "${PUBLIC_KEY}"
