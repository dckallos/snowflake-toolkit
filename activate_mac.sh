#!/usr/bin/env bash
# ============================================================
# activate_mac.sh -- 🖥️  Activate this Mac as the primary control plane
#
# Registers all RSA keys (admin + service users) and applies IaC from
# this machine. After running, this Mac owns all key slots and can
# execute the full project workflow (make iac, service-user scripts, etc.).
#
# Usage:
#   ./activate_mac.sh [--profile PROFILE] [--project-dir DIR] [--iac-target TARGET]
#
# Default profile: mk07348
# Default project dir: current working directory
# Default IaC target: infra
#
# ⚠️  WARNING: Running this on Mac B invalidates Mac A's keys.
#    Only ONE Mac can be active at a time (Snowflake slot-1 limitation).
#    A future dual-slot solution will remove this constraint.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="${SCRIPT_DIR}"

usage() {
    local code="${1:-64}"
    cat <<'EOF'
usage: activate_mac.sh [--profile PROFILE] [--project-dir DIR] [--iac-target TARGET]

  --profile PROFILE     Snowflake connection profile to activate.
                        Default: mk07348
  --project-dir DIR     Project directory containing the Makefile that applies
                        IaC. Default: current working directory.
  --iac-target TARGET   Make target to run after admin bootstrap.
                        Default: infra

Examples:
  ./activate_mac.sh --profile mk07348
  ./activate_mac.sh --profile clientb --project-dir /path/to/project
  ./activate_mac.sh --profile clientb --iac-target iac
EOF
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

# --- Parse args ---------------------------------------------------------------
PROFILE="mk07348"
PROJECT_DIR="${PROJECT_DIR:-${PWD}}"
IAC_TARGET="${IAC_TARGET:-infra}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ -n "${2:-}" ]] || { echo "❌ --profile requires a value" >&2; exit 64; }
            PROFILE="$2"
            shift 2
            ;;
        --project-dir)
            [[ -n "${2:-}" ]] || { echo "❌ --project-dir requires a value" >&2; exit 64; }
            PROJECT_DIR="$2"
            shift 2
            ;;
        --iac-target)
            [[ -n "${2:-}" ]] || { echo "❌ --iac-target requires a value" >&2; exit 64; }
            IAC_TARGET="$2"
            shift 2
            ;;
        -h|--help|help) usage 0 ;;
        *) echo "❌ Unknown argument: $1" >&2; usage 64 ;;
    esac
done

SETUP_SH="$(find_setup_script)" || {
    echo "❌ Could not find snowflake_cli/setup.sh from ${TOOLKIT_DIR}" >&2
    exit 66
}

PROJECT_DIR="$(cd "${PROJECT_DIR}" 2>/dev/null && pwd)" || {
    echo "❌ Project directory not found: ${PROJECT_DIR}" >&2
    exit 66
}

if ! has_makefile "${PROJECT_DIR}"; then
    cat >&2 <<EOF
❌ No Makefile found in project dir: ${PROJECT_DIR}

activate_mac.sh now runs Snowflake CLI setup from the toolkit directory, but
applies IaC from --project-dir (default: the directory you ran it from).

Run this from your project root, or pass:
  --project-dir /path/to/project
EOF
    exit 66
fi

echo ""
echo "🖥️  Activating this Mac as primary control plane"
echo "   Profile: ${PROFILE}"
echo "   Toolkit: ${TOOLKIT_DIR}"
echo "   Project: ${PROJECT_DIR}"
echo "   IaC: make ${IAC_TARGET} CONN=${PROFILE}"
echo ""
echo "⚠️  This will register THIS Mac's keys in Snowflake."
echo "   Any other Mac's keys will be invalidated (slot-1 overwrite)."
echo ""
read -rp "🔑 Proceed? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "❌ Aborted."
    exit 0
fi

echo ""

# --- Step 1: Admin key registration (password auth bootstrap) -----------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Step 1/5: Preparing local config + registering admin key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
bash "${SETUP_SH}" --profile "${PROFILE}" --phase prereq
bash "${SETUP_SH}" --profile "${PROFILE}" --phase admin
echo ""
echo "✅ Admin key registered"
echo ""

# --- Step 2: Apply IaC (creates service users + all DDL) ----------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Step 2/5: Applying infrastructure (make ${IAC_TARGET})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
make -C "${PROJECT_DIR}" "${IAC_TARGET}" CONN="${PROFILE}"
echo ""
echo "✅ Infrastructure applied"
echo ""

# --- Step 3: Promote admin warehouse -----------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⬆️  Step 3/5: Promoting admin connection to ARTWORK_WH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
bash "${SETUP_SH}" --profile "${PROFILE}" --phase promote
echo ""
echo "✅ Admin connection promoted"
echo ""

# --- Step 4: Loader key registration -----------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 4/5: Registering loader service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
bash "${SETUP_SH}" --profile "${PROFILE}" --phase loader
echo ""
echo "✅ Loader key registered"
echo ""

# --- Step 5: Transformer key registration -------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Step 5/5: Registering transformer service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
bash "${SETUP_SH}" --profile "${PROFILE}" --phase transformer
echo ""
echo "✅ Transformer key registered"
echo ""

# --- Verification -------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Verifying all connections..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

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

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 This Mac is now the active control plane."
    echo "   All connections verified. You can run project workflows."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Some connections failed. Check the output above for details."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
