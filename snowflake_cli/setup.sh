#!/usr/bin/env bash
# ============================================================
# scripts/snowflake_cli/setup.sh -- Snowflake CLI setup orchestrator.
#
# Single entry point for configuring and testing the Snowflake CLI for the
# OpenAccess Artwork Medallion Pipeline. Chmods every child script in this
# directory, then runs them in numeric order according to the selected phase.
#
# Quickstart:
#   chmod +x scripts/snowflake_cli/setup.sh
#   ./scripts/snowflake_cli/setup.sh --phase all
#
# Phases:
#   prereq   Local-only setup. Runs 00-03 (install snow, init ~/.snowflake,
#            generate admin RSA key pair, lock permissions on config.toml
#            and the private key). Safe to re-run.
#   admin    Snowflake-side admin bootstrap. Runs 04-05 (register the admin
#            public key via password-auth one-shot, then verify JWT-based
#            'admin' connection).
#            Required env:
#               SNOWFLAKE_ACCOUNT     account locator
#               SNOWFLAKE_ADMIN_USER  admin user (e.g., DKALLOS)
#               SNOWFLAKE_PASSWORD    admin temporary password (one-shot only)
#   loader   Loader service-user bootstrap. Runs 06-07 (rotate ARTWORK_LOADER_SVC
#            password, test the 'loader' connection). Requires `make iac` to
#            have created the V008 service user already.
#            Required env:
#               LOADER_NEW_PASSWORD   strong random value; also goes into .env
#   all      Runs prereq + admin, then prints the next-step reminder to
#            invoke `make iac` before re-running with --phase loader.
#
# Idempotent: every child script is safe to re-run.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
usage: setup.sh [--phase {prereq|admin|loader|all}]
  prereq   local-only steps 00-03 (install snow, init dirs, keypair, chmod)
  admin    Snowflake-side admin bootstrap (steps 04-05); requires
           SNOWFLAKE_ACCOUNT, SNOWFLAKE_ADMIN_USER, SNOWFLAKE_PASSWORD
  loader   loader service-user bootstrap (steps 06-07); requires
           LOADER_NEW_PASSWORD and 'make iac' must have already run V008
  all      prereq + admin, then prints reminder to run 'make iac' before loader
EOF
    exit 64
}

# Parse a single optional --phase NAME flag.
PHASE="all"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase) PHASE="${2:-}"; shift 2 ;;
        -h|--help|help) usage ;;
        *) echo "error: unknown argument '$1'" >&2; usage ;;
    esac
done

case "${PHASE}" in
    prereq|admin|loader|all) ;;
    *) echo "error: unknown phase '${PHASE}'" >&2; usage ;;
esac

chmod_children() {
    echo "==> chmod +x ${SCRIPT_DIR}/*.sh"
    chmod +x "${SCRIPT_DIR}"/*.sh
}

run() {
    local script="$1"; shift || true
    echo
    echo "==================================================================="
    echo "==> ${script}"
    echo "==================================================================="
    "${SCRIPT_DIR}/${script}" "$@"
}

phase_prereq() {
    run 00_install_snowflake_cli.sh
    run 01_init_snowflake_home.sh
    run 02_generate_admin_keypair.sh
    run 03_lock_config_permissions.sh
}

phase_admin() {
    : "${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT must be set for --phase admin}"
    : "${SNOWFLAKE_ADMIN_USER:?SNOWFLAKE_ADMIN_USER must be set for --phase admin}"
    : "${SNOWFLAKE_PASSWORD:?SNOWFLAKE_PASSWORD (admin temp password) must be set for --phase admin}"
    run 04_register_admin_public_key.sh
    run 05_verify_admin_jwt.sh
}

phase_loader() {
    : "${LOADER_NEW_PASSWORD:?LOADER_NEW_PASSWORD must be set for --phase loader}"
    run 06_rotate_loader_password.sh
    run 07_test_loader_connection.sh
}

chmod_children

case "${PHASE}" in
    prereq) phase_prereq ;;
    admin)  phase_admin ;;
    loader) phase_loader ;;
    all)
        phase_prereq
        phase_admin
        cat <<'EOF'

==================================================================
PHASE 'all' complete through admin verification.

Next steps (in this order):
  1. make iac                  # creates V008 ARTWORK_LOADER_SVC service user
  2. export LOADER_NEW_PASSWORD='<strong_random_value>'
  3. ./scripts/snowflake_cli/setup.sh --phase loader
  4. Copy LOADER_NEW_PASSWORD into .env as SNOWFLAKE_PASSWORD
==================================================================
EOF
        ;;
esac

echo
echo "==> setup.sh phase '${PHASE}' complete."
