#!/bin/bash
# 🧹 unload_profile.sh - Cleans up dbt/Snowflake vars from your shell 🌟

echo "🧹 Sweeping away dbt & Snowflake configurations..."

TARGET_VARS=(
  "SNOWFLAKE_ACCOUNT"
  "SNOWFLAKE_USER"
  "SNOWFLAKE_PRIVATE_KEY_FILE"
  "SNOWFLAKE_ROLE"
  "SNOWFLAKE_WAREHOUSE"
  "SNOWFLAKE_DATABASE"
  "DBT_SNOWFLAKE_USER"
  "DBT_SNOWFLAKE_PRIVATE_KEY_PATH"
  "DBT_SNOWFLAKE_ROLE"
)

# Loop through and unset each variable
for var in "${TARGET_VARS[@]}"; do
  unset "$var"
  echo "✨ Unset: $var"
done

echo "🎉 All clean! Your environment is totally refreshed and ready to go. 🎈"
