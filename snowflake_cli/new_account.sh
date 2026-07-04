#!/usr/bin/env bash
# ============================================================
# snowflake_cli/new_account.sh -- guided, profile-safe Snowflake account onboarding.
#
# This wrapper prevents project .env pollution from influencing admin bootstrap.
# It passes explicit admin values to setup.sh using SNOWFLAKE_ADMIN_* variables
# and unsets generic SNOWFLAKE_* runtime variables in the child process.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'USAGE'
usage: new_account.sh --profile PROFILE --account ORG-ACCOUNT --admin-user USER [options]

Required:
  --profile PROFILE       Local connection prefix, e.g. kw94245
  --account ACCOUNT       Snowflake account identifier, e.g. DSHXYWJ-KW94245
  --admin-user USER       Snowflake login name, e.g. PORCHORCH

Options:
  --admin-role ROLE       Admin role for registration. Default: ACCOUNTADMIN
  --init-warehouse WH     Existing day-one warehouse. Default: COMPUTE_WH
  --target-warehouse WH   Post-IaC warehouse for promote. Default: ARTWORK_WH
  --replace-existing      Rewrite an existing local [PROFILE] block after backup.
  --no-admin              Only seed prereqs/profile; do not register the admin key.

Examples:
  ./snowflake_cli/new_account.sh --profile kw94245 \
    --account DSHXYWJ-KW94245 --admin-user PORCHORCH

  ./snowflake_cli/new_account.sh --profile kw94245 \
    --account DSHXYWJ-KW94245 --admin-user PORCHORCH --replace-existing
USAGE
}

PROFILE=""
ACCOUNT=""
ADMIN_USER=""
ADMIN_ROLE="ACCOUNTADMIN"
INIT_WAREHOUSE="COMPUTE_WH"
TARGET_WAREHOUSE="ARTWORK_WH"
REPLACE_EXISTING=0
RUN_ADMIN=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --account) ACCOUNT="${2:-}"; shift 2 ;;
        --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
        --admin-role) ADMIN_ROLE="${2:-}"; shift 2 ;;
        --init-warehouse|--admin-warehouse) INIT_WAREHOUSE="${2:-}"; shift 2 ;;
        --target-warehouse) TARGET_WAREHOUSE="${2:-}"; shift 2 ;;
        --replace-existing) REPLACE_EXISTING=1; shift ;;
        --no-admin) RUN_ADMIN=0; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 64 ;;
    esac
done

[[ -n "${PROFILE}" ]] || { echo "error: --profile is required" >&2; usage >&2; exit 64; }
[[ -n "${ACCOUNT}" ]] || { echo "error: --account is required" >&2; usage >&2; exit 64; }
[[ -n "${ADMIN_USER}" ]] || { echo "error: --admin-user is required" >&2; usage >&2; exit 64; }
[[ "${PROFILE}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "error: invalid profile '${PROFILE}'" >&2; exit 64; }

SETUP_ARGS=(
    --profile "${PROFILE}"
    --account "${ACCOUNT}"
    --admin-user "${ADMIN_USER}"
    --admin-role "${ADMIN_ROLE}"
    --init-warehouse "${INIT_WAREHOUSE}"
    --target-warehouse "${TARGET_WAREHOUSE}"
)
if [[ "${REPLACE_EXISTING}" -eq 1 ]]; then
    SETUP_ARGS+=(--replace-existing)
fi

cat <<STATUS
==> Onboarding Snowflake account
    profile:          ${PROFILE}
    account:          ${ACCOUNT}
    admin user:       ${ADMIN_USER}
    admin role:       ${ADMIN_ROLE}
    init warehouse:   ${INIT_WAREHOUSE}
    target warehouse: ${TARGET_WAREHOUSE}
STATUS

echo "==> Clearing generic runtime Snowflake variables in this child process"

env -u SNOWFLAKE_ACCOUNT \
    -u SNOWFLAKE_USER \
    -u SNOWFLAKE_ROLE \
    -u SNOWFLAKE_WAREHOUSE \
    -u SNOWFLAKE_DATABASE \
    -u SNOWFLAKE_SCHEMA \
    -u SNOWFLAKE_PRIVATE_KEY_FILE \
    -u SNOWFLAKE_PRIVATE_KEY_PATH \
    -u SNOWFLAKE_AUTHENTICATOR \
    bash "${SCRIPT_DIR}/setup.sh" "${SETUP_ARGS[@]}" --phase prereq

if [[ "${RUN_ADMIN}" -eq 1 ]]; then
    env -u SNOWFLAKE_ACCOUNT \
        -u SNOWFLAKE_USER \
        -u SNOWFLAKE_ROLE \
        -u SNOWFLAKE_WAREHOUSE \
        -u SNOWFLAKE_DATABASE \
        -u SNOWFLAKE_SCHEMA \
        -u SNOWFLAKE_PRIVATE_KEY_FILE \
        -u SNOWFLAKE_PRIVATE_KEY_PATH \
        -u SNOWFLAKE_AUTHENTICATOR \
        bash "${SCRIPT_DIR}/setup.sh" "${SETUP_ARGS[@]}" --phase admin
fi

cat <<NEXT

===================================================================
ACCOUNT PROFILE READY: ${PROFILE}
===================================================================

Admin profile:
  [${PROFILE}] account=${ACCOUNT} user=${ADMIN_USER} role=${ADMIN_ROLE} warehouse=${INIT_WAREHOUSE}

Next commands from your artwork-db project root:
  make infra CONN=${PROFILE}
  ${SCRIPT_DIR}/setup.sh --profile ${PROFILE} --target-warehouse ${TARGET_WAREHOUSE} --phase promote
  ${SCRIPT_DIR}/setup.sh --profile ${PROFILE} --phase loader
  ${SCRIPT_DIR}/setup.sh --profile ${PROFILE} --phase transformer
  ${SCRIPT_DIR}/setup.sh --profile ${PROFILE} --phase switch

Or run the end-to-end activator from artwork-db:
  ${SCRIPT_DIR%/snowflake_cli}/activate_mac.sh --profile ${PROFILE} \
    --account ${ACCOUNT} --admin-user ${ADMIN_USER} --project-dir .
===================================================================
NEXT
