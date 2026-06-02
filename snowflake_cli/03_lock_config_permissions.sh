#!/usr/bin/env bash
# ============================================================
# 03_lock_config_permissions.sh -- Enforce chmod 600 on the Snowflake CLI
# config file and the admin private key.
#
# The CLI refuses to read config.toml when its mode is looser than
# owner-read/write. This script chmods both files in one place so the rule
# is never forgotten after editing config.toml in another tool.
#
# Idempotent: chmod is naturally idempotent. Missing files are warned and
# skipped (this lets the script run before you have hand-written
# config.toml).
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"
PRIVATE_KEY="$(admin_key_path p8)"

lock() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        chmod 600 "${file}"
        echo "chmod 600 ${file}"
    else
        echo "WARN: ${file} not found; skipping (create it then re-run)"
    fi
}

lock "${CONFIG_TOML}"
lock "${PRIVATE_KEY}"

# Show effective permissions for confirmation.
ls -l "${CONFIG_TOML}" "${PRIVATE_KEY}" 2>/dev/null || true
