#!/usr/bin/env bash
# ============================================================
# snowflake_cli/setup.sh -- Snowflake CLI setup orchestrator.
#
# Single entry point for configuring and testing the Snowflake CLI for the
# OpenAccess Artwork Medallion Pipeline. Chmods every child script in this
# directory, then runs them in numeric order according to the selected phase.
#
# Quickstart (zero env exports):
#   chmod +x snowflake_cli/setup.sh
#   ./snowflake_cli/setup.sh --phase all
#
# `--phase admin` and `--phase all` no longer require any pre-set env vars.
# Account / admin user / warehouse are resolved from ~/.snowflake/connections.toml
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
#   prereq   Local-only setup. Runs 00-02, then init_profile.sh, then 03
#            (install snow, init ~/.snowflake, generate admin RSA key pair,
#            seed [<admin>] in connections.toml if missing, lock
#            permissions on the toml files and the private key). Safe to re-run.
#   init-profile  Local-only. Seed [<admin>] in
#            ~/.snowflake/connections.toml from SNOWFLAKE_ADMIN_ACCOUNT /
#            SNOWFLAKE_ADMIN_USER (prompted if unset) + the admin key path.
#            Non-destructive: if the block already has an account it is left
#            untouched. Also sets default_connection_name = "admin" (in
#            config.toml) when unset.
#            Runs automatically inside `prereq`; exposed standalone for
#            re-seeding a fresh connections.toml. Creates NO Snowflake objects.
#   admin    Snowflake-side admin bootstrap. Runs 04-05 (register the admin
#            public key via password-auth one-shot, then verify JWT-based
#            'admin' connection end-to-end against whatever warehouse is
#            currently in [<admin>] -- initially an account-
#            default such as COMPUTE_WH, later ARTWORK_WH after promote).
#            Prompts for admin password if SNOWFLAKE_PASSWORD is not
#            pre-set.
#   loader   Loader service-user bootstrap. Runs 06-07 (generate the loader
#            RSA key pair, register its public key on ARTWORK_LOADER_SVC via
#            the admin JWT connection, rewrite [<loader>] for
#            key-pair auth, then test the 'loader' connection). Requires
#            `make infra` to have created the (TYPE = SERVICE) service user
#            already. No env vars and no password required.
#   transformer  dbt service-user bootstrap. Runs 09-10 (generate the
#            transformer RSA key pair, register its public key on
#            ARTWORK_TRANSFORMER_SVC via the admin JWT connection, rewrite
#            [<transformer>] for key-pair auth, then test it).
#            Requires `make infra` to have created ARTWORK_TRANSFORMER_SVC
#            (TYPE = SERVICE). No env vars and no password required.
#   promote  Promote the admin connection from the initial account-default
#            warehouse to ARTWORK_WH. Runs 08 (verify ARTWORK_WH exists,
#            back up ~/.snowflake/connections.toml, rewrite
#            [<admin>].warehouse, chmod 600, re-run the full
#            JWT verification against ARTWORK_WH). Requires `make infra` to
#            have already created ARTWORK_WH. Creates NO new Snowflake
#            objects.
#   all      Runs prereq + admin, then prints the next-step reminder to
#            invoke `make infra`, then `--phase promote`, then
#            `--phase loader`. Does NOT run promote automatically (promote
#            depends on make infra, which is outside setup.sh).
#
# Idempotent: every child script is safe to re-run.
#
# ------------------------------------------------------------
# Multi-account support
# ------------------------------------------------------------
# By default this suite manages the connection trio admin / loader / transformer.
# To manage a SECOND Snowflake account, pass a profile label and every step
# targets a namespaced connection set + key files:
#
#   ./setup.sh --profile clientb --phase all
#     -> admin connection       = [clientb]             key clientb_rsa_key.p8
#     -> loader connection      = [clientb_loader]      key clientb_loader_rsa_key.p8
#     -> transformer connection = [clientb_transformer] key clientb_transformer_rsa_key.p8
#
# Advanced: override names explicitly with --admin-conn / --loader-conn /
# --transformer-conn. With no flags the names are admin / loader / transformer
# and the historical admin_rsa_key.p8 / loader_rsa_key.p8 key paths are preserved.
#
# Inspect and switch the active account (these touch NO Snowflake objects):
#   ./setup.sh --phase list                 # list profiles + mark the default
#   ./setup.sh --profile clientb --phase switch   # set default_connection_name
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

usage() {
    cat <<'EOF'
usage: setup.sh [--profile LABEL | --admin-conn NAME --loader-conn NAME --transformer-conn NAME]
                [--account ACCOUNT --admin-user USER]
                [--admin-role ROLE] [--init-warehouse WAREHOUSE] [--target-warehouse WAREHOUSE]
                [--replace-existing]
                [--phase {prereq|init-profile|admin|loader|transformer|promote|all|list|switch}]

  Connection selection (default trio: admin / loader / transformer):
    --profile LABEL    target [LABEL] + [LABEL_loader]
                       + [LABEL_transformer] (matching key files)
    --admin-conn NAME  explicit admin connection name (overrides --profile)
    --loader-conn NAME explicit loader connection name (overrides --profile)
    --transformer-conn NAME explicit transformer connection name (overrides --profile)

  Admin bootstrap values (safe replacements for generic project .env variables):
    --account ACCOUNT        Snowflake account identifier, e.g. DSHXYWJ-KW94245
    --admin-user USER        Admin login name, e.g. PORCHORCH
    --admin-role ROLE        Role for the admin profile. Default: ACCOUNTADMIN
    --init-warehouse NAME    Existing day-one warehouse for bootstrap. Default: COMPUTE_WH
    --target-warehouse NAME  Post-IaC admin warehouse for --phase promote. Default: ARTWORK_WH
    --replace-existing       Rewrite an existing [admin/profile] local block after backup.
                             Without this flag, a mismatched existing account is refused.

  prereq   local-only steps 00-02 + init_profile.sh + step 03 (install snow,
           init dirs, keypair, seed [<admin>] if missing, chmod)
  init-profile
           local-only: seed [<admin>] in ~/.snowflake/connections.toml
           from --account / --admin-user (or SNOWFLAKE_ADMIN_ACCOUNT /
           SNOWFLAKE_ADMIN_USER), prompted if unset
           and the admin key path. Non-destructive (skips if account already
           set); sets default_connection_name (in config.toml) when unset.
           Creates NO Snowflake objects.
  admin    Snowflake-side admin bootstrap (steps 04-05); zero env required.
           Account / admin user / warehouse parsed from
           ~/.snowflake/connections.toml; admin password prompted interactively
           if SNOWFLAKE_PASSWORD is not already set. Runs full verification
           against the warehouse currently in [<admin>]
           (initially an account-default like COMPUTE_WH).
  loader   loader service-user bootstrap (steps 06-07); requires 'make infra'
           to have already created the (TYPE = SERVICE) ARTWORK_LOADER_SVC.
           Generates the loader key pair, registers it via the admin JWT
           connection, rewrites [<loader>] for key-pair auth, and
           tests the connection. No env vars / no password required.
  transformer
           dbt service-user bootstrap (steps 09-10); requires 'make infra' to
           have already created the (TYPE = SERVICE) ARTWORK_TRANSFORMER_SVC.
           Generates the transformer key pair, registers it via the admin JWT
           connection, rewrites [<transformer>] for key-pair auth,
           and tests the connection. No env vars / no password required.
  promote  promote admin connection to ARTWORK_WH (step 08); requires
           'make infra' to have already created ARTWORK_WH. Rewrites
           [<admin>].warehouse in ~/.snowflake/connections.toml,
           backs up the previous file, and re-runs full JWT verification
           against the promoted warehouse. Creates NO new Snowflake objects.
  all      prereq + admin, then prints reminder to run 'make infra', then
           '--phase promote', then '--phase loader'. Does NOT run promote
           automatically.
  list     local-only: list every connection in connections.toml and mark
           the default_connection_name. Creates NO Snowflake objects.
  switch   local-only: set default_connection_name to the selected admin
           connection (from --profile / --admin-conn). Creates NO Snowflake
           objects.
EOF
    exit 64
}

# Parse optional flags: --phase, plus the connection selectors.
PHASE="all"
PROFILE=""
ADMIN_CONN_FLAG=""
LOADER_CONN_FLAG=""
TRANSFORMER_CONN_FLAG=""
ACCOUNT_FLAG=""
ADMIN_USER_FLAG=""
ADMIN_ROLE_FLAG=""
INIT_WAREHOUSE_FLAG=""
TARGET_WAREHOUSE_FLAG=""
REPLACE_EXISTING="0"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)       PHASE="${2:-}";            shift 2 ;;
        --profile)     PROFILE="${2:-}";          shift 2 ;;
        --admin-conn)  ADMIN_CONN_FLAG="${2:-}";  shift 2 ;;
        --loader-conn) LOADER_CONN_FLAG="${2:-}"; shift 2 ;;
        --transformer-conn) TRANSFORMER_CONN_FLAG="${2:-}"; shift 2 ;;
        --account)     ACCOUNT_FLAG="${2:-}";     shift 2 ;;
        --admin-user)  ADMIN_USER_FLAG="${2:-}";  shift 2 ;;
        --admin-role)  ADMIN_ROLE_FLAG="${2:-}";  shift 2 ;;
        --init-warehouse|--admin-warehouse) INIT_WAREHOUSE_FLAG="${2:-}"; shift 2 ;;
        --target-warehouse) TARGET_WAREHOUSE_FLAG="${2:-}"; shift 2 ;;
        --replace-existing) REPLACE_EXISTING="1"; shift ;;
        -h|--help|help) usage ;;
        *) echo "error: unknown argument '$1'" >&2; usage ;;
    esac
done

case "${PHASE}" in
    prereq|init-profile|admin|loader|transformer|promote|all|list|switch) ;;
    *) echo "error: unknown phase '${PHASE}'" >&2; usage ;;
esac

# Resolve the admin/loader connection names. Explicit --admin-conn/--loader-conn
# win; otherwise --profile LABEL yields LABEL / LABEL_loader; otherwise the
# historical defaults admin / loader (which preserve the original key paths).
if [[ -n "${PROFILE}" ]]; then
    ADMIN_CONN="${ADMIN_CONN_FLAG:-${PROFILE}}"
    LOADER_CONN="${LOADER_CONN_FLAG:-${PROFILE}_loader}"
    TRANSFORMER_CONN="${TRANSFORMER_CONN_FLAG:-${PROFILE}_transformer}"
else
    ADMIN_CONN="${ADMIN_CONN_FLAG:-admin}"
    LOADER_CONN="${LOADER_CONN_FLAG:-loader}"
    TRANSFORMER_CONN="${TRANSFORMER_CONN_FLAG:-transformer}"
fi

# Validate (these names become TOML section keys and `snow -c` args) and export
# so every child script resolves the same target account via _lib.sh.
validate_conn_name "${ADMIN_CONN}"  || exit $?
validate_conn_name "${LOADER_CONN}" || exit $?
validate_conn_name "${TRANSFORMER_CONN}" || exit $?
export ADMIN_CONN LOADER_CONN TRANSFORMER_CONN

# Dedicated admin/bootstrap values. These are intentionally separate from
# generic SNOWFLAKE_* runtime variables, which the Snowflake CLI may treat as
# connection overrides and which project .env files commonly set for loader/dbt.
[[ -z "${ACCOUNT_FLAG}" ]] || export SNOWFLAKE_ADMIN_ACCOUNT="${ACCOUNT_FLAG}"
[[ -z "${ADMIN_USER_FLAG}" ]] || export SNOWFLAKE_ADMIN_USER="${ADMIN_USER_FLAG}"
[[ -z "${ADMIN_ROLE_FLAG}" ]] || export SNOWFLAKE_ADMIN_ROLE="${ADMIN_ROLE_FLAG}"
if [[ -n "${INIT_WAREHOUSE_FLAG}" ]]; then
    export SNOWFLAKE_ADMIN_WAREHOUSE="${INIT_WAREHOUSE_FLAG}"
    export INIT_DEFAULT_WAREHOUSE="${INIT_WAREHOUSE_FLAG}"
fi
[[ -z "${TARGET_WAREHOUSE_FLAG}" ]] || export TARGET_WAREHOUSE="${TARGET_WAREHOUSE_FLAG}"
[[ "${REPLACE_EXISTING}" != "1" ]] || export SNOWFLAKE_PROFILE_REPLACE="1"

echo "==> connections: admin='${ADMIN_CONN}' loader='${LOADER_CONN}' transformer='${TRANSFORMER_CONN}'"
if [[ -n "${SNOWFLAKE_ADMIN_ACCOUNT:-}" || -n "${SNOWFLAKE_ADMIN_USER:-}" ]]; then
    echo "==> admin target: account='${SNOWFLAKE_ADMIN_ACCOUNT:-<prompt/file>}' user='${SNOWFLAKE_ADMIN_USER:-<prompt/file>}'"
fi

chmod_children() {
    # NOTE: scripts/bootstrap_chmod.sh is the CANONICAL chmod policy for
    # every .sh in the bootstrap.py call graph (covers scripts/apply_sql.sh,
    # scripts/rollback_sql.sh, scripts/run_pipeline.sh, and everything
    # under scripts/snowflake_cli/). See Phase 0.6 IaC strategy § 3.4.
    # This helper is retained as a defensive no-op for the orchestrator's
    # own subtree; `make infra` auto-runs `bash scripts/bootstrap_chmod.sh`
    # via its PHONY `chmod` prereq, so the executable bit on every
    # script in the call graph is guaranteed before bootstrap.py shells
    # out via subprocess.run(...).
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

phase_init_profile() {
    # Local-only: seed [<admin>] in connections.toml if it is missing.
    # init_profile.sh sources _lib.sh, is non-destructive (skips when the
    # admin account is already set), and creates no Snowflake objects.
    run init_profile.sh
}

phase_prereq() {
    run 00_install_snowflake_cli.sh
    run 01_init_snowflake_home.sh
    run 02_generate_admin_keypair.sh
    # Seed [<admin>] AFTER the key pair exists (so private_key_path
    # points at a real file) and BEFORE 03 locks the toml-file permissions.
    phase_init_profile
    run 03_lock_config_permissions.sh
}

phase_admin() {
    # No pre-flight env-var checks here: scripts 04 and 05 resolve account /
    # admin user / warehouse from ~/.snowflake/connections.toml (overridable via
    # env vars) using _lib.sh helpers, and prompt interactively for
    # SNOWFLAKE_PASSWORD if it is not already set. Letting the child scripts
    # own resolution keeps the user-facing prompt and error messages in one
    # place.
    run 04_register_admin_public_key.sh
    run 05_verify_admin_jwt.sh
}

phase_loader() {
    # No env-var prerequisites: 06_setup_loader_keypair.sh generates the loader
    # RSA key pair lazily, registers the public key on ARTWORK_LOADER_SVC via the
    # admin JWT connection, and rewrites [<loader>] for key-pair auth.
    # `make infra` must have already created the (TYPE = SERVICE) user.
    run 06_setup_loader_keypair.sh
    run 07_test_loader_connection.sh
}

phase_transformer() {
    # No env-var prerequisites: 09_setup_transformer_keypair.sh generates the
    # transformer RSA key pair lazily, registers the public key on
    # ARTWORK_TRANSFORMER_SVC via the admin JWT connection, and rewrites
    # [<transformer>] for key-pair auth. `make infra` must have already
    # created the (TYPE = SERVICE) user.
    run 09_setup_transformer_keypair.sh
    run 10_test_transformer_connection.sh
}

phase_promote() {
    # No pre-flight env-var checks: 08_promote_admin_warehouse.sh sources
    # _lib.sh to resolve the admin user from ~/.snowflake/connections.toml and
    # verifies ARTWORK_WH exists in Snowflake before rewriting connections.toml.
    # JWT auth via the existing admin RSA key pair; no admin password is
    # required.
    run 08_promote_admin_warehouse.sh
}

phase_list() {
    # Local-only: enumerate every connection in connections.toml and mark the
    # default. Touches no Snowflake objects (resolved entirely from the files).
    list_connections
}

phase_switch() {
    # Local-only: point default_connection_name at the selected admin connection
    # (resolved above from --profile / --admin-conn). Touches no Snowflake objects.
    set_default_connection "${ADMIN_CONN}"
}

chmod_children

case "${PHASE}" in
    prereq)       phase_prereq ;;
    init-profile) phase_init_profile ;;
    admin)        phase_admin ;;
    loader)       phase_loader ;;
    transformer)  phase_transformer ;;
    promote)      phase_promote ;;
    list)         phase_list ;;
    switch)       phase_switch ;;
    all)
        phase_prereq
        phase_admin
        PROFILE_FLAG=""
        if [[ -n "${PROFILE}" ]]; then
            PROFILE_FLAG=" --profile ${PROFILE}"
        fi
        LOADER_KEY="$(loader_key_path p8)"
        TRANSFORMER_KEY="$(transformer_key_path p8)"
        cat <<EOF

==================================================================
PHASE 'all' complete through admin verification (against the initial
account-default warehouse, e.g. COMPUTE_WH).

Next steps (in this order):
  1. make infra CONN=${ADMIN_CONN}
     # creates ARTWORK_WH, ARTWORK_DB, ARTWORK_LOADER_SVC (TYPE = SERVICE), etc.
  2. ${SCRIPT_DIR}/setup.sh${PROFILE_FLAG} --phase promote
     # rewrites [${ADMIN_CONN}].warehouse to ARTWORK_WH and
     # re-verifies; no further manual checks needed.
  3. ${SCRIPT_DIR}/setup.sh${PROFILE_FLAG} --phase loader
     # generates the loader key pair, registers it on ARTWORK_LOADER_SVC via
     # the admin JWT connection, and switches [${LOADER_CONN}] to
     # key-pair auth -- no password anywhere.
  4. ${SCRIPT_DIR}/setup.sh${PROFILE_FLAG} --phase transformer
     # same flow for ARTWORK_TRANSFORMER_SVC (the dbt identity); switches
     # [${TRANSFORMER_CONN}] to key-pair auth.
  5. In .env, point the Python extractor + dbt at their private keys:
     #   SNOWFLAKE_PRIVATE_KEY_FILE=${LOADER_KEY}
     #   DBT_SNOWFLAKE_USER=ARTWORK_TRANSFORMER_SVC
     #   DBT_SNOWFLAKE_PRIVATE_KEY_PATH=${TRANSFORMER_KEY}

Or skip steps 1-4 with the all-in-one activation script:
     ./activate_mac.sh --project-dir ~/dev/artwork-db${PROFILE_FLAG}

Note: --phase loader needs NO env vars and no password. The loader has no
chicken-and-egg problem -- a working admin JWT connection already exists, so
the loader public key is registered by admin over JWT and the service user
(TYPE = SERVICE) authenticates only with its key pair. Nothing secret is
written to disk except the key files themselves (chmod 600).

Note: --phase promote creates NO new Snowflake objects. ARTWORK_WH must
already exist (created by infrastructure/create_warehouses.sql via
'make infra CONN=${ADMIN_CONN}'); promote only verifies it, rewrites connections.toml
in code (with a timestamped backup), and re-runs the full JWT verification.
==================================================================
EOF
        ;;
esac

echo
echo "==> setup.sh phase '${PHASE}' complete."
