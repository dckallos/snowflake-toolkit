#!/usr/bin/env bash
# ============================================================
# scripts/git_mark_executable.sh -- One-time-per-clone helper that stores
# the executable bit (+x) for every script in the bootstrap.py call
# graph directly inside Git's index, so future clones receive +x for
# free.
#
# Background:
#   Git tracks file mode in tree objects as either 100644 (regular) or
#   100755 (executable). `chmod +x` on disk only changes the working
#   tree; without `git update-index --chmod=+x <path>` (and a follow-up
#   commit), the next `git checkout` on another machine restores the
#   file as 100644.
#
# Usage:
#   bash scripts/git_mark_executable.sh
#   git diff --cached
#   git add -u
#   git commit -m "chore: mark bootstrap scripts executable in git index"
#   git push
#
# After this commit lands on origin, every new clone receives mode 0755
# on all listed paths without any further action. `make chmod` /
# bootstrap_chmod.sh then becomes a defensive safety net for files that
# arrived via copy-paste from the Notion source pages.
#
# Idempotency:
#   `git update-index --chmod=+x` on an already-executable tracked file
#   is a no-op (it stages no change). Re-running is harmless. Untracked
#   paths and paths missing on disk are skipped with a note rather than
#   erroring out, so this script can be run safely on a partial checkout.
#
# Refs:
#   https://git-scm.com/docs/git-update-index
# ============================================================
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Same allow-list as scripts/bootstrap_chmod.sh. Keep the two in sync.
ALLOW_LIST=(
    scripts/apply_sql.sh
    scripts/bootstrap_chmod.sh
    scripts/git_mark_executable.sh
    scripts/rollback_sql.sh
    scripts/run_pipeline.sh
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

declare -a UPDATED=()
declare -a SKIPPED=()

for path in "${ALLOW_LIST[@]}"; do
    if [[ ! -f "${path}" ]]; then
        SKIPPED+=("${path} (not on disk)")
        continue
    fi
    if ! git ls-files --error-unmatch "${path}" >/dev/null 2>&1; then
        SKIPPED+=("${path} (not tracked by git)")
        continue
    fi
    git update-index --chmod=+x "${path}"
    UPDATED+=("${path}")
done

echo
echo "==> staged +x for ${#UPDATED[@]} path(s):"
for p in "${UPDATED[@]}"; do
    echo "    ${p}"
done

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo
    echo "==> skipped ${#SKIPPED[@]} path(s):"
    for p in "${SKIPPED[@]}"; do
        echo "    ${p}"
    done
fi

cat <<'EOF'

Next steps:
    git diff --cached
    git add -u
    git commit -m "chore: mark bootstrap scripts executable in git index"
    git push

After this commit lands on origin, every new clone receives mode 0755
on all listed paths automatically (the executable bit is stored in
git's tree object). bootstrap_chmod.sh / `make chmod` then becomes a
defensive safety net for files that arrived via copy-paste from the
Notion source pages.
EOF
