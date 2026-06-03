#!/usr/bin/env bash
# =============================================================================
# orchestrate_modern.sh — Modernized DDL orchestrator using domain-agnostic framework
# =============================================================================
#
# CONTEXT: Legacy script modernization for domain-agnostic framework
# PURPOSE: Modernized version of scripts/orchestrate.sh using framework components
# MAINTAINER: Facebook staff-level implementation
#
# This script provides modernized DDL orchestration using the domain-agnostic
# framework components. It maintains backward compatibility with existing
# Makefile targets while enabling multi-domain deployments and improved
# error handling. Once thoroughly tested, this will replace scripts/orchestrate.sh.
#
# ARCHITECTURE:
#   - Uses scripts/lib/ddl_orchestrator.sh for core functionality
#   - Maintains backward compatibility with existing CLI interface
#   - Adds domain configuration support via --config parameter
#   - Enhanced connection resolution and validation
#
# USAGE:
#   scripts/orchestrate_modern.sh --phase infra --connection admin
#   scripts/orchestrate_modern.sh --config config/artwork_domain.yml --phase all --connection mk07348
#   scripts/orchestrate_modern.sh --phase down --from create_stages --connection admin
#
# TESTING STATUS: New implementation - requires thorough testing before replacing legacy script
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly ORCHESTRATE_MODERN_VERSION="1.0.0"
readonly ORCHESTRATE_MODERN_CREATED="2026-06-02"

# Script configuration  
readonly MODERN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${MODERN_SCRIPT_DIR}/.." && pwd)"

# Source framework components
source "${MODERN_SCRIPT_DIR}/lib/ddl_orchestrator.sh"

# Default values for backward compatibility
DEFAULT_CONFIG="${REPO_ROOT}/config/artwork_domain.yml"
DEFAULT_CONNECTION="admin"

# =============================================================================
# MAIN ORCHESTRATION FUNCTION
# =============================================================================

# main
#
# Primary entry point for modernized DDL orchestration.
# Provides backward compatibility while using domain-agnostic framework.
main() {
    local config_file=""
    local phase=""
    local connection=""
    local from_script=""
    local down_file=""
    local show_help=false
    
    # Parse arguments with backward compatibility
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --connection)
                connection="$2"
                shift 2
                ;;
            --from)
                from_script="$2"
                shift 2
                ;;
            --down)
                # Legacy flag compatibility
                if [[ "${2:-}" != --* && -n "${2:-}" ]]; then
                    phase="down"
                    shift
                else
                    phase="down"
                    shift
                fi
                ;;
            --file)
                # Legacy single script rollback
                down_file="$2"
                shift 2
                ;;
            -h|--help|help)
                show_help=true
                shift
                ;;
            *)
                _log_error "Unknown argument: $1"
                _show_usage
                exit 1
                ;;
        esac
    done
    
    # Show help if requested
    if [[ "$show_help" == true ]]; then
        _show_usage
        exit 0
    fi
    
    # Validate and set defaults
    if [[ -z "$config_file" ]]; then
        if [[ -f "$DEFAULT_CONFIG" ]]; then
            config_file="$DEFAULT_CONFIG"
            _log_info "Using default configuration: $config_file"
        else
            _log_error "No configuration specified and default not found: $DEFAULT_CONFIG"
            _log_error "Specify configuration with: --config CONFIG_FILE"
            exit 1
        fi
    fi
    
    if [[ -z "$phase" ]]; then
        _log_error "Phase is required. Use --help for usage information."
        exit 1
    fi
    
    # Handle legacy single script rollback
    if [[ -n "$down_file" ]]; then
        _log_info "Modernized DDL Orchestrator v${ORCHESTRATE_MODERN_VERSION}"
        _log_info "Rolling back single script: $down_file"
        
        rollback_ddl_script --config "$config_file" --file "$down_file" --connection "$connection"
        exit $?
    fi
    
    # Execute main DDL phase
    _log_info "Modernized DDL Orchestrator v${ORCHESTRATE_MODERN_VERSION}"
    _log_info "Domain-agnostic framework execution"
    
    execute_ddl_phase --config "$config_file" --phase "$phase" --connection "$connection" --from "$from_script"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Show usage information with backward compatibility notes
_show_usage() {
    cat <<EOF
orchestrate_modern.sh — Modernized DDL orchestrator using domain-agnostic framework

DESCRIPTION:
    Modernized version of scripts/orchestrate.sh that uses domain-agnostic framework
    components. Provides backward compatibility while enabling multi-domain deployments.

USAGE:
    scripts/orchestrate_modern.sh [OPTIONS]

OPTIONS:
    --config FILE       Domain configuration file (default: config/artwork_domain.yml)
    --phase PHASE       Phase to execute (infra|bootstrap|all|down)
    --connection CONN   Snowflake connection name (optional)
    --from SCRIPT       Start execution from specific script (optional)
    --file FILE         Roll back single script (legacy compatibility)
    --help              Show this help message

PHASES:
    infra               Execute infrastructure DDL scripts (databases, roles, warehouses)
    bootstrap           Execute Git integration setup scripts  
    all                 Execute infrastructure then bootstrap phases
    down                Execute teardown using paired drop scripts

BACKWARD COMPATIBILITY:
    # Legacy orchestrate.sh command format
    scripts/orchestrate.sh --phase infra --connection admin
    
    # Modern equivalent
    scripts/orchestrate_modern.sh --phase infra --connection admin
    
    # Multi-domain deployment (new capability)
    scripts/orchestrate_modern.sh --config config/customer_domain.yml --phase all --connection prod

FRAMEWORK INTEGRATION:
    - Uses scripts/lib/ddl_orchestrator.sh for core functionality
    - Domain configuration via YAML files in config/
    - Enhanced connection resolution and validation
    - Template substitution for domain-specific values
    - Comprehensive error handling and logging

MIGRATION NOTES:
    1. Test modernized script alongside legacy version
    2. Validate identical behavior for existing workflows
    3. Leverage new domain configuration capabilities
    4. Update Makefile targets to use modernized script

EXAMPLES:
    # Basic infrastructure deployment
    scripts/orchestrate_modern.sh --phase infra --connection admin
    
    # Multi-account deployment
    scripts/orchestrate_modern.sh --config config/artwork_domain.yml --phase all --connection mk07348
    
    # Partial deployment from specific script
    scripts/orchestrate_modern.sh --phase infra --from create_warehouses.sql --connection admin
    
    # Single script rollback
    scripts/orchestrate_modern.sh --file create_stages.sql --connection admin

EOF
}

# Logging function
_log_info() {
    echo "==> [orchestrate_modern] $*" >&2
}

_log_error() {
    echo "ERROR [orchestrate_modern] $*" >&2
}

# =============================================================================
# EXECUTION
# =============================================================================

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi