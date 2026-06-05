#!/usr/bin/env bash
# ============================================================
# 10_test_transformer_connection.sh -- Verify the 'transformer' connection.
#
# By this point 09_setup_transformer_keypair.sh has switched
# [connections.<transformer>] to key-pair auth (authenticator = SNOWFLAKE_JWT,
# private_key_file = the transformer .p8), so NO password and NO .env are
# required for the CLI test -- the private key in config.toml is the sole
# credential.
#
# Runs `snow connection test` and a CURRENT_USER / CURRENT_ROLE round-trip to
# prove JWT auth works end-to-end for the dbt service user.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

echo "==> snow connection test -c ${SNOW_LIB_TRANSFORMER_CONN} (SNOWFLAKE_JWT)"
# Scrub SNOWFLAKE_* env vars that override config.toml connection settings.
# Without this, SNOWFLAKE_ROLE from .env (ARTWORK_LOADER) leaks into the
# transformer connection test and causes a "role not granted" error.
env -u SNOWFLAKE_ROLE \
    -u SNOWFLAKE_USER \
    -u SNOWFLAKE_ACCOUNT \
    -u SNOWFLAKE_WAREHOUSE \
    -u SNOWFLAKE_DATABASE \
    -u SNOWFLAKE_PRIVATE_KEY_FILE \
    -u SNOWFLAKE_AUTHENTICATOR \
snow connection test -c "${SNOW_LIB_TRANSFORMER_CONN}"

echo
echo "==> CURRENT_USER / CURRENT_ROLE round-trip"
env -u SNOWFLAKE_ROLE \
    -u SNOWFLAKE_USER \
    -u SNOWFLAKE_ACCOUNT \
    -u SNOWFLAKE_WAREHOUSE \
    -u SNOWFLAKE_DATABASE \
    -u SNOWFLAKE_PRIVATE_KEY_FILE \
    -u SNOWFLAKE_AUTHENTICATOR \
snow sql -c "${SNOW_LIB_TRANSFORMER_CONN}" -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"

echo
echo "==> transformer connection verified (key-pair / SNOWFLAKE_JWT)"
