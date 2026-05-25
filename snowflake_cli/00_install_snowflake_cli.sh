#!/usr/bin/env bash
# ============================================================
# 00_install_snowflake_cli.sh -- Install the Snowflake CLI via Homebrew.
#
# Idempotent: skips install if 'snow' is already on PATH and reports the
# version. On non-Homebrew systems, prints guidance to install via pipx.
# ============================================================
set -euo pipefail

if command -v snow >/dev/null 2>&1; then
    echo "snow already installed: $(snow --version)"
    exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
    cat <<'EOF' >&2
error: Homebrew (brew) is not installed.
       On macOS: install Homebrew from https://brew.sh, then re-run.
       On Linux/Windows: install via pipx instead:
           pipx install snowflake-cli
EOF
    exit 1
fi

echo "==> brew install snowflake-cli"
brew install snowflake-cli

echo "installed: $(snow --version)"
