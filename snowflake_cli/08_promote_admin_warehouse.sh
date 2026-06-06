#!/usr/bin/env bash
# ============================================================
# 08_promote_admin_warehouse.sh -- Promote the admin connection from the
# initial account-default warehouse to ARTWORK_WH.
#
# Solves the chicken-and-egg between [<admin>].warehouse and the
# IaC layer: ARTWORK_WH does not exist until `make iac` applies V002, but
# the snow CLI's 'admin' connection needs *some* existing warehouse for
# 'snow connection test -c admin' and SELECT CURRENT_USER() round-trips to
# succeed during initial setup. The project pins
# [<admin>].warehouse to an account-default warehouse on day one
# (typically COMPUTE_WH on fresh Snowflake trial accounts), runs the full
# JWT verification against it via '--phase admin' / '--phase all', then
# runs 'make iac' to create ARTWORK_WH and finally invokes THIS script via
# '--phase promote' to:
#
#   1. Verify ARTWORK_WH actually exists in Snowflake (SHOW WAREHOUSES).
#   2. Back up ~/.snowflake/connections.toml to a timestamped .bak.
#   3. Rewrite ONLY the warehouse line under [<admin>] using
#      _lib.sh's awk-based replace_toml_value_in_section helper. Other
#      sections ([<loader>], [<transformer>]) are left
#      untouched.
#   4. chmod 600 ~/.snowflake/connections.toml so the snow CLI continues to
#      accept it (handled by replace_toml_value_in_section).
#   5. Reuse _lib.sh's parse_toml_value helper to confirm the new value
#      parses back as ARTWORK_WH; abort otherwise.
#   6. Re-run the full three-step JWT verification via _lib.sh's
#      verify_admin_jwt_full helper -- the SAME verification path used by
#      05_verify_admin_jwt.sh, against the now-promoted warehouse.
#
# Idempotent: re-running after promotion is a safe no-op. The SHOW
# WAREHOUSES check succeeds, replace_toml_value_in_section rewrites the
# already-correct value (creating a fresh timestamped backup each time),
# and verify_admin_jwt_full succeeds again against the same warehouse.
#
# Creates NO Snowflake objects. ARTWORK_WH must already exist (created
# by infrastructure/V002__create_warehouses.sql via 'make iac'); this
# script only verifies it, rewrites connections.toml in code, and re-verifies
# JWT auth end-to-end.
#
# Zero-export resolution order (handled by _lib.sh helpers):
#   SNOWFLAKE_ADMIN_USER  env var -> [<admin>].user in connections.toml
#
# No password required -- JWT auth via the existing admin RSA key pair.
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
#   CONNECTIONS_TOML      defaults to ~/.snowflake/connections.toml
#   TARGET_WAREHOUSE      defaults to ARTWORK_WH
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

CONNECTIONS_TOML="${CONNECTIONS_TOML:-${SNOW_LIB_CONNECTIONS_TOML}}"

# Check connections.toml exists BEFORE resolving values from it, so a missing
# file yields the actionable init-profile hint rather than a bare resolve error.
[[ -f "${CONNECTIONS_TOML}" ]] || {
    echo "error: connections.toml not found: ${CONNECTIONS_TOML}" >&2
    echo "       seed it first with:" >&2
    echo "           ./scripts/snowflake_cli/setup.sh --phase init-profile" >&2
    echo "       (or run --phase prereq / --phase all, which include it), then re-run." >&2
    exit 66
}

ADMIN_USER="$(resolve_admin_user)"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"
TARGET_WAREHOUSE="${TARGET_WAREHOUSE:-ARTWORK_WH}"

# ------------------------------------------------------------
# Step 1/4: verify ARTWORK_WH exists in Snowflake (account-side check).
#
# SHOW WAREHOUSES LIKE '<name>' returns zero rows if the warehouse is
# absent. Capture the output and grep for the target name so absence is
# a hard failure with a clear remediation message rather than a silent
# success.
# ------------------------------------------------------------
echo "==> Step 1/4: verify ${TARGET_WAREHOUSE} exists in Snowflake"
SHOW_OUTPUT="$(snow sql -c "${SNOW_LIB_ADMIN_CONN}" \
    -q "SHOW WAREHOUSES LIKE '${TARGET_WAREHOUSE}';" \
    --format=plain \
    --enhanced-exit-codes)"

if ! grep -qi "${TARGET_WAREHOUSE}" <<<"${SHOW_OUTPUT}"; then
    cat <<EOF >&2
error: warehouse '${TARGET_WAREHOUSE}' does not exist in Snowflake yet.

       Run 'make iac' first (it applies
       infrastructure/V002__create_warehouses.sql under the already-verified
       admin JWT connection). Then re-run:

           ./scripts/snowflake_cli/setup.sh --phase promote
EOF
    exit 70
fi
echo "    OK: ${TARGET_WAREHOUSE} exists"

# ------------------------------------------------------------
# Step 2/4: rewrite [<admin>].warehouse in connections.toml via the
# _lib.sh helper, which handles the timestamped backup, the in-section
# awk rewrite, the atomic mv, and chmod 600. Other sections
# ([<loader>], [<transformer>]) are left strictly untouched.
# ------------------------------------------------------------
echo
echo "==> Step 2/4: rewrite [${SNOW_LIB_ADMIN_CONN}].warehouse -> ${TARGET_WAREHOUSE}"
replace_toml_value_in_section \
    "${SNOW_LIB_ADMIN_CONN}" \
    "warehouse" \
    "${TARGET_WAREHOUSE}" \
    "${CONNECTIONS_TOML}"

# ------------------------------------------------------------
# Step 3/4: parse-back verification using the same parse_toml_value
# helper that scripts 04/05 use to read connection values. Aborts before
# wasting a connection test if connections.toml did not round-trip cleanly.
# ------------------------------------------------------------
echo
echo "==> Step 3/4: parse-back verification"
NEW_VALUE="$(parse_toml_value "${SNOW_LIB_ADMIN_CONN}" 'warehouse' "${CONNECTIONS_TOML}")"
if [[ "${NEW_VALUE}" != "${TARGET_WAREHOUSE}" ]]; then
    echo "error: parse-back mismatch: expected '${TARGET_WAREHOUSE}', got '${NEW_VALUE}'" >&2
    echo "       inspect ${CONNECTIONS_TOML} and the most recent .bak.* backup." >&2
    exit 70
fi
echo "    OK: [${SNOW_LIB_ADMIN_CONN}].warehouse parses back as '${NEW_VALUE}'"

# ------------------------------------------------------------
# Step 4/4: re-run the full three-step JWT verification against the
# promoted warehouse. Same _lib.sh helper that 05_verify_admin_jwt.sh
# calls; DRY guarantees identical semantics in both contexts.
# ------------------------------------------------------------
echo
echo "==> Step 4/4: re-run full JWT verification against ${TARGET_WAREHOUSE}"
verify_admin_jwt_full "${ADMIN_USER}" "${SQL_FILE}"

cat <<EOF

==================================================================
admin connection promoted to ${TARGET_WAREHOUSE}.

[${SNOW_LIB_ADMIN_CONN}].warehouse in ${CONNECTIONS_TOML} now points at
${TARGET_WAREHOUSE}; the previous value is preserved in a timestamped
${CONNECTIONS_TOML}.bak.* file. Full JWT verification just re-ran successfully
against the promoted warehouse.

Next: set up the loader service-user key pair and verify the loader connection:
    ./scripts/snowflake_cli/setup.sh --phase loader
==================================================================
EOF
