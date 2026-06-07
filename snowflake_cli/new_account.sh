#!/usr/bin/env bash
# ============================================================
# scripts/snowflake_cli/new_account.sh -- Guided wrapper for onboarding a new
# Snowflake account into the multi-account connection framework.
#
# Runs setup.sh --profile <LABEL> --phase prereq + admin, then prints the
# exact next-step commands (make iac, promote, loader, transformer) with
# the correct --profile flag pre-filled.
#
# USAGE:
#   ./scripts/snowflake_cli/new_account.sh <PROFILE>
#   ./scripts/snowflake_cli/new_account.sh hw58276
#
# WHAT IT DOES (local + one-shot Snowflake bootstrap):
#   1. Generates (or reuses) the admin RSA key pair for the profile
#   2. Seeds [<PROFILE>] in ~/.snowflake/connections.toml (prompts for
#      SNOWFLAKE_ACCOUNT and SNOWFLAKE_ADMIN_USER if not exported)
#   3. Locks file permissions
#   4. Registers the admin public key on the account (prompts for password once)
#   5. Verifies JWT auth works
#   6. Prints remaining steps with paste-ready commands
#
# PREREQUISITES:
#   - snow CLI installed (or script 00 will install it)
#   - The target account exists and you know the admin credentials
#
# ENVIRONMENT OVERRIDES (all optional -- prompted interactively if unset):
#   SNOWFLAKE_ACCOUNT       e.g. JHTJUUT-HW58276
#   SNOWFLAKE_ADMIN_USER    e.g. PORCHSNOW
#   SNOWFLAKE_PASSWORD      admin password (prompted securely if unset)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
usage: new_account.sh <PROFILE>

  PROFILE   A short label for this account (e.g. hw58276, mk07348, prod).
            Becomes the connection name prefix:
              [<PROFILE>]              admin connection
              [<PROFILE>_loader]       loader service connection
              [<PROFILE>_transformer]  transformer service connection
            Key files are namespaced: <PROFILE>_rsa_key.p8, etc.

  Examples:
    ./scripts/snowflake_cli/new_account.sh hw58276
    SNOWFLAKE_ACCOUNT=JHTJUUT-HW58276 ./scripts/snowflake_cli/new_account.sh hw58276
EOF
    exit 64
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    usage
fi

PROFILE="$1"

if [[ ! "${PROFILE}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "error: invalid profile name '${PROFILE}'" >&2
    echo "       allowed characters: letters, digits, underscore, hyphen" >&2
    exit 64
fi

echo "==> Onboarding new account with profile: ${PROFILE}"
echo "==> Connection names: admin='${PROFILE}' loader='${PROFILE}_loader' transformer='${PROFILE}_transformer'"
echo "==> Key files: ~/.snowflake/keys/${PROFILE}_rsa_key.p8 (+ loader/transformer variants)"
echo

unset SNOWFLAKE_ACCOUNT SNOWFLAKE_ADMIN_USER SNOWFLAKE_PASSWORD \
      SNOW_LIB_KEY_DIR SNOW_LIB_CONNECTIONS_TOML SNOW_LIB_CONFIG_TOML \
      SNOW_LIB_DEFAULT_WAREHOUSE 2>/dev/null || true

"${SCRIPT_DIR}/setup.sh" --profile "${PROFILE}" --phase prereq
"${SCRIPT_DIR}/setup.sh" --profile "${PROFILE}" --phase admin

cat <<EOF

===================================================================
ACCOUNT ONBOARDED: ${PROFILE}
===================================================================

Admin connection [${PROFILE}] is live and verified (JWT auth).

Next steps (paste these in order):

  1. Deploy infrastructure to this account:
     make iac CONN=${PROFILE}

  2. Promote admin connection to ARTWORK_WH:
     ./scripts/snowflake_cli/setup.sh --profile ${PROFILE} --phase promote

  3. Bootstrap the loader service user:
     ./scripts/snowflake_cli/setup.sh --profile ${PROFILE} --phase loader

  4. Bootstrap the transformer (dbt) service user:
     ./scripts/snowflake_cli/setup.sh --profile ${PROFILE} --phase transformer

  5. Make this the default connection:
     ./scripts/snowflake_cli/setup.sh --profile ${PROFILE} --phase switch

Resulting connections.toml blocks:
  [${PROFILE}]              -> admin (ACCOUNTADMIN, JWT)
  [${PROFILE}_loader]       -> ARTWORK_LOADER_SVC (key-pair)
  [${PROFILE}_transformer]  -> ARTWORK_TRANSFORMER_SVC (key-pair)

Use with orchestrate_modern.sh:
  scripts/orchestrate_modern.sh --ddl-dir infrastructure/ \\
    --manifest scripts/manifest.txt --phase infra --connection ${PROFILE}
===================================================================
EOF
