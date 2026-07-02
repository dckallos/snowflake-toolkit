#!/usr/bin/env bash
# ============================================================
# bootstrap_chmod.sh -- Canonical chmod policy for every .sh file
# in the IaC call graph.
#
# Purpose:
# Guarantee that every shell script the IaC layer invokes carries
# mode 0755 on the operator's filesystem -- regardless of whether the
# file arrived from a fresh git clone or a copy-paste (mode 0644).
#
# Allow-lists:
# Reads TWO allow-lists (both optional individually, but at least one
# must exist):
#   1. ${TOOLKIT_DIR}/executable_files.txt  -- toolkit's own scripts
#   2. scripts/executable_files.txt         -- project-local scripts
#
# Each file contains one repo-relative path per line; blank lines and
# #-comments are ignored. Paths in the toolkit list are resolved
# relative to TOOLKIT_DIR; paths in the project list are resolved
# relative to the project root (CWD).
#
# Bootstrap workaround:
# The Makefile invokes this as `bash $(TOOLKIT_DIR)/bootstrap_chmod.sh`
# so the POSIX shell loads it as a plain text file -- no executable bit
# required on the file itself.
#
# Idempotency:
# chmod 755 is naturally idempotent. A second invocation prints
# identical before/after columns for every entry and returns 0.
# ============================================================
set -euo pipefail

TOOLKIT_DIR="${TOOLKIT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

toolkit_list="${TOOLKIT_DIR}/executable_files.txt"
project_list="scripts/executable_files.txt"

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
found_any=false

# ----------------------------------------------------------------------
# process_list <list_file> <base_dir>
# Reads an allow-list and chmods each entry relative to base_dir.
# ----------------------------------------------------------------------
process_list() {
  local list_file="$1"
  local base_dir="$2"
  [[ -f "$list_file" ]] || return 0
  found_any=true

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "${line}" ]] && continue

    local target="${base_dir}/${line}"
    if [[ ! -f "${target}" ]]; then
      MISSING+=("${target}")
      continue
    fi

    local before after
    before="$(mode_of "${target}")"
    chmod 755 "${target}"
    after="$(mode_of "${target}")"
    SUMMARY_ROWS+=("${target}|${before}|${after}")
  done < "$list_file"
}

# Process toolkit scripts (resolved relative to TOOLKIT_DIR)
process_list "$toolkit_list" "$TOOLKIT_DIR"

# Process project-local scripts (resolved relative to CWD / project root)
process_list "$project_list" "."

# ----------------------------------------------------------------------
# Guard: at least one allow-list must exist.
# ----------------------------------------------------------------------
if [[ "$found_any" == false ]]; then
  echo "error: neither ${toolkit_list} nor ${project_list} found (required allow-list)" >&2
  exit 66
fi

# ----------------------------------------------------------------------
# Summary table.
# ----------------------------------------------------------------------
if [[ ${#SUMMARY_ROWS[@]} -gt 0 ]]; then
  printf '\n%-60s | %-6s | %-5s\n' "path" "before" "after"
  printf '%s\n' "-----------------------------------------------------------------------------"
  for row in "${SUMMARY_ROWS[@]}"; do
    IFS='|' read -r p b a <<<"${row}"
    printf '%-60s | %-6s | %-5s\n' "${p}" "${b}" "${a}"
  done
fi

# ----------------------------------------------------------------------
# Verify every chmoded path is executable.
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
# Missing-path handling: soft warning, not hard failure.
# After repo separation some toolkit entries may not exist in every
# consuming project -- that's expected. Warn but don't block.
# ----------------------------------------------------------------------
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "warning: ${#MISSING[@]} path(s) in allow-list not found on disk (skipped):" >&2
  for path in "${MISSING[@]}"; do
    echo "  - ${path}" >&2
  done
fi

if [[ ${fail} -ne 0 ]]; then
  exit 1
fi

echo
echo "==> bootstrap_chmod.sh complete: ${#SUMMARY_ROWS[@]} script(s) at mode 755"
