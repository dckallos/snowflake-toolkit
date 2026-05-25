#!/usr/bin/env bash
# ============================================================
# scripts/snowflake_cli/setup.sh -- Snowflake CLI setup orchestrator.
#
# Single entry point for configuring and testing the Snowflake CLI for the
# OpenAccess Artwork Medallion Pipeline. Chmods every child script in this
# directory, then runs them in numeric order according to the selected phase.
#
# Quickstart (zero env exports):
#   chmod +x scripts/snowflake_cli/setup.sh
#   ./scripts/snowflake_cli/setup.sh --phase all
#
# `--phase admin` and `--phase all` no longer require any pre-set env vars.
# Account / admin user / warehouse are resolved from ~/.snowflake/config.toml
# (overridable via env vars) by scripts 04 and 05 themselves, using helpers
# in _lib.sh. SNOWFLAKE_PASSWORD is prompted interactively (read -rs) if it
# is not already exported; it is never written to disk.
#
# The admin password is needed 1-3 times per year (bootstrap + key rotations)
# and is intentionally NOT stored at rest. After the admin RSA key is
# registered by step 04, JWT auth takes over for every subsequent snow CLI
# invocation.
#
# Phases:
#   prereq   Local-only setup. Runs 00-03 (install snow, init ~/.snowflake,
#            generate admin RSA key pair, lock permissions on config.toml
#            and the private key). Safe to re-run.
#   admin    Snowflake-side admin bootstrap. Runs 04-05 (register the admin
#            public key via password-auth one-shot, then verify JWT-based
#            'admin' connection). Prompts for admin password if
#            SNOWFLAKE_PASSWORD is not pre-set.
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
  admin    Snowflake-side admin bootstrap (steps 04-05); zero env required.
           Account / admin user / warehouse parsed from
           ~/.snowflake/config.toml; admin password prompted interactively
           if SNOWFLAKE_PASSWORD is not already set.
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
    # No pre-flight env-var checks here: scripts 04 and 05 resolve account /
    # admin user / warehouse from ~/.snowflake/config.toml (overridable via
    # env vars) using _lib.sh helpers, and prompt interactively for
    # SNOWFLAKE_PASSWORD if it is not already set. Letting the child scripts
    # own resolution keeps the user-facing prompt and error messages in one
    # place.
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
  1. make iac                                        # creates V008 ARTWORK_LOADER_SVC
  2. export LOADER_NEW_PASSWORD='<strong_random_value>'
  3. ./scripts/snowflake_cli/setup.sh --phase loader
  4. Copy LOADER_NEW_PASSWORD into .env as SNOWFLAKE_PASSWORD

Note: --phase loader still requires LOADER_NEW_PASSWORD in the shell so
the rotation can be applied via `snow sql -c admin --variable<br>loader_password=...`. Unlike the admin password, the new loader password
must be persisted to .env afterwards (consumed by both the Phase 1A
extractor and the snow CLI loader connection), so an interactive prompt
would not remove the at-rest exposure.
==================================================================
EOF
        ;;
esac

echo
echo "==> setup.sh phase '${PHASE}' complete."
