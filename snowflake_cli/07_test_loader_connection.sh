#!/usr/bin/env bash
# ============================================================
# 07_test_loader_connection.sh -- Verify the 'loader' connection.
#
# By this point 06_setup_loader_keypair.sh has switched [connections.loader]
# to key-pair auth (authenticator = SNOWFLAKE_JWT, private_key_file = the
# loader .p8), so NO password and NO .env are required for the CLI test --
# the private key in config.toml is the sole credential.
#
# Runs `snow connection test -c loader` and a CURRENT_USER / CURRENT_ROLE
# round-trip to prove JWT auth works end-to-end for the service user.
# ============================================================
set -euo pipefail

echo "==> snow connection test -c loader (SNOWFLAKE_JWT)"
snow connection test -c loader

echo
echo "==> CURRENT_USER / CURRENT_ROLE round-trip"
snow sql -c loader -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"

echo
echo "==> loader connection verified (key-pair / SNOWFLAKE_JWT)"
