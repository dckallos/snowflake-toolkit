#!/usr/bin/env bash
# ============================================================
# 01_init_snowflake_home.sh -- Create ~/.snowflake/{keys,logs} with the
# tight permissions the Snowflake CLI expects.
#
# Idempotent: mkdir -p creates only what is missing; chmod is naturally
# idempotent.
# ============================================================
set -euo pipefail

SNOWFLAKE_HOME_DIR="${HOME}/.snowflake"

echo "==> mkdir -p ${SNOWFLAKE_HOME_DIR}/{keys,logs}"
mkdir -p "${SNOWFLAKE_HOME_DIR}/keys" "${SNOWFLAKE_HOME_DIR}/logs"

# Tighten the parent so derivatives (config.toml, keys) inherit a narrow
# effective access surface even if their own modes drift.
chmod 700 "${SNOWFLAKE_HOME_DIR}"
chmod 700 "${SNOWFLAKE_HOME_DIR}/keys"

ls -ld \
    "${SNOWFLAKE_HOME_DIR}" \
    "${SNOWFLAKE_HOME_DIR}/keys" \
    "${SNOWFLAKE_HOME_DIR}/logs"
