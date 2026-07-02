#!/bin/bash
# 📋 status_profile.sh - Checks the current status of dbt/Snowflake vars 👀

echo "📋 Checking your active dbt & Snowflake environment variables..."
echo "--------------------------------------------------------------"

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

# Loop through and check the status of each variable
for var in "${TARGET_VARS[@]}"; do
  
  # Use Bash indirect expansion (${!var}) to get the variable's value
  value="${!var}"
  
  if [ -n "$value" ]; then
    echo "🟢 $var = $value"
  else
    echo "⚪ $var is NOT SET (or empty) 👻"
  fi

done

echo "--------------------------------------------------------------"
echo "🥳 Status check complete! Happy coding! 💻✨"
