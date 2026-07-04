#!/usr/bin/env bash
# ❄️ load_profile.sh - source project runtime Snowflake/dbt variables safely.
#
# Usage (must be sourced to affect the current shell):
#   source ../snowflake-toolkit/load_profile.sh [--env-file .env] [--mode runtime|dbt|cli|all]
#
# The default mode is "runtime": it loads the project variables needed by the
# extractor and dbt, but intentionally avoids admin-only variables such as
# SNOWFLAKE_ADMIN_ACCOUNT. Do not source project .env files before running the
# Snowflake CLI admin bootstrap; use setup.sh --account/--admin-user instead.
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

usage() {
  cat <<'EOF'
usage: source load_profile.sh [--env-file FILE] [--mode runtime|dbt|cli|all]

Modes:
  runtime  Load application + dbt runtime variables (default).
  dbt      Load only DBT_* and dbt-target Snowflake variables.
  cli      Load Snowflake CLI generic variables. Use only for one-off runtime
           tests, not admin/bootstrap phases.
  all      Load runtime + CLI variables.

Examples:
  source ../snowflake-toolkit/load_profile.sh --env-file .env
  source ../snowflake-toolkit/load_profile.sh --mode dbt
  source ../snowflake-toolkit/load_profile.sh --mode all
EOF
}

ENV_FILE=".env"
MODE="runtime"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file|-f)
      [[ -n "${2:-}" ]] || { echo "❌ --env-file requires a value" >&2; return 64 2>/dev/null || exit 64; }
      ENV_FILE="$2"; shift 2 ;;
    --mode)
      [[ -n "${2:-}" ]] || { echo "❌ --mode requires a value" >&2; return 64 2>/dev/null || exit 64; }
      MODE="$2"; shift 2 ;;
    -h|--help|help) usage; return 0 2>/dev/null || exit 0 ;;
    *)
      # Backward compatibility: first positional argument is the env file.
      if [[ "$1" == -* ]]; then
        echo "❌ Unknown argument: $1" >&2; usage; return 64 2>/dev/null || exit 64
      fi
      ENV_FILE="$1"; shift ;;
  esac
done

case "${MODE}" in
  runtime|dbt|cli|all) ;;
  *) echo "❌ Unknown mode: ${MODE}" >&2; usage; return 64 2>/dev/null || exit 64 ;;
esac

if ! _is_sourced; then
  cat >&2 <<'EOF'
❌ load_profile.sh must be sourced, not executed, or exports will not reach your shell.

Run:
  source ../snowflake-toolkit/load_profile.sh --env-file .env

For bootstrap/admin setup, prefer explicit setup flags instead of sourcing .env:
  ../snowflake-toolkit/snowflake_cli/setup.sh --profile kw94245 \
    --account DSHXYWJ-KW94245 --admin-user PORCHORCH --phase prereq
EOF
  exit 64
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "❌ Env file not found: ${ENV_FILE}" >&2
  return 66
fi

# Keep this parser intentionally small: KEY=VALUE, optional single/double quotes,
# comments and blank lines ignored. It never evals the file.
_read_env_value() {
  local key="$1" line value
  line="$(grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  [[ -n "${line}" ]] || return 1
  value="${line#*=}"
  value="${value%%$'\r'}"
  value="${value%\#*}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value#"${value%%[![:space:]]*}"}"
  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

RUNTIME_VARS=(
  SNOWFLAKE_ACCOUNT
  SNOWFLAKE_USER
  SNOWFLAKE_PRIVATE_KEY_FILE
  SNOWFLAKE_PRIVATE_KEY_PATH
  SNOWFLAKE_ROLE
  SNOWFLAKE_WAREHOUSE
  SNOWFLAKE_DATABASE
  SNOWFLAKE_SCHEMA
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
DBT_VARS=(
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
)
CLI_VARS=(
  SNOWFLAKE_ACCOUNT
  SNOWFLAKE_USER
  SNOWFLAKE_ROLE
  SNOWFLAKE_WAREHOUSE
  SNOWFLAKE_DATABASE
  SNOWFLAKE_SCHEMA
  SNOWFLAKE_PRIVATE_KEY_FILE
  SNOWFLAKE_PRIVATE_KEY_PATH
)

case "${MODE}" in
  runtime) TARGET_VARS=("${RUNTIME_VARS[@]}") ;;
  dbt) TARGET_VARS=("${DBT_VARS[@]}") ;;
  cli) TARGET_VARS=("${CLI_VARS[@]}") ;;
  all) TARGET_VARS=("${RUNTIME_VARS[@]}" "${CLI_VARS[@]}") ;;
esac

echo "🔍 Loading ${MODE} variables from ${ENV_FILE}..."
loaded=0
for var in "${TARGET_VARS[@]}"; do
  if value="$(_read_env_value "${var}")"; then
    export "${var}=${value}"
    echo "✅ Exported: ${var}"
    loaded=$((loaded + 1))
  fi
done

if [[ "${MODE}" == "cli" || "${MODE}" == "all" ]]; then
  cat >&2 <<'EOF'
⚠️  Generic SNOWFLAKE_* variables are now in your shell. They can override Snowflake CLI
   connection profiles. Before profile/bootstrap work, run:
     source ../snowflake-toolkit/unload_profile.sh
   or use setup.sh --account/--admin-user so admin bootstrap ignores project runtime env.
EOF
fi

echo "🚀 Loaded ${loaded} variable(s)."
