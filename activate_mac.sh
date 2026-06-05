#!/usr/bin/env bash
# ============================================================
# activate_mac.sh -- 🖥️  Activate this Mac as the primary control plane
#
# Registers all RSA keys (admin + service users) and applies IaC from
# this machine. After running, this Mac owns all key slots and can
# execute the full pipeline (make infra, extraction, dbt).
#
# Usage:
#   ./scripts/activate_mac.sh [--profile PROFILE]
#
# Default profile: mk07348
#
# ⚠️  WARNING: Running this on Mac B invalidates Mac A's keys.
#    Only ONE Mac can be active at a time (Snowflake slot-1 limitation).
#    A future dual-slot solution will remove this constraint.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Parse args ---------------------------------------------------------------
PROFILE="mk07348"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        *) echo "❌ Unknown argument: $1" >&2; exit 1 ;;
    esac
done

echo ""
echo "🖥️  Activating this Mac as primary control plane"
echo "   Profile: ${PROFILE}"
echo "   Account: OBANOYY-MK07348"
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
echo "🔐 Step 1/4: Registering admin key (requires Snowflake password)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
"${REPO_ROOT}/scripts/snowflake_cli/setup.sh" --profile "${PROFILE}" --phase admin
echo ""
echo "✅ Admin key registered"
echo ""

# --- Step 2: Apply IaC (creates service users + all DDL) ----------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Step 2/4: Applying infrastructure (make infra)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
make -C "${REPO_ROOT}" infra CONN="${PROFILE}"
echo ""
echo "✅ Infrastructure applied"
echo ""

# --- Step 3: Loader key registration -----------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 3/4: Registering loader service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
"${REPO_ROOT}/scripts/snowflake_cli/setup.sh" --profile "${PROFILE}" --phase loader
echo ""
echo "✅ Loader key registered"
echo ""

# --- Step 4: Transformer key registration -------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Step 4/4: Registering transformer service user key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
"${REPO_ROOT}/scripts/snowflake_cli/setup.sh" --profile "${PROFILE}" --phase transformer
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
           -u SNOWFLAKE_PRIVATE_KEY_FILE -u SNOWFLAKE_AUTHENTICATOR \
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
    echo "   All connections verified. You can run make infra, dbt, extraction, etc."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Some connections failed. Check the output above for details."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
