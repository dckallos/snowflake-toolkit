#!/usr/bin/env bash
# =============================================================================
# dbt_orchestrator.sh — DEPRECATED - Use direct dbt commands with connections
# =============================================================================
#
# DEPRECATION NOTICE: This component contained domain configuration logic that
# violated separation of concerns. dbt operations are user domain logic, not
# framework concerns. Use direct dbt commands with connection parameters.
#
# CORRECTED APPROACH:
# - Framework provides connection resolution only
# - User manages dbt project, profiles, and operations directly
# - No framework orchestration of user's dbt workflows
# - Clean separation: framework = connection utilities, user = dbt logic
#
# MIGRATION:
# Old: execute_dbt_phase --config domain.yml --phase build --connection transformer
# New: cd artwork_pipeline/ && dbt build --connection transformer
#
# PHILOSOPHY:
# dbt is user domain logic. Framework should provide connection utilities,
# not orchestrate user's dbt workflows. User maintains full control over
# dbt profiles, models, and execution patterns.
#
# =============================================================================

set -euo pipefail

# Source connection utilities (legitimate framework concern)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/connection_resolver.sh"

# DEPRECATED FUNCTIONS - Use direct dbt commands instead

execute_dbt_phase() {
    echo "ERROR: execute_dbt_phase is deprecated. Use direct dbt commands instead." >&2
    echo "Migration: cd your_dbt_project/ && dbt build --connection CONN" >&2
    echo "Framework provides connection utilities only, not dbt orchestration." >&2
    return 1
}

generate_dbt_profile() {
    echo "ERROR: generate_dbt_profile is deprecated. Manage profiles.yml directly." >&2
    echo "Framework should not generate user's dbt configuration." >&2
    return 1
}

validate_dbt_environment() {
    echo "ERROR: validate_dbt_environment is deprecated. Use dbt debug." >&2
    return 1
}

show_dbt_orchestrator_help() {
    cat <<EOF
dbt_orchestrator.sh — DEPRECATED

This component has been deprecated due to architectural violations.
dbt operations are user domain logic, not framework concerns.

CORRECTED APPROACH:
  Framework: Provides connection utilities only
  User: Manages dbt project, profiles, and operations directly

MIGRATION:
  Old: execute_dbt_phase --config domain.yml --phase build
  New: cd artwork_pipeline/ && dbt build --connection CONN

RATIONALE:
  dbt is user domain logic. The framework should provide connection 
  utilities but not orchestrate user's dbt workflows. Clean separation
  means user maintains full control over dbt profiles and operations.

AVAILABLE FROM FRAMEWORK:
  - Connection resolution via connection_resolver.sh
  - Connection validation and capability checking

USER RESPONSIBILITY:
  - dbt project structure and configuration
  - profiles.yml management
  - dbt model development and execution
  - dbt testing and documentation

EOF
}

# Handle --help flag when script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--help" ]]; then
    show_dbt_orchestrator_help
    exit 0
fi