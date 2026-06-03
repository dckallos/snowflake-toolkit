#!/usr/bin/env bash
# ============================================================
# init_profile.sh -- Seed the [connections.<admin>] block in
# ~/.snowflake/config.toml on a fresh machine.
#
# This closes the only manual gap left in the bootstrap chain: scripts 04 and
# 08 READ [connections.<admin>] (account / user / warehouse) and ABORT if the
# block is missing, but nothing in the suite ever CREATED it -- the operator
# had to hand-write config.toml first. This script creates that block from
# resolvable inputs so `--phase all` is runnable end-to-end on a clean box.
#
# The target connection name is SNOW_LIB_ADMIN_CONN (default 'admin'), set by
# setup.sh from --profile / --admin-conn. For a second account, run e.g.
# `setup.sh --profile clientb --phase init-profile`, which seeds
# [connections.clientb] using the clientb_rsa_key.p8 key path.
#
# It is LOCAL-ONLY: it touches nothing but ~/.snowflake/config.toml and creates
# no Snowflake objects. It is invoked both as its own `setup.sh --phase
# init-profile` and automatically inside `--phase prereq` (after the key pair
# exists in step 02, before step 03 locks file permissions).
#
# NON-DESTRUCTIVE BY DESIGN:
#   - If [connections.<admin>] already has a non-empty `account`, the block is
#     left untouched (reported and skipped). This protects an operator's
#     hand-tuned or promoted config from being clobbered.
#   - default_connection_name is set to the admin connection name ONLY if it is
#     currently unset; an existing value (any profile) is never overridden.
#
# Value resolution (each value is prompted interactively, OR overridable via
# its env var for non-interactive/CI use):
#   account    SNOWFLAKE_ACCOUNT      -> prompt (no default)
#   user       SNOWFLAKE_ADMIN_USER   -> prompt (no default)
#   role       SNOWFLAKE_ROLE         -> prompt [default ACCOUNTADMIN]
#   warehouse  SNOWFLAKE_WAREHOUSE    -> prompt [default INIT_DEFAULT_WAREHOUSE]
#   key file   ADMIN_PRIVATE_KEY_FILE -> ~/.snowflake/keys/<admin>_rsa_key.p8
#
# The login PASSWORD is NOT collected here. This project stores key-pair auth
# only; the password is prompted ONCE (hidden, `read -rs`) in `--phase admin`
# solely to register the RSA public key, and is never written to disk.
#
# Note the warehouse default here is COMPUTE_WH, NOT _lib.sh's ARTWORK_WH:
# at bootstrap time ARTWORK_WH does not exist yet (it is created later by
# `make iac`), and the admin connection needs an account-default warehouse to
# pass `snow connection test`. `--phase promote` flips it to ARTWORK_WH after
# `make iac`.
#
# Idempotent: re-running once the block exists is a reported no-op.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"
ADMIN_CONN="${SNOW_LIB_ADMIN_CONN}"
ADMIN_SECTION="connections.${ADMIN_CONN}"
PRIVATE_KEY="${ADMIN_PRIVATE_KEY_FILE:-$(admin_key_path p8)}"
INIT_DEFAULT_WAREHOUSE="${INIT_DEFAULT_WAREHOUSE:-COMPUTE_WH}"

# --- Ensure ~/.snowflake exists and config.toml is at least an empty file ---
# (01_init_snowflake_home.sh normally does the mkdir, but this script must be
# safe to run standalone too.)
mkdir -p "$(dirname "${CONFIG_TOML}")"
if [[ ! -f "${CONFIG_TOML}" ]]; then
    echo "==> creating empty ${CONFIG_TOML} (chmod 600)"
    : > "${CONFIG_TOML}"
    chmod 600 "${CONFIG_TOML}"
fi

# --- Non-destructive guard: bail out if this admin profile already exists ---
EXISTING_ACCOUNT="$(parse_toml_value "${ADMIN_SECTION}" 'account' "${CONFIG_TOML}")"
if [[ -n "${EXISTING_ACCOUNT}" ]]; then
    cat <<EOF
==> [${ADMIN_SECTION}] already configured (account = "${EXISTING_ACCOUNT}").
    Leaving it untouched. To change account/user/warehouse, edit
    ${CONFIG_TOML} by hand or use the dedicated phases (e.g. --phase promote
    for the warehouse). This script only SEEDS a missing admin profile.
EOF
    # Still ensure default_connection_name is set if it is currently absent.
    if [[ -z "$(parse_toml_toplevel_key 'default_connection_name' "${CONFIG_TOML}")" ]]; then
        echo "==> default_connection_name unset; setting it to \"${ADMIN_CONN}\""
        upsert_toml_toplevel_key 'default_connection_name' "${ADMIN_CONN}" "${CONFIG_TOML}"
    fi
    exit 0
fi

# --- Resolve the values for the new block --------------------------------
# Each value is prompted interactively (press Enter to accept the [default]),
# OR pre-supplied via its env var for non-interactive/CI use. The login
# PASSWORD is intentionally NOT asked here: this project stores key-pair auth
# only, so the password is prompted ONCE (hidden, via `read -rs`) during
# `--phase admin` purely to register your RSA public key -- never stored.
echo
echo "==> Configuring profile [${ADMIN_SECTION}]"
echo "    key pair: ${PRIVATE_KEY}"
echo "    (Enter = accept [default]; password is prompted later, hidden, in --phase admin)"
echo

ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
if [[ -z "${ACCOUNT}" ]]; then
    read -r -p "Snowflake account identifier (e.g. ORGNAME-ACCOUNTNAME): " ACCOUNT
fi
[[ -n "${ACCOUNT}" ]] || { echo "error: account identifier is required" >&2; exit 78; }

ADMIN_USER="${SNOWFLAKE_ADMIN_USER:-}"
if [[ -z "${ADMIN_USER}" ]]; then
    read -r -p "Snowflake login name: " ADMIN_USER
fi
[[ -n "${ADMIN_USER}" ]] || { echo "error: login name is required" >&2; exit 78; }

ROLE="${SNOWFLAKE_ROLE:-}"
if [[ -z "${ROLE}" ]]; then
    read -r -p "Role [ACCOUNTADMIN]: " ROLE
    ROLE="${ROLE:-ACCOUNTADMIN}"
fi

WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-}"
if [[ -z "${WAREHOUSE}" ]]; then
    read -r -p "Warehouse [${INIT_DEFAULT_WAREHOUSE}]: " WAREHOUSE
    WAREHOUSE="${WAREHOUSE:-${INIT_DEFAULT_WAREHOUSE}}"
fi

# --- default_connection_name only if currently unset ---------------------
# Written BEFORE the section block so a freshly-seeded file starts with the
# top-level key, then the [connections.<admin>] table (no leading blank line).
if [[ -z "$(parse_toml_toplevel_key 'default_connection_name' "${CONFIG_TOML}")" ]]; then
    upsert_toml_toplevel_key 'default_connection_name' "${ADMIN_CONN}" "${CONFIG_TOML}"
fi

# --- Seed [connections.<admin>] via the upsert helper (creates the block) -
echo "==> seeding [${ADMIN_SECTION}] in ${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'account'          "${ACCOUNT}"      "${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'user'             "${ADMIN_USER}"   "${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'role'             "${ROLE}"         "${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'warehouse'        "${WAREHOUSE}"    "${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'authenticator'    'SNOWFLAKE_JWT'   "${CONFIG_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'private_key_file' "${PRIVATE_KEY}"  "${CONFIG_TOML}"

cat <<EOF

==> [${ADMIN_SECTION}] seeded.
    account          = ${ACCOUNT}
    user             = ${ADMIN_USER}
    role             = ${ROLE}
    warehouse        = ${WAREHOUSE}   (account-default; promote to ARTWORK_WH later)
    authenticator    = SNOWFLAKE_JWT
    private_key_file = ${PRIVATE_KEY}

Next: register the public key and verify JWT auth:
    ./scripts/snowflake_cli/setup.sh --phase admin
EOF
