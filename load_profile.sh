#!/bin/bash
# ❄️ load_profile.sh - Loads exact dbt/Snowflake vars from a specified env file 🎨

# 0️⃣ Use the first argument as the env file, or default to ".env"
ENV_FILE="${1:-.env}"

# 1️⃣ Check if the file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Oops! No '$ENV_FILE' file found. 🕵️‍♂️"
  return 1 2>/dev/null || exit 1
fi

echo "🔍 Extracting specific dbt & Snowflake configurations from $ENV_FILE..."

# 2️⃣ Define the hard-coded list of variables you want to extract
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

# 3️⃣ Loop through the target variables and pull them from the target file
for var in "${TARGET_VARS[@]}"; do
  
  # Search for the exact variable at the start of a line
  match=$(grep "^${var}=" "$ENV_FILE" | head -n 1)
  
  if [ -n "$match" ]; then
    # Grab the value (everything after the first '=')
    value=$(echo "$match" | cut -d '=' -f 2-)
    
    # Strip any surrounding single or double quotes from the value
    value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    
    # Export it to the active shell session!
    export "$var"="$value"
    echo "✅ Exported: $var"
  else
    # Let you know if a variable from your list is missing from the file
    echo "⚠️  Warning: $var was not found in $ENV_FILE! 🤷‍♂️"
  fi

done

echo "🚀 All set! Your specific variables are locked and loaded. 🎸"
