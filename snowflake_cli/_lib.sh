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

# ------------------------------------------------------------
# Multi-account connection-name model.
#
# Every helper that touches a connection resolves its config.toml section and
# key-file paths from these two names rather than the literals "admin"/"loader".
# Defaults preserve the original single-account behavior byte-for-byte (and the
# original admin_rsa_key.p8 / loader_rsa_key.p8 paths). setup.sh exports
# ADMIN_CONN / LOADER_CONN (from --profile / --admin-conn / --loader-conn) so
# all child scripts inherit a consistent target account.
# ------------------------------------------------------------
SNOW_LIB_ADMIN_CONN="${ADMIN_CONN:-admin}"
SNOW_LIB_LOADER_CONN="${LOADER_CONN:-loader}"
SNOW_LIB_KEY_DIR="${SNOW_LIB_KEY_DIR:-${HOME}/.snowflake/keys}"

# validate_conn_name <name>
#
# A connection name is used both as a TOML bare section key
# ([connections.NAME]) and as a `snow -c NAME` argument, so restrict it to a
# safe charset. Rejects anything else with a clear error (exit 64).
validate_conn_name() {
    local name="$1"
    if [[ ! "${name}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "error: invalid connection name '${name}'" >&2
        echo "       allowed characters: letters, digits, underscore, hyphen" >&2
        return 64
    fi
}

# admin_key_path [p8|pub] / loader_key_path [p8|pub]
#
# Derive the key-file path for the active admin/loader connection. The default
# names (admin/loader) yield the historical admin_rsa_key.* / loader_rsa_key.*
# paths; any other connection name is namespaced automatically, so two accounts
# never share a key file.
admin_key_path() {
    printf '%s/%s_rsa_key.%s' "${SNOW_LIB_KEY_DIR}" "${SNOW_LIB_ADMIN_CONN}" "${1:-p8}"
}
loader_key_path() {
    printf '%s/%s_rsa_key.%s' "${SNOW_LIB_KEY_DIR}" "${SNOW_LIB_LOADER_CONN}" "${1:-p8}"
}

# How many timestamped config.toml.bak.* files to retain after a mutating
# helper (replace_*/upsert_*) runs. Older backups beyond this count are pruned
# so repeated `--phase promote`/`--phase loader` runs do not accumulate
# unbounded copies of the config next to the live file.
SNOW_LIB_BACKUP_KEEP="${SNOW_LIB_BACKUP_KEEP:-5}"

# prune_backups <file> [keep]
#
# Delete all but the newest <keep> (default SNOW_LIB_BACKUP_KEEP) timestamped
# "<file>.bak.YYYYMMDDHHMMSS" backups. The timestamp suffix sorts lexically in
# chronological order, so `sort -r` yields newest-first. A no-op when the glob
# matches nothing or the count is already at/below <keep>.
prune_backups() {
    local file="$1"
    local keep="${2:-${SNOW_LIB_BACKUP_KEEP}}"
    local dir base
    dir="$(dirname "${file}")"
    base="$(basename "${file}")"

    local backups=()
    local f
    while IFS= read -r f; do
        [[ -n "${f}" ]] && backups+=("${f}")
    done < <(ls -1 "${dir}/${base}".bak.* 2>/dev/null | sort -r)

    local count=${#backups[@]}
    if (( count > keep )); then
        local i
        for (( i = keep; i < count; i++ )); do
            rm -f "${backups[$i]}"
            echo "==> pruned old backup ${backups[$i]}"
        done
    fi
}

# warn_duplicate_section <section> <file>
#
# Emit a stderr warning if the literal "[<section>]" header appears more than
# once in <file>. The parse/replace/upsert helpers all operate on the FIRST
# matching section only; a duplicate header is a silent-wrong-edit foot-gun
# (e.g. a hand-edit that pasted a second [connections.admin] block), so flag it
# rather than edit the wrong copy quietly. Never fatal.
warn_duplicate_section() {
    local section="$1"
    local file="$2"
    [[ -f "${file}" ]] || return 0
    local n
    n="$(awk -v s="[${section}]" '
        { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l) }
        l == s { c++ }
        END { print c + 0 }
    ' "${file}")"
    if (( n > 1 )); then
        echo "WARN: section [${section}] appears ${n} times in ${file};" >&2
        echo "      only the FIRST occurrence will be edited. Remove duplicates." >&2
    fi
}

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

# parse_toml_toplevel_key <key> <file>
#
# Like parse_toml_value, but for a TOP-LEVEL (no section) key such as
# `default_connection_name`. Scans only the lines BEFORE the first `[section]`
# header -- in TOML, a bare `key = value` after a table header belongs to that
# table, so true top-level keys must precede every section. Returns the empty
# string when the key is absent.
parse_toml_toplevel_key() {
    local key="$1"
    local file="$2"

    [[ -f "${file}" ]] || { printf ''; return 0; }

    awk -v key="${key}" '
        { line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line) }
        line ~ /^\[.*\]$/ { exit 0 }
        line ~ ("^" key "[[:space:]]*=") {
            sub("^" key "[[:space:]]*=[[:space:]]*", "", line)
            sub(/[[:space:]]*#.*$/, "", line)
            if (line ~ /^".*"$/) { line = substr(line, 2, length(line) - 2) }
            print line
            exit 0
        }
    ' "${file}"
}

# upsert_toml_toplevel_key <key> <new_value> <file>
#
# Insert-or-replace a TOP-LEVEL `<key> = "<new_value>"` line, always positioned
# BEFORE the first `[section]` header (so it cannot accidentally fall inside a
# table). Same durability contract as the in-section helpers: timestamped
# backup, atomic temp-file swap, chmod 600, backup pruning. Used to manage
# `default_connection_name`.
upsert_toml_toplevel_key() {
    local key="$1"
    local new_value="$2"
    local file="$3"

    [[ -f "${file}" ]] || { echo "error: TOML file not found: ${file}" >&2; return 66; }

    local timestamp backup tmp dir
    timestamp="$(date -u +%Y%m%d%H%M%S)"
    backup="${file}.bak.${timestamp}"
    dir="$(dirname "${file}")"
    tmp="$(mktemp "${dir}/.$(basename "${file}").XXXXXX")"

    cp -p "${file}" "${backup}"
    echo "==> backed up ${file} -> ${backup}"

    awk -v key="${key}" -v new_value="${new_value}" '
        function emit() { printf "%s = \"%s\"\n", key, new_value }
        BEGIN { replaced = 0; before_first_section = 1 }
        {
            line = $0
            trimmed = line
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)

            if (trimmed ~ /^\[.*\]$/) {
                # About to enter the first section: write the key first if we
                # have not already replaced an existing top-level occurrence.
                if (before_first_section && !replaced) { emit(); replaced = 1 }
                before_first_section = 0
                print line
                next
            }

            if (before_first_section && !replaced && trimmed ~ ("^" key "[[:space:]]*=")) {
                emit()
                replaced = 1
                next
            }

            print line
        }
        END {
            # No section header in the whole file and key never seen: append it.
            if (!replaced) { emit() }
        }
    ' "${file}" > "${tmp}"
    local awk_rc=$?

    if [[ ${awk_rc} -ne 0 ]]; then
        rm -f "${tmp}"
        echo "error: failed to upsert top-level ${key} in ${file}" >&2
        return 1
    fi

    mv "${tmp}" "${file}"
    chmod 600 "${file}"
    echo "==> upserted top-level ${key} = \"${new_value}\" in ${file} (chmod 600)"
    prune_backups "${file}"
}

# list_connections [file]
#
# Print every [connections.NAME] defined in config.toml, marking the one named
# by default_connection_name. Read-only. Falls back gracefully on an empty or
# missing file. (Intentionally parses the file rather than shelling out to
# `snow connection list`, so it works offline and is deterministic in tests.)
list_connections() {
    local file="${1:-${SNOW_LIB_CONFIG_TOML}}"
    local default
    default="$(parse_toml_toplevel_key 'default_connection_name' "${file}")"

    echo "Connections in ${file}:"
    if [[ ! -f "${file}" ]]; then
        echo "  (file not found)"
        return 0
    fi

    local found=0 name
    while IFS= read -r name; do
        found=1
        if [[ "${name}" == "${default}" ]]; then
            echo "  * ${name}   (default)"
        else
            echo "    ${name}"
        fi
    done < <(awk '
        { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l) }
        l ~ /^\[connections\..+\]$/ {
            sub(/^\[connections\./, "", l); sub(/\]$/, "", l); print l
        }
    ' "${file}")

    if [[ "${found}" -eq 0 ]]; then
        echo "  (none defined)"
    fi
}

# set_default_connection <name> [file]
#
# Point default_connection_name at <name>. Validates the name, warns (but does
# not fail) if no [connections.<name>] block exists yet, then upserts the
# top-level key via the durable helper (timestamped backup, chmod 600).
set_default_connection() {
    local name="$1"
    local file="${2:-${SNOW_LIB_CONFIG_TOML}}"

    validate_conn_name "${name}" || return $?
    [[ -f "${file}" ]] || { echo "error: config.toml not found: ${file}" >&2; return 66; }

    if [[ -z "$(parse_toml_value "connections.${name}" 'account' "${file}")" ]]; then
        echo "WARN: [connections.${name}] has no 'account' yet in ${file};" >&2
        echo "      setting it as default anyway -- seed it with --phase init-profile." >&2
    fi

    upsert_toml_toplevel_key 'default_connection_name' "${name}" "${file}"
    echo "==> default_connection_name is now \"${name}\""
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
        value="$(parse_toml_value "connections.${SNOW_LIB_ADMIN_CONN}" 'account' "${SNOW_LIB_CONFIG_TOML}")"
    fi
    if [[ -z "${value}" ]]; then
        echo "error: cannot resolve SNOWFLAKE_ACCOUNT" >&2
        echo "       set SNOWFLAKE_ACCOUNT in the environment OR add" >&2
        echo "       account = \"...\" under [connections.${SNOW_LIB_ADMIN_CONN}] in" >&2
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
        value="$(parse_toml_value "connections.${SNOW_LIB_ADMIN_CONN}" 'user' "${SNOW_LIB_CONFIG_TOML}")"
    fi
    if [[ -z "${value}" ]]; then
        echo "error: cannot resolve SNOWFLAKE_ADMIN_USER" >&2
        echo "       set SNOWFLAKE_ADMIN_USER in the environment OR add" >&2
        echo "       user = \"...\" under [connections.${SNOW_LIB_ADMIN_CONN}] in" >&2
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
        value="$(parse_toml_value "connections.${SNOW_LIB_ADMIN_CONN}" 'warehouse' "${SNOW_LIB_CONFIG_TOML}")"
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

    local pubkey_file="${ADMIN_PUBLIC_KEY_FILE:-$(admin_key_path pub)}"
    [[ -f "${pubkey_file}" ]] || { echo "error: public key not found: ${pubkey_file}" >&2; return 66; }

    # Strip PEM header/footer/newlines so the key body fits in a single
    # --variable value.
    local pubkey
    pubkey="$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' "${pubkey_file}")"

    echo "==> JWT auth check 1/3: re-apply ${sql_file##*/} via -c ${SNOW_LIB_ADMIN_CONN}"
    snow sql -c "${SNOW_LIB_ADMIN_CONN}" \
        --filename "${sql_file}" \
        --variable "admin_user=${admin_user}" \
        --variable "rsa_public_key=${pubkey}" \
        --enhanced-exit-codes

    echo
    echo "==> JWT auth check 2/3: snow connection test -c ${SNOW_LIB_ADMIN_CONN} (full handshake)"
    snow connection test -c "${SNOW_LIB_ADMIN_CONN}"

    echo
    echo "==> JWT auth check 3/3: SELECT CURRENT_USER(), CURRENT_ROLE() round-trip"
    snow sql -c "${SNOW_LIB_ADMIN_CONN}" -q "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r;"
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

    warn_duplicate_section "${section}" "${file}"

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
    prune_backups "${file}"
}

# upsert_toml_value_in_section <section> <key> <new_value> <file>
#
# Like replace_toml_value_in_section, but INSERT-IF-MISSING instead of
# abort-if-missing. Guarantees that after the call, [<section>] contains
# exactly one `<key> = "<new_value>"` line:
#   - key present in section            -> value replaced in place
#   - section present, key absent        -> key line inserted into the section
#   - section absent                     -> a new [<section>] block is appended
#                                           with the key line
#
# This is the right tool when converting [connections.loader] from password
# auth to key-pair auth, where `private_key_file` / `authenticator` lines may
# not yet exist. (replace_toml_value_in_section is retained for callers like
# 08_promote_admin_warehouse.sh that WANT the abort-if-missing safety, e.g.
# rewriting an existing `warehouse` value.)
#
# Same durability contract as replace_*: timestamped backup, atomic temp-file
# swap, chmod 600. All other sections are left byte-for-byte untouched.
upsert_toml_value_in_section() {
    local section="$1"
    local key="$2"
    local new_value="$3"
    local file="$4"

    [[ -f "${file}" ]] || { echo "error: TOML file not found: ${file}" >&2; return 66; }

    warn_duplicate_section "${section}" "${file}"

    local timestamp backup tmp dir
    timestamp="$(date -u +%Y%m%d%H%M%S)"
    backup="${file}.bak.${timestamp}"
    dir="$(dirname "${file}")"
    tmp="$(mktemp "${dir}/.$(basename "${file}").XXXXXX")"

    cp -p "${file}" "${backup}"
    echo "==> backed up ${file} -> ${backup}"

    awk -v section="[${section}]" -v key="${key}" -v new_value="${new_value}" '
        function emit_key() { printf "%s = \"%s\"\n", key, new_value }
        BEGIN { in_section = 0; replaced = 0; seen_section = 0 }
        {
            line = $0
            trimmed = line
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)

            if (trimmed ~ /^\[.*\]$/) {
                # Leaving the target section without having written the key:
                # insert it now, before the next section header.
                if (in_section && !replaced) { emit_key(); replaced = 1 }
                in_section = (trimmed == section) ? 1 : 0
                if (in_section) { seen_section = 1 }
                print line
                next
            }

            if (in_section && !replaced && trimmed ~ ("^" key "[[:space:]]*=")) {
                emit_key()
                replaced = 1
                next
            }

            print line
        }
        END {
            # EOF reached while still inside the target section, key not written.
            if (in_section && !replaced) { emit_key(); replaced = 1 }
            # Section never appeared at all: append a fresh block.
            if (!seen_section) {
                print ""
                print section
                emit_key()
            }
        }
    ' "${file}" > "${tmp}"
    local awk_rc=$?

    if [[ ${awk_rc} -ne 0 ]]; then
        rm -f "${tmp}"
        echo "error: failed to upsert [${section}].${key} in ${file}" >&2
        return 1
    fi

    mv "${tmp}" "${file}"
    chmod 600 "${file}"
    echo "==> upserted [${section}].${key} = \"${new_value}\" in ${file} (chmod 600)"
    prune_backups "${file}"
}
