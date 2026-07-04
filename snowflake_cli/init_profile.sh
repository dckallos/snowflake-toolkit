#!/usr/bin/env bash
# ============================================================
# init_profile.sh -- Seed the [<admin>] connection block in
# ~/.snowflake/connections.toml on a fresh machine.
#
# This closes the only manual gap left in the bootstrap chain: scripts 04 and
# 08 READ the admin connection (account / user / warehouse) and ABORT if the
# block is missing, but nothing in the suite ever CREATED it -- the operator
# had to hand-write it first. This script creates that block from
# resolvable inputs so `--phase all` is runnable end-to-end on a clean box.
#
# Connection definitions are written to connections.toml (the file the snow CLI,
# the VS Code extension, and the Python connector all read). config.toml is
# retained only for default_connection_name and [cli.*] settings.
#
# The target connection name is SNOW_LIB_ADMIN_CONN (default 'admin'), set by
# setup.sh from --profile / --admin-conn. For a second account, run e.g.
# `setup.sh --profile clientb --phase init-profile`, which seeds
# [clientb] using the clientb_rsa_key.p8 key path.
#
# It is LOCAL-ONLY: it touches nothing but ~/.snowflake/{connections,config}.toml
# and creates no Snowflake objects. It is invoked both as its own `setup.sh
# --phase init-profile` and automatically inside `--phase prereq` (after the key
# pair exists in step 02, before step 03 locks file permissions).
#
# NON-DESTRUCTIVE BY DESIGN:
#   - If [<admin>] already has a non-empty `account` in connections.toml, the
#     block is left untouched (reported and skipped). This protects an operator's
#     hand-tuned or promoted config from being clobbered.
#   - default_connection_name is set to the admin connection name ONLY if it is
#     currently unset; an existing value (any profile) is never overridden.
#
# Value resolution (each value is prompted interactively, OR overridable via
# explicit admin env vars / setup.sh flags for non-interactive use):
#   account    SNOWFLAKE_ADMIN_ACCOUNT -> prompt (no default)
#   user       SNOWFLAKE_ADMIN_USER    -> prompt (no default)
#   role       SNOWFLAKE_ADMIN_ROLE    -> prompt [default ACCOUNTADMIN]
#   warehouse  SNOWFLAKE_ADMIN_WAREHOUSE -> prompt [default INIT_DEFAULT_WAREHOUSE]
#   key file   ADMIN_PRIVATE_KEY_FILE  -> ~/.snowflake/keys/<admin>_rsa_key.p8
#
# Generic runtime vars such as SNOWFLAKE_ACCOUNT / SNOWFLAKE_ROLE are
# intentionally ignored here unless SNOWFLAKE_TOOLKIT_ALLOW_GENERIC_ADMIN_ENV=1,
# because project .env files commonly contain loader/dbt values that are wrong
# for first-time admin bootstrap.
#
# The login PASSWORD is NOT collected here. This project stores key-pair auth
# only; the password is prompted ONCE (hidden, `read -rs`) in `--phase admin`
# solely to register the RSA public key, and is never written to disk.
#
# Note the warehouse default here is COMPUTE_WH, NOT _lib.sh's ARTWORK_WH:
# at bootstrap time ARTWORK_WH does not exist yet (it is created later by
# `make infra`), and the admin connection needs an account-default warehouse to
# pass `snow connection test`. `--phase promote` flips it to ARTWORK_WH after
# `make infra`.
#
# Idempotent: re-running once the block exists is a reported no-op.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"             # keeps default_connection_name + [cli.*]
CONNECTIONS_TOML="${SNOW_LIB_CONNECTIONS_TOML}"   # connection DEFINITIONS live here
ADMIN_CONN="${SNOW_LIB_ADMIN_CONN}"
ADMIN_SECTION="${ADMIN_CONN}"                     # UN-prefixed bare section in connections.toml
PRIVATE_KEY="${ADMIN_PRIVATE_KEY_FILE:-$(admin_key_path p8)}"
INIT_DEFAULT_WAREHOUSE="${INIT_DEFAULT_WAREHOUSE:-COMPUTE_WH}"

# --- Ensure ~/.snowflake exists and BOTH toml files are at least empty files ---
# (01_init_snowflake_home.sh normally does the mkdir, but this script must be
# safe to run standalone too.) config.toml is retained for default_connection_name
# and [cli.*]; connections.toml is the primary target for connection definitions.
mkdir -p "$(dirname "${CONFIG_TOML}")"
if [[ ! -f "${CONFIG_TOML}" ]]; then
    echo "==> creating empty ${CONFIG_TOML} (chmod 600)"
    : > "${CONFIG_TOML}"
    chmod 600 "${CONFIG_TOML}"
fi
if [[ ! -f "${CONNECTIONS_TOML}" ]]; then
    echo "==> creating empty ${CONNECTIONS_TOML} (chmod 600)"
    : > "${CONNECTIONS_TOML}"
    chmod 600 "${CONNECTIONS_TOML}"
fi

# --- connections.toml is the PRIMARY connection store (Snowflake CLI docs) ----
# When ~/.snowflake/connections.toml exists, the snow CLI reads connections ONLY
# from it and IGNORES every [connections.*] block in config.toml. The VS Code
# extension and the Python connector also read connections.toml exclusively.
# This script therefore seeds the admin connection DIRECTLY into connections.toml
# as an UN-prefixed bare section ([${ADMIN_CONN}], not [connections.${ADMIN_CONN}]).
# default_connection_name is always read from config.toml, so it stays there.

# --- Non-destructive guard: bail out if this admin profile already exists ---
EXISTING_ACCOUNT="$(parse_toml_value "${ADMIN_SECTION}" 'account' "${CONNECTIONS_TOML}")"
REQUESTED_ACCOUNT="${SNOWFLAKE_ADMIN_ACCOUNT:-}"
if [[ -z "${REQUESTED_ACCOUNT}" && "${SNOWFLAKE_TOOLKIT_ALLOW_GENERIC_ADMIN_ENV:-0}" == "1" ]]; then
    REQUESTED_ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
fi
if [[ -n "${EXISTING_ACCOUNT}" && "${SNOWFLAKE_PROFILE_REPLACE:-0}" != "1" ]]; then
    if [[ -n "${REQUESTED_ACCOUNT}" && "${REQUESTED_ACCOUNT}" != "${EXISTING_ACCOUNT}" ]]; then
        cat >&2 <<EOF
error: [${ADMIN_SECTION}] already points at account "${EXISTING_ACCOUNT}",
       but this run requested "${REQUESTED_ACCOUNT}". Refusing to silently reuse
       the wrong Snowflake account.

       To intentionally rewrite this local profile, re-run with:
         setup.sh --profile ${ADMIN_SECTION} --account ${REQUESTED_ACCOUNT} --replace-existing --phase prereq

       A timestamped backup of ${CONNECTIONS_TOML} is created for every rewrite.
EOF
        exit 78
    fi
    cat <<EOF
==> [${ADMIN_SECTION}] already configured in ${CONNECTIONS_TOML} (account = "${EXISTING_ACCOUNT}").
    Leaving it untouched. To change account/user/warehouse, pass --replace-existing
    with explicit --account/--admin-user, edit ${CONNECTIONS_TOML} by hand, or use
    dedicated phases such as --phase promote for post-IaC warehouse promotion.
EOF
    # Still ensure default_connection_name is set if it is currently absent.
    # (default_connection_name lives in config.toml, not connections.toml.)
    if [[ -z "$(parse_toml_toplevel_key 'default_connection_name' "${CONFIG_TOML}")" ]]; then
        echo "==> default_connection_name unset; setting it to \"${ADMIN_CONN}\""
        upsert_toml_toplevel_key 'default_connection_name' "${ADMIN_CONN}" "${CONFIG_TOML}"
    fi
    exit 0
fi
if [[ -n "${EXISTING_ACCOUNT}" && "${SNOWFLAKE_PROFILE_REPLACE:-0}" == "1" ]]; then
    echo "==> --replace-existing set; rewriting [${ADMIN_SECTION}] in ${CONNECTIONS_TOML}"
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

ACCOUNT="${SNOWFLAKE_ADMIN_ACCOUNT:-}"
if [[ -z "${ACCOUNT}" && "${SNOWFLAKE_TOOLKIT_ALLOW_GENERIC_ADMIN_ENV:-0}" == "1" ]]; then
    ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
fi
if [[ -z "${ACCOUNT}" ]]; then
    read -r -p "Snowflake account identifier (e.g. ORGNAME-ACCOUNTNAME): " ACCOUNT
fi
[[ -n "${ACCOUNT}" ]] || { echo "error: account identifier is required" >&2; exit 78; }

ADMIN_USER="${SNOWFLAKE_ADMIN_USER:-}"
if [[ -z "${ADMIN_USER}" ]]; then
    read -r -p "Snowflake login name: " ADMIN_USER
fi
[[ -n "${ADMIN_USER}" ]] || { echo "error: login name is required" >&2; exit 78; }

ROLE="${SNOWFLAKE_ADMIN_ROLE:-}"
if [[ -z "${ROLE}" && "${SNOWFLAKE_TOOLKIT_ALLOW_GENERIC_ADMIN_ENV:-0}" == "1" ]]; then
    ROLE="${SNOWFLAKE_ROLE:-}"
fi
if [[ -z "${ROLE}" ]]; then
    read -r -p "Role [ACCOUNTADMIN]: " ROLE
    ROLE="${ROLE:-ACCOUNTADMIN}"
fi

WAREHOUSE="${SNOWFLAKE_ADMIN_WAREHOUSE:-}"
if [[ -z "${WAREHOUSE}" && "${SNOWFLAKE_TOOLKIT_ALLOW_GENERIC_ADMIN_ENV:-0}" == "1" ]]; then
    WAREHOUSE="${SNOWFLAKE_WAREHOUSE:-}"
fi
if [[ -z "${WAREHOUSE}" ]]; then
    read -r -p "Warehouse [${INIT_DEFAULT_WAREHOUSE}]: " WAREHOUSE
    WAREHOUSE="${WAREHOUSE:-${INIT_DEFAULT_WAREHOUSE}}"
fi

# --- default_connection_name only if currently unset ---------------------
# Lives in config.toml (the snow CLI reads it there even when the connection
# definitions live in connections.toml). Only set when currently absent.
if [[ -z "$(parse_toml_toplevel_key 'default_connection_name' "${CONFIG_TOML}")" ]]; then
    upsert_toml_toplevel_key 'default_connection_name' "${ADMIN_CONN}" "${CONFIG_TOML}"
fi

# --- Seed [<admin>] in connections.toml via the upsert helper (creates block) -
# Key field is private_key_path (NOT private_key_file): connections.toml is read
# by the VS Code extension and the Python connector, which expect private_key_path.
# The snow CLI accepts private_key_path in connections.toml as well.
echo "==> seeding [${ADMIN_SECTION}] in ${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'account'          "${ACCOUNT}"      "${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'user'             "${ADMIN_USER}"   "${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'role'             "${ROLE}"         "${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'warehouse'        "${WAREHOUSE}"    "${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'authenticator'    'SNOWFLAKE_JWT'   "${CONNECTIONS_TOML}"
upsert_toml_value_in_section "${ADMIN_SECTION}" 'private_key_path' "${PRIVATE_KEY}"  "${CONNECTIONS_TOML}"

# --- Ensure the key pair exists (connections.toml must never reference a missing file) -
PUBLIC_KEY="${PRIVATE_KEY%.p8}.pub"
if [[ ! -f "${PRIVATE_KEY}" ]]; then
    echo "==> key file not found at ${PRIVATE_KEY}; generating..."
    mkdir -p "$(dirname "${PRIVATE_KEY}")"
    openssl genrsa 2048 \
        | openssl pkcs8 -topk8 -inform PEM -out "${PRIVATE_KEY}" -nocrypt
    openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"
    chmod 600 "${PRIVATE_KEY}"
    chmod 644 "${PUBLIC_KEY}"
    echo "==> generated ${PRIVATE_KEY} + ${PUBLIC_KEY}"
fi

PROFILE_FLAG=""
if [[ "${ADMIN_CONN}" != "admin" ]]; then
    PROFILE_FLAG=" --profile ${ADMIN_CONN}"
fi

cat <<EOF

==> [${ADMIN_SECTION}] seeded in ${CONNECTIONS_TOML}.
    account          = ${ACCOUNT}
    user             = ${ADMIN_USER}
    role             = ${ROLE}
    warehouse        = ${WAREHOUSE}   (account-default; promote to ARTWORK_WH later)
    authenticator    = SNOWFLAKE_JWT
    private_key_path = ${PRIVATE_KEY}
    (default_connection_name lives in ${CONFIG_TOML})

Next: register the public key and verify JWT auth:
    ${SCRIPT_DIR}/setup.sh${PROFILE_FLAG} --phase admin

Or run the all-in-one activation (registers key + applies infra + loader + transformer):
    ${SCRIPT_DIR%/snowflake_cli}/activate_mac.sh${PROFILE_FLAG} --project-dir ~/dev/artwork-db
EOF
