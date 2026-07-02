#!/usr/bin/env bash
# =============================================================================
# ddl_orchestrator.sh — DEPRECATED - Use scripts/orchestrate_modern.sh instead
# =============================================================================
#
# DEPRECATION NOTICE: This component contained domain configuration logic that
# violated separation of concerns. It has been superseded by scripts/orchestrate_modern.sh
# which provides pure connection framework without domain assumptions.
#
# NEW ARCHITECTURE:
# - Framework provides ONLY connection utilities and file orchestration
# - User provides DDL directory, manifest file, and connection name explicitly
# - No domain configuration, no template processing, no defaults
# - Clean separation: framework = plumbing, user = domain logic
#
# MIGRATION:
# Old: execute_ddl_phase --config domain.yml --phase infra --connection admin
# New: scripts/orchestrate_modern.sh --ddl-dir DIR --manifest FILE --phase infra --connection NAME
#
# =============================================================================

set -euo pipefail

# DEPRECATED FUNCTIONS - All functionality moved to scripts/orchestrate_modern.sh

execute_ddl_phase() {
    echo "ERROR: execute_ddl_phase is deprecated. Use scripts/orchestrate_modern.sh instead." >&2
    echo "Migration: scripts/orchestrate_modern.sh --ddl-dir DIR --manifest FILE --phase PHASE --connection CONN" >&2
    return 1
}

rollback_ddl_script() {
    echo "ERROR: rollback_ddl_script is deprecated. Use scripts/orchestrate_modern.sh instead." >&2
    echo "Migration: scripts/orchestrate_modern.sh --ddl-dir DIR --manifest FILE --file SCRIPT --connection CONN" >&2
    return 1
}

validate_ddl_environment() {
    echo "ERROR: validate_ddl_environment is deprecated. Use scripts/orchestrate_modern.sh instead." >&2
    return 1
}

show_ddl_orchestrator_help() {
    cat <<EOF
ddl_orchestrator.sh — DEPRECATED

This component has been deprecated due to architectural violations.
Use scripts/orchestrate_modern.sh for pure connection framework.

MIGRATION:
  Old: execute_ddl_phase --config domain.yml --phase infra
  New: scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase infra --connection CONN

RATIONALE:
  The old approach violated separation of concerns by embedding domain 
  configuration and template processing in the framework. The new approach
  provides pure connection utilities with user-specified parameters only.

EOF
}

# Handle --help flag when script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--help" ]]; then
    show_ddl_orchestrator_help
    exit 0
fi