#!/usr/bin/env bash
# ============================================================
# 05_verify_admin_jwt.sh -- Verify the JWT-based 'admin' connection
# end-to-end using the warehouse currently configured under
# [connections.admin] in ~/.snowflake/config.toml.
#
# Runs the full three-step JWT verification provided by _lib.sh's
# verify_admin_jwt_full helper:
#   1. Re-apply register_admin_public_key.sql via 'snow sql -c admin
#      --filename ...' (proves JWT auth end-to-end; idempotent re-register).
#   2. 'snow connection test -c admin' (full session handshake using the
#      warehouse currently configured under [connections.admin]).
#   3. 'snow sql -c admin -q "SELECT CURRENT_USER(), CURRENT_ROLE();"'
#      (real query round-trip that exercises the warehouse).
#
# Warehouse dependency:
#   [connections.admin].warehouse MUST point at a warehouse that EXISTS in
#   Snowflake when this script runs. The project's initial config.toml
#   intentionally points at an account-default warehouse that is present
#   on day one (for fresh Snowflake trial accounts that is COMPUTE_WH, the
#   auto-created default), so '--phase admin' / '--phase all' succeed
#   BEFORE 'make iac' has created ARTWORK_WH. After 'make iac' runs and
#   creates ARTWORK_WH, 08_promote_admin_warehouse.sh rewrites
#   [connections.admin].warehouse to ARTWORK_WH and re-runs this same
#   verification path against the promoted warehouse via the same
#   _lib.sh helper.
#
# Zero-export resolution order (handled by _lib.sh helpers):
#   SNOWFLAKE_ADMIN_USER  env var -> [connections.admin].user in config.toml
#
# No password is needed -- this script exercises JWT auth via the 'admin'
# connection defined in ~/.snowflake/config.toml.
#
# Optional env:
#   ADMIN_PUBLIC_KEY_FILE defaults to ~/.snowflake/keys/admin_rsa_key.pub
#   SQL_FILE              defaults to git-setup/operator/register_admin_public_key.sql
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

ADMIN_USER="$(resolve_admin_user)"
SQL_FILE="${SQL_FILE:-${REPO_ROOT}/git-setup/operator/register_admin_public_key.sql}"

verify_admin_jwt_full "${ADMIN_USER}" "${SQL_FILE}"

CURRENT_WAREHOUSE="$(parse_toml_value 'connections.admin' 'warehouse' "${HOME}/.snowflake/config.toml")"
echo
echo "==> admin JWT connection verified end-to-end against warehouse '${CURRENT_WAREHOUSE}'."
