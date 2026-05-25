#!/usr/bin/env bash
# ============================================================
# scripts/snowflake_cli/_lib.sh -- Shared helpers for the Snowflake CLI
# setup scripts.
#
# Resolution-order helpers for the values that scripts 04 and 05 need to
# bootstrap and verify the admin connection. The goal is to make
# `./setup.sh --phase all` runnable from a fresh shell with ZERO exported
# environment variables:
#
#   1. An env var set in the calling shell (CI override).
#   2. A value parsed from ~/.snowflake/config.toml.
#   3. (Admin password only) an interactive `read -rs` prompt.
#
# Account / admin user / warehouse are NOT secrets and already live in
# config.toml, so they are parsed from there when no env var is set. The
# admin password is needed 1-3 times per year (bootstrap + key rotations)
# and is intentionally NEVER stored at rest -- when not provided as an env
# var, the operator is prompted and the value lives in process memory only
# for the duration of the snow sql call.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
#   ACCOUNT="$(resolve_admin_account)"
#   USER_NAME="$(resolve_admin_user)"
#   WAREHOUSE="$(resolve_admin_warehouse)"
#   resolve_admin_password_interactive   # exports SNOWFLAKE_PASSWORD
#
# This file is intentionally sourced (not executed) and therefore does NOT
# set `set -euo pipefail`; the calling scripts already do. It does, however,
# rely on `set -u`-safe variable access via `${VAR:-}` defaults so it is
# safe to source under a strict caller.
# ============================================================

SNOW_LIB_CONFIG_TOML="${SNOW_LIB_CONFIG_TOML:-${HOME}/.snowflake/config.toml}"

# Default warehouse used when neither an env var nor config.toml provides one.
SNOW_LIB_DEFAULT_WAREHOUSE="${SNOW_LIB_DEFAULT_WAREHOUSE:-ARTWORK_WH}"

# parse_toml_value <section> <key> <file>
#
# Extract the value for `key = "value"` inside the literal `[<section>]`
# block of a TOML file. Strips surrounding double quotes. Returns an empty
# string when the section, key, or file are missing.
#
# Section names like `connections.admin` are matched literally as
# `[connections.admin]`; no dotted-table walking is attempted. The project's
# config.toml uses simple top-level `[connections.NAME]` blocks with
# double-quoted string values, which is exactly what this helper supports.
parse_toml_value() {
    local section="$1"
    local key="$2"
    local file="$3"

    [[ -f "${file}" ]] || { printf ''; return 0; }

    awk -v section="[${section}]" -v key="${key}" '
        BEGIN { in_section = 0 }
        {
            # Trim leading/trailing whitespace for matching.
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
        }
        # Any [section_header] line toggles whether we are inside the target.
        line ~ /^\[.*\]$/ {
            in_section = (line == section) ? 1 : 0
            next
        }
        in_section && line ~ ("^" key "[[:space:]]*=") {
            sub("^" key "[[:space:]]*=[[:space:]]*", "", line)
            # Strip trailing inline comment (TOML allows `# ...` after value).
            sub(/[[:space:]]*#.*$/, "", line)
            # Strip surrounding double quotes if present.
            if (line ~ /^".*"$/) {
                line = substr(line, 2, length(line) - 2)
            }
            print line
            exit 0
        }
    ' "${file}"
}

# resolve_admin_account
#
# Resolution order:
#   1. $SNOWFLAKE_ACCOUNT
#   2. [connections.admin].account from ~/.snowflake/config.toml
#   3. error (no interactive prompt -- account is not a secret but must be
#      configured before running these scripts)
resolve_admin_account() {
    local value="${SNOWFLAKE_ACCOUNT:-}"
    if [[ -z "${value}" ]]; then
        value="$(parse_toml_value 'connections.admin' 'account' "${SNOW_LIB_CONFIG_TOML}")"
    fi
    if [[ -z "${value}" ]]; then
        echo "error: cannot resolve SNOWFLAKE_ACCOUNT" >&2
        echo "       set SNOWFLAKE_ACCOUNT in the environment OR add" >&2
        echo "       account = \"...\" under [connections.admin] in" >&2
        echo "       ${SNOW_LIB_CONFIG_TOML}" >&2
        return 78
    fi
    printf '%s' "${value}"
}

# resolve_admin_user
#
# Resolution order:
#   1. $SNOWFLAKE_ADMIN_USER
#   2. [connections.admin].user from ~/.snowflake/config.toml
#   3. error
resolve_admin_user() {
    local value="${SNOWFLAKE_ADMIN_USER:-}"
    if [[ -z "${value}" ]]; then
        value="$(parse_toml_value 'connections.admin' 'user' "${SNOW_LIB_CONFIG_TOML}")"
    fi
    if [[ -z "${value}" ]]; then
        echo "error: cannot resolve SNOWFLAKE_ADMIN_USER" >&2
        echo "       set SNOWFLAKE_ADMIN_USER in the environment OR add" >&2
        echo "       user = \"...\" under [connections.admin] in" >&2
        echo "       ${SNOW_LIB_CONFIG_TOML}" >&2
        return 78
    fi
    printf '%s' "${value}"
}

# resolve_admin_warehouse
#
# Resolution order:
#   1. $SNOWFLAKE_WAREHOUSE
#   2. [connections.admin].warehouse from ~/.snowflake/config.toml
#   3. fall back to $SNOW_LIB_DEFAULT_WAREHOUSE (ARTWORK_WH)
resolve_admin_warehouse() {
    local value="${SNOWFLAKE_WAREHOUSE:-}"
    if [[ -z "${value}" ]]; then
        value="$(parse_toml_value 'connections.admin' 'warehouse' "${SNOW_LIB_CONFIG_TOML}")"
    fi
    if [[ -z "${value}" ]]; then
        value="${SNOW_LIB_DEFAULT_WAREHOUSE}"
    fi
    printf '%s' "${value}"
}

# resolve_admin_password_interactive
#
# If SNOWFLAKE_PASSWORD is already set in the environment (CI override),
# leave it untouched. Otherwise, prompt interactively with `read -rs` and
# export the resulting value as SNOWFLAKE_PASSWORD for downstream `snow sql`
# calls. The value is never written to disk and never echoed to the screen.
#
# Expects resolve_admin_user / resolve_admin_account to succeed first so the
# prompt can identify the target identity.
resolve_admin_password_interactive() {
    if [[ -n "${SNOWFLAKE_PASSWORD:-}" ]]; then
        return 0
    fi
    local user account
    user="$(resolve_admin_user)" || return $?
    account="$(resolve_admin_account)" || return $?
    local prompt="Snowflake admin password for ${user}@${account}: "
    # `read -rs` reads silently; echo a newline after so subsequent output
    # is not glued to the prompt line.
    read -rs -p "${prompt}" SNOWFLAKE_PASSWORD
    echo
    export SNOWFLAKE_PASSWORD
    if [[ -z "${SNOWFLAKE_PASSWORD}" ]]; then
        echo "error: empty password entered" >&2
        return 78
    fi
}

# verify_admin_jwt_full <admin_user> <register_sql_file>
#
# Three-step verification of the JWT-based 'admin' connection. Used by both
# 05_verify_admin_jwt.sh and 08_promote_admin_warehouse.sh so they exercise
# exactly the same checks (DRY) regardless of which warehouse
# [connections.admin].warehouse currently points at.
#
# Steps:
#   1. Re-apply register_admin_public_key.sql via 'snow sql -c admin
#      --filename ...' -- proves JWT auth end-to-end. ALTER USER ... SET
#      RSA_PUBLIC_KEY with the same value is a no-op; with a new value it
#      rotates the credential.
#   2. 'snow connection test -c admin' -- full session handshake using
#      the warehouse currently configured under [connections.admin].
#   3. 'snow sql -c admin -q "SELECT CURRENT_USER(), CURRENT_ROLE();"' --
#      real query round-trip that exercises the warehouse.
#
# Requires [connections.admin].warehouse to point at an EXISTING warehouse.
# Initially that is an account-default such as COMPUTE_WH; after
# 08_promote_admin_warehouse.sh runs, it is ARTWORK_WH.
verify_admin_jwt_full() {
    local admin_user="$1"
    local sql_file="$2"

    [[ -n "${admin_user}" ]] || { echo "error: verify_admin_jwt_full requires <admin_user>" >&2; return 64; }
    [[ -f "${sql_file}" ]]  || { echo "error: SQL file not found: ${sql_file}" >&2; return 66; }

    local pubkey_file="${ADMIN_PUBLIC_KEY_FILE:-${HOME}/.snowflake/keys/admin_rsa_key.pub}"
    [[ -f "${pubkey_file}" ]] || { echo "error: public key not found: ${pubkey_file}" >&2; return 66; }

    # Strip PEM header/footer/newlines so the key body fits in a single
    # --variable value.
    local pubkey
    pubkey="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${pubkey_file}")"

    echo "==> JWT auth check 1/3: re-apply ${sql_file##*/} via -c admin"
    snow sql -c admin \
        --filename "${sql_file}" \
        --variable "admin_user=${admin_user}" \
        --variable "rsa_public_key=${pubkey}" \
        --enhanced-exit-codes

    echo
    echo "==> JWT auth check 2/3: snow connection test -c admin (full handshake)"
    snow connection test -c admin

    echo
    echo "==> JWT auth check 3/3: SELECT CURRENT_USER(), CURRENT_ROLE() round-trip"
    snow sql -c admin -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"
}

# replace_toml_value_in_section <section> <key> <new_value> <file>
#
# Rewrite ONLY <key> = "<new_value>" inside the literal [<section>] block of
# a TOML file. Touches no other section ([connections.loader], [cli.logs],
# etc. are left untouched). Creates a timestamped backup at
# <file>.bak.YYYYMMDDHHMMSS, writes the new contents to a temp file in the
# same directory, then atomically mv's it over the original and re-chmods
# to 600.
#
# Implementation: an awk script tracks whether the current line is inside
# the target section. When inside, the first key-line that matches the
# requested key is replaced with the new value; all other lines are emitted
# unchanged. The section's existing surrounding lines (comments, blank
# lines) are preserved. If the key is not found inside the target section,
# the helper aborts with exit 3 and the original file is left in place.
replace_toml_value_in_section() {
    local section="$1"
    local key="$2"
    local new_value="$3"
    local file="$4"

    [[ -f "${file}" ]] || { echo "error: TOML file not found: ${file}" >&2; return 66; }

    local timestamp backup tmp dir
    timestamp="$(date -u +%Y%m%d%H%M%S)"
    backup="${file}.bak.${timestamp}"
    dir="$(dirname "${file}")"
    tmp="$(mktemp "${dir}/.$(basename "${file}").XXXXXX")"

    cp -p "${file}" "${backup}"
    echo "==> backed up ${file} -> ${backup}"

    awk -v section="[${section}]" -v key="${key}" -v new_value="${new_value}" '
        BEGIN { in_section = 0; replaced = 0 }
        {
            line = $0
            trimmed = line
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)

            if (trimmed ~ /^\[.*\]$/) {
                in_section = (trimmed == section) ? 1 : 0
                print line
                next
            }

            if (in_section && !replaced && trimmed ~ ("^" key "[[:space:]]*=")) {
                printf "%s = \"%s\"\n", key, new_value
                replaced = 1
                next
            }

            print line
        }
        END {
            if (!replaced) {
                exit 3
            }
        }
    ' "${file}" > "${tmp}"
    local awk_rc=$?

    if [[ ${awk_rc} -ne 0 ]]; then
        rm -f "${tmp}"
        echo "error: key '${key}' not found in section [${section}] of ${file}" >&2
        return 3
    fi

    mv "${tmp}" "${file}"
    chmod 600 "${file}"
    echo "==> rewrote [${section}].${key} = \"${new_value}\" in ${file} (chmod 600)"
}
