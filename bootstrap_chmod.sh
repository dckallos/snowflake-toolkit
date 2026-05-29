#!/usr/bin/env bash
# ============================================================
# scripts/bootstrap_chmod.sh -- Canonical chmod policy for every .sh file
# in the bootstrap.py call graph.
#
# Purpose:
#   Guarantee that every shell script the IaC layer invokes
#   (apply_sql.sh, rollback_sql.sh, run_pipeline.sh, every script under
#   scripts/snowflake_cli/, and this file itself) carries mode 0755 on
#   the operator's filesystem -- regardless of whether the file arrived
#   from a fresh git clone (which preserves the executable bit if it was
#   committed via `git update-index --chmod=+x`) or from a copy-paste of
#   the Notion source pages (which arrive as mode 0644 by default).
#
# Why this exists:
#   Before this script existed, `make iac` would fail at the very first
#   `subprocess.run(["scripts/apply_sql.sh", ...])` call inside
#   scripts/bootstrap.py with:
#
#     PermissionError: [Errno 13] Permission denied:
#       '/Users/<...>/scripts/apply_sql.sh'
#
#   because apply_sql.sh shipped as mode 0644. The existing
#   scripts/snowflake_cli/setup.sh::chmod_children() helper only chmoded
#   scripts/snowflake_cli/*.sh and therefore missed apply_sql.sh,
#   rollback_sql.sh, and any other .sh one directory up. This script is
#   the single source of truth: every .sh path the IaC contract depends
#   on is enumerated in ALLOW_LIST below.
#
# Bootstrap workaround:
#   This script is itself part of the call graph, so it must be runnable
#   even when its own mode is 0644 on a fresh clone. The Makefile invokes
#   it as `bash scripts/bootstrap_chmod.sh` (not `./scripts/...`) so the
#   POSIX shell loads it as a plain text file -- no executable bit
#   required on the file itself. The script then chmods itself (along
#   with everything else in ALLOW_LIST) so subsequent direct invocations
#   (`./scripts/...`) also work.
#
# Idempotency:
#   chmod 755 is naturally idempotent. A second invocation prints
#   identical before/after columns for every entry and returns 0.
#
# Acceptance:
#   - Every path in ALLOW_LIST exists and is mode 0755 (verified via
#     `test -x` at the end).
#   - Missing paths fail fast with a clear error.
#   - Output includes a summary table (path | before | after).
#
# Refs:
#   https://git-scm.com/docs/git-update-index  (run
#   scripts/git_mark_executable.sh once per repo to store +x in the git
#   tree itself; thereafter `make chmod` is a defensive safety net for
#   files copy-pasted from the Notion source pages.)
# ============================================================
set -euo pipefail

# Resolve to repo root so all paths are stable regardless of CWD.
cd "$(git rev-parse --show-toplevel)"

# ----------------------------------------------------------------------
# ALLOW_LIST -- every .sh in the bootstrap.py call graph.
# Keep alphabetized within each subtree for easy diffing.
# ----------------------------------------------------------------------
ALLOW_LIST=(
    scripts/apply_sql.sh
    scripts/bootstrap_chmod.sh
    scripts/git_mark_executable.sh
    scripts/rollback_sql.sh
    scripts/snowflake_cli/_lib.sh
    scripts/snowflake_cli/00_install_snowflake_cli.sh
    scripts/snowflake_cli/01_init_snowflake_home.sh
    scripts/snowflake_cli/02_generate_admin_keypair.sh
    scripts/snowflake_cli/03_lock_config_permissions.sh
    scripts/snowflake_cli/04_register_admin_public_key.sh
    scripts/snowflake_cli/05_verify_admin_jwt.sh
    scripts/snowflake_cli/06_rotate_loader_password.sh
    scripts/snowflake_cli/07_test_loader_connection.sh
    scripts/snowflake_cli/08_promote_admin_warehouse.sh
    scripts/snowflake_cli/setup.sh
)

# Portable octal mode read (GNU coreutils: stat -c %a; BSD/macOS: stat -f %Lp).
mode_of() {
    if stat -c %a "$1" >/dev/null 2>&1; then
        stat -c %a "$1"
    else
        stat -f %Lp "$1"
    fi
}

declare -a SUMMARY_ROWS=()
declare -a MISSING=()

for path in "${ALLOW_LIST[@]}"; do
    if [[ ! -f "${path}" ]]; then
        MISSING+=("${path}")
        continue
    fi
    before="$(mode_of "${path}")"
    chmod 755 "${path}"
    after="$(mode_of "${path}")"
    SUMMARY_ROWS+=("${path}|${before}|${after}")
done

# ----------------------------------------------------------------------
# Summary table.
# ----------------------------------------------------------------------
printf '\n%-55s | %-6s | %-5s\n' "path" "before" "after"
printf '%s\n' "------------------------------------------------------------------------"
for row in "${SUMMARY_ROWS[@]}"; do
    IFS='|' read -r p b a <<<"${row}"
    printf '%-55s | %-6s | %-5s\n' "${p}" "${b}" "${a}"
done

# ----------------------------------------------------------------------
# Verify every chmoded path is executable. Fail fast on any miss.
# ----------------------------------------------------------------------
fail=0
for row in "${SUMMARY_ROWS[@]}"; do
    IFS='|' read -r p _b _a <<<"${row}"
    if [[ ! -x "${p}" ]]; then
        echo "error: ${p} is not executable after chmod 755" >&2
        fail=1
    fi
done

# ----------------------------------------------------------------------
# Missing-path handling: any entry in ALLOW_LIST missing on disk is a
# hard failure. The ${#MISSING[@]} guard is required because `set -u`
# treats expansion of an EMPTY array via "${MISSING[@]}" as an unbound
# variable on Bash 3.2 (macOS system Bash), which would otherwise abort
# the script on the happy path where every file is present.
# ----------------------------------------------------------------------
if [[ ${#MISSING[@]} -gt 0 ]]; then
    for path in "${MISSING[@]}"; do
        echo "error: ${path} listed in ALLOW_LIST but not found on disk" >&2
        fail=1
    done
fi

if [[ ${fail} -ne 0 ]]; then
    exit 1
fi

echo
echo "==> bootstrap_chmod.sh complete: ${#SUMMARY_ROWS[@]} script(s) at mode 755"
