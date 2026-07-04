#!/usr/bin/env bash
# 🧹 unload_profile.sh - remove project dbt/Snowflake variables from the current shell.
#
# Usage:
#   source ../snowflake-toolkit/unload_profile.sh
# This file is meant to be sourced from either bash or zsh. Do not set strict
# shell options here; doing so would leak those options into the caller's shell.

_is_sourced() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in
      *:file:*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  if [ -n "${BASH_VERSION:-}" ]; then
    [[ "${BASH_SOURCE[0]}" != "$0" ]]
    return $?
  fi
  return 0
}

if ! _is_sourced; then
  cat >&2 <<'EOF'
❌ unload_profile.sh must be sourced, not executed, or it cannot clean your current shell.

Run:
  source ../snowflake-toolkit/unload_profile.sh
EOF
  exit 64
fi

echo "🧹 Sweeping dbt, Snowflake, and toolkit runtime variables from this shell..."

TARGET_VARS=(
  SNOWFLAKE_ACCOUNT
  SNOWFLAKE_USER
  SNOWFLAKE_PASSWORD
  SNOWFLAKE_PRIVATE_KEY_FILE
  SNOWFLAKE_PRIVATE_KEY_PATH
  SNOWFLAKE_ROLE
  SNOWFLAKE_WAREHOUSE
  SNOWFLAKE_DATABASE
  SNOWFLAKE_SCHEMA
  SNOWFLAKE_AUTHENTICATOR
  SNOWFLAKE_ADMIN_ACCOUNT
  SNOWFLAKE_ADMIN_USER
  SNOWFLAKE_ADMIN_ROLE
  SNOWFLAKE_ADMIN_WAREHOUSE
  DBT_TARGET
  DBT_SNOWFLAKE_USER
  DBT_SNOWFLAKE_PRIVATE_KEY_PATH
  DBT_SNOWFLAKE_PRIVATE_KEY
  DBT_SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
  DBT_SNOWFLAKE_ROLE
  DBT_SNOWFLAKE_SCHEMA_PREFIX
  DBT_SNOWFLAKE_SCHEMA
  DBT_SNOWFLAKE_DATABASE
  DBT_SNOWFLAKE_WAREHOUSE
  DBT_STAGING_WAREHOUSE
  DBT_PROD_WAREHOUSE
  SNOW_CONNECTION
  TOOLKIT_DIR
)

for var in "${TARGET_VARS[@]}"; do
  unset "${var}" 2>/dev/null || true
  echo "✨ Unset: ${var}"
done

echo "🎉 Clean shell state for Snowflake/dbt variables."
