#!/usr/bin/env bash
# ============================================================
# activate_mac.sh -- activate this Mac as the Snowflake control plane.
#
# End-to-end flow:
#   prereq -> admin key registration -> project IaC -> promote -> loader -> transformer.
#
# Safe profile creation is explicit: pass --account and --admin-user for a new
# account. Generic project .env variables are stripped from every setup phase so
# old SNOWFLAKE_ACCOUNT / SNOWFLAKE_ROLE values cannot poison admin bootstrap.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="${SCRIPT_DIR}"

usage() {
    local code="${1:-64}"
    cat <<'USAGE'
usage: activate_mac.sh --profile PROFILE [--account ACCOUNT --admin-user USER] [options]

Required for a brand-new account/profile:
  --profile PROFILE       Local connection prefix, e.g. kw94245
  --account ACCOUNT       Snowflake account identifier, e.g. DSHXYWJ-KW94245
  --admin-user USER       Snowflake login name, e.g. PORCHORCH

Options:
  --project-dir DIR       Project directory containing the Makefile. Default: current dir
  --iac-target TARGET     Make target to run after admin bootstrap. Default: infra
  --admin-role ROLE       Admin role for registration. Default: ACCOUNTADMIN
  --init-warehouse WH     Existing day-one warehouse. Default: COMPUTE_WH
  --target-warehouse WH   Post-IaC admin warehouse. Default: ARTWORK_WH
  --replace-existing      Rewrite an existing local [PROFILE] block after backup
  --yes                   Skip confirmation prompt

Examples:
  ../snowflake-toolkit/activate_mac.sh --profile kw94245 \
    --account DSHXYWJ-KW94245 --admin-user PORCHORCH --project-dir .

  ../snowflake-toolkit/activate_mac.sh --profile kw94245 \
    --account DSHXYWJ-KW94245 --admin-user PORCHORCH --replace-existing --project-dir .
USAGE
    exit "${code}"
}

find_setup_script() {
    local candidate candidate_dir
    for candidate in \
        "${TOOLKIT_DIR}/snowflake_cli/setup.sh" \
        "${TOOLKIT_DIR}/scripts/snowflake_cli/setup.sh" \
        "${TOOLKIT_DIR}/../snowflake_cli/setup.sh"
    do
        if [[ -f "${candidate}" ]]; then
            candidate_dir="$(cd "$(dirname "${candidate}")" && pwd)"
            printf '%s\n' "${candidate_dir}/$(basename "${candidate}")"
            return 0
        fi
    done
    return 1
}

has_makefile() {
    local dir="$1"
    [[ -f "${dir}/GNUmakefile" || -f "${dir}/makefile" || -f "${dir}/Makefile" ]]
}

run_setup_clean() {
    env -u SNOWFLAKE_ACCOUNT \
        -u SNOWFLAKE_USER \
        -u SNOWFLAKE_ROLE \
        -u SNOWFLAKE_WAREHOUSE \
        -u SNOWFLAKE_DATABASE \
        -u SNOWFLAKE_SCHEMA \
        -u SNOWFLAKE_PRIVATE_KEY_FILE \
        -u SNOWFLAKE_PRIVATE_KEY_PATH \
        -u SNOWFLAKE_AUTHENTICATOR \
        bash "${SETUP_SH}" "${SETUP_ARGS[@]}" "$@"
}

PROFILE=""
ACCOUNT=""
ADMIN_USER=""
ADMIN_ROLE="ACCOUNTADMIN"
INIT_WAREHOUSE="COMPUTE_WH"
TARGET_WAREHOUSE="ARTWORK_WH"
PROJECT_DIR="${PROJECT_DIR:-${PWD}}"
IAC_TARGET="${IAC_TARGET:-infra}"
REPLACE_EXISTING=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --account) ACCOUNT="${2:-}"; shift 2 ;;
        --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
        --admin-role) ADMIN_ROLE="${2:-}"; shift 2 ;;
        --init-warehouse|--admin-warehouse) INIT_WAREHOUSE="${2:-}"; shift 2 ;;
        --target-warehouse) TARGET_WAREHOUSE="${2:-}"; shift 2 ;;
        --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
        --iac-target) IAC_TARGET="${2:-}"; shift 2 ;;
        --replace-existing) REPLACE_EXISTING=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        -h|--help|help) usage 0 ;;
        *) echo "❌ Unknown argument: $1" >&2; usage 64 ;;
    esac
done

[[ -n "${PROFILE}" ]] || { echo "❌ --profile is required" >&2; usage 64; }
[[ "${PROFILE}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "❌ Invalid profile: ${PROFILE}" >&2; exit 64; }

SETUP_SH="$(find_setup_script)" || {
    echo "❌ Could not find snowflake_cli/setup.sh from ${TOOLKIT_DIR}" >&2
    exit 66
}

PROJECT_DIR="$(cd "${PROJECT_DIR}" 2>/dev/null && pwd)" || {
    echo "❌ Project directory not found: ${PROJECT_DIR}" >&2
    exit 66
}

if ! has_makefile "${PROJECT_DIR}"; then
    cat >&2 <<MSG
❌ No Makefile found in project dir: ${PROJECT_DIR}

Run this from your artwork-db root, or pass:
  --project-dir /path/to/artwork-db
MSG
    exit 66
fi

SETUP_ARGS=(--profile "${PROFILE}" --admin-role "${ADMIN_ROLE}" --init-warehouse "${INIT_WAREHOUSE}" --target-warehouse "${TARGET_WAREHOUSE}")
if [[ -n "${ACCOUNT}" ]]; then
    SETUP_ARGS+=(--account "${ACCOUNT}")
fi
if [[ -n "${ADMIN_USER}" ]]; then
    SETUP_ARGS+=(--admin-user "${ADMIN_USER}")
fi
if [[ "${REPLACE_EXISTING}" -eq 1 ]]; then
    SETUP_ARGS+=(--replace-existing)
fi

cat <<STATUS

🖥️  Activating this Mac as primary control plane
   Profile:          ${PROFILE}
   Account:          ${ACCOUNT:-<from existing profile or prompt>}
   Admin user:       ${ADMIN_USER:-<from existing profile or prompt>}
   Toolkit:          ${TOOLKIT_DIR}
   Project:          ${PROJECT_DIR}
   IaC:              make ${IAC_TARGET} CONN=${PROFILE}
   Init warehouse:   ${INIT_WAREHOUSE}
   Target warehouse: ${TARGET_WAREHOUSE}

⚠️  This registers this Mac's admin, loader, and transformer public keys in Snowflake.
   Do not run it against the wrong account. Existing local profiles are not rewritten
   unless --replace-existing is supplied.
STATUS

if [[ "${ASSUME_YES}" -ne 1 ]]; then
    read -rp "🔑 Proceed? [y/N] " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "❌ Aborted."
        exit 0
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Step 1/5: Preparing local config + registering admin key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_setup_clean --phase prereq
run_setup_clean --phase admin

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Step 2/5: Applying infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
make -C "${PROJECT_DIR}" "${IAC_TARGET}" CONN="${PROFILE}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⬆️  Step 3/5: Promoting admin connection to ${TARGET_WAREHOUSE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_setup_clean --phase promote

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 4/5: Registering loader service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_setup_clean --phase loader

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Step 5/5: Registering transformer service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_setup_clean --phase transformer

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Verifying all connections..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
FAILED=0
for conn in "${PROFILE}" "${PROFILE}_loader" "${PROFILE}_transformer"; do
    if env -u SNOWFLAKE_ROLE -u SNOWFLAKE_USER -u SNOWFLAKE_ACCOUNT \
           -u SNOWFLAKE_WAREHOUSE -u SNOWFLAKE_DATABASE \
           -u SNOWFLAKE_SCHEMA -u SNOWFLAKE_PRIVATE_KEY_FILE \
           -u SNOWFLAKE_PRIVATE_KEY_PATH -u SNOWFLAKE_AUTHENTICATOR \
       snow connection test -c "${conn}" >/dev/null 2>&1; then
        echo "  ✅ ${conn}"
    else
        echo "  ❌ ${conn} -- FAILED"
        FAILED=1
    fi
done

if [[ "${FAILED}" -ne 0 ]]; then
    echo "⚠️  Some connections failed. Check the output above."
    exit 1
fi

cat <<DONE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 This Mac is now the active control plane for ${PROFILE}.
   Next: write/update artwork-db .env using the template in the review output.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DONE
