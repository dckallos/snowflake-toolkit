#!/usr/bin/env bash
# ============================================================
# 07_test_loader_connection.sh -- Verify the 'loader' connection.
#
# Loads .env into the current process (env-var precedence is how the snow
# CLI picks up SNOWFLAKE_PASSWORD for the loader connection), then runs
# `snow connection test -c loader` and a CURRENT_USER / CURRENT_ROLE
# round-trip.
#
# Optional env:
#   ENV_FILE   defaults to <repo>/.env
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"

if [[ -f "${ENV_FILE}" ]]; then
    echo "==> loading ${ENV_FILE}"
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
else
    echo "WARN: ${ENV_FILE} not found; relying on already-exported env vars"
fi

: "${SNOWFLAKE_PASSWORD:?SNOWFLAKE_PASSWORD must be set (rotate via 06 first, then copy into .env)}"

echo
echo "==> snow connection test -c loader"
snow connection test -c loader

echo
echo "==> CURRENT_USER / CURRENT_ROLE round-trip"
snow sql -c loader -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"

echo
echo "==> loader connection verified"
