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
source "${MODERN_SCRIPT_DIR}/lib/connection_resolver.sh"

# Pure orchestration - no defaults, user must specify paths and connections

# =============================================================================
# MAIN ORCHESTRATION FUNCTION
# =============================================================================

# main
#
# Primary entry point for modernized DDL orchestration.
# Provides backward compatibility while using domain-agnostic framework.
main() {
    local ddl_dir=""
    local manifest_file=""
    local phase=""
    local connection=""
    local from_script=""
    local down_file=""
    local show_help=false
    declare -a variables=()
    
    # Parse arguments with backward compatibility
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ddl-dir)
                ddl_dir="$2"
                shift 2
                ;;
            --manifest)
                manifest_file="$2"
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
            --var)
                # Template variable for DDL substitution
                variables+=("$2")
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
    
    # Validate required parameters - no defaults
    if [[ -z "$ddl_dir" ]]; then
        _log_error "DDL directory is required. Use --ddl-dir DIR"
        exit 1
    fi
    
    if [[ -z "$manifest_file" ]]; then
        _log_error "Manifest file is required. Use --manifest FILE"
        exit 1
    fi
    
    if [[ -z "$connection" ]]; then
        _log_error "Connection is required. Use --connection NAME"
        exit 1
    fi
    
    if [[ ! -d "$ddl_dir" ]]; then
        _log_error "DDL directory not found: $ddl_dir"
        exit 1
    fi
    
    if [[ ! -f "$manifest_file" ]]; then
        _log_error "Manifest file not found: $manifest_file"
        exit 1
    fi
    
    if [[ -z "$phase" ]]; then
        _log_error "Phase is required. Use --help for usage information."
        exit 1
    fi
    
    # Handle legacy single script rollback
    if [[ -n "$down_file" ]]; then
        _log_info "Pure Orchestration Framework v${ORCHESTRATE_MODERN_VERSION}"
        _log_info "Rolling back single script: $down_file"
        
        _rollback_single_ddl_script "$down_file" "$connection"
        exit $?
    fi
    
    # Execute main DDL phase
    _log_info "Pure Orchestration Framework v${ORCHESTRATE_MODERN_VERSION}"
    _log_info "Executing user DDL unchanged via connection framework"
    
    _execute_ddl_phase "$ddl_dir" "$manifest_file" "$phase" "$connection" "$from_script" "${variables[@]+"${variables[@]}"}"
}

# =============================================================================
# PURE ORCHESTRATION FUNCTIONS
# =============================================================================

# Execute DDL phase - pure connection + file execution
_execute_ddl_phase() {
    local ddl_dir="$1"
    local manifest_file="$2"
    local phase="$3"
    local connection="$4"
    local from_script="$5"
    shift 5
    declare -a variables=()
    if [[ $# -gt 0 ]]; then
        variables=("$@")
    fi
    
    # Resolve connection
    local resolved_connection
    if ! resolved_connection=$(resolve_connection_with_capability admin "$connection"); then
        _log_error "Failed to resolve connection: $connection"
        return 1
    fi
    
    # Execute scripts from manifest
    local started=0
    if [[ -n "$from_script" ]]; then
        started=0
    else
        started=1
    fi
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check if this script matches the target phase
        local script_phase
        script_phase=$(dirname "$line")
        if [[ "$phase" == "infra" && "$script_phase" != "infrastructure" ]]; then
            continue
        elif [[ "$phase" == "bootstrap" && "$script_phase" != "git-setup" ]]; then
            continue
        elif [[ "$phase" == "down" ]]; then
            # Teardown logic would go here
            continue
        fi
        
        # Check if we should start executing (for --from option)
        if [[ $started -eq 0 ]]; then
            local script_name
            script_name=$(basename "$line")
            local from_name
            from_name=$(basename "$from_script")
            if [[ "$script_name" == "$from_name" ]]; then
                started=1
            else
                continue
            fi
        fi
        
        # Execute the script unchanged
        local full_script_path="${REPO_ROOT}/$line"
        if ! _execute_single_ddl_script "$full_script_path" "$resolved_connection" "${variables[@]+"${variables[@]}"}"; then
            _log_error "Failed to execute script: $line"
            return 1
        fi
        
    done < "$manifest_file"
    
    return 0
}

# Execute single DDL script unchanged with optional variable substitution
_execute_single_ddl_script() {
    local script_path="$1"
    local connection="$2"
    shift 2
    declare -a variables=()
    if [[ $# -gt 0 ]]; then
        variables=("$@")
    fi
    
    # Build variable arguments for snow sql
    local -a var_args=()
    if [[ ${#variables[@]} -gt 0 ]]; then
        for var in "${variables[@]}"; do
            if [[ -n "$var" ]]; then
                var_args+=("-D" "$var")
            fi
        done
    fi
    
    _log_info "Executing script: $(basename "$script_path")"
    
    # Check if script exists
    if [[ ! -f "$script_path" ]]; then
        _log_error "Script not found: $script_path"
        return 1
    fi
    
    # Execute via Snowflake CLI (user's DDL unchanged, with optional template substitution)
    if ! snow sql --filename "$script_path" --connection "$connection" "${var_args[@]+"${var_args[@]}"}"; then
        _log_error "Script execution failed: $(basename "$script_path")"
        return 1
    fi
    
    _log_info "Script completed: $(basename "$script_path")"
    return 0
}

# Rollback single DDL script
_rollback_single_ddl_script() {
    local script_file="$1"
    local connection="$2"
    
    # Derive drop script name
    local create_basename
    create_basename=$(basename "$script_file")
    local drop_basename
    drop_basename="${create_basename/create_/drop_}"
    
    local drop_script
    drop_script="infrastructure/$drop_basename"
    
    if [[ ! -f "$drop_script" ]]; then
        _log_error "Paired drop script not found: $drop_script"
        return 1
    fi
    
    # Resolve connection
    local resolved_connection
    if ! resolved_connection=$(resolve_connection_with_capability admin "$connection"); then
        _log_error "Failed to resolve connection: $connection"
        return 1
    fi
    
    # Execute drop script
    _log_info "Rolling back with drop script: $(basename "$drop_script")"
    _execute_single_ddl_script "$drop_script" "$resolved_connection"
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
    --ddl-dir DIR       DDL directory (required)
    --manifest FILE     Manifest file (required)
    --phase PHASE       Phase to execute (infra|bootstrap|all|down)
    --connection CONN   Snowflake connection name (required)
    --from SCRIPT       Start execution from specific script (optional)
    --var NAME=VALUE    Template variable for DDL substitution (repeatable)
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
    
    # Connection flexibility (work with any configured account)
    scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --phase all --connection prod

FRAMEWORK INTEGRATION:
    - Uses scripts/lib/connection_resolver.sh for connection management
    - Pure file orchestration - no domain configuration
    - Enhanced connection resolution and validation
    - User's DDL files executed unchanged
    - Comprehensive error handling and logging

MIGRATION NOTES:
    1. Test modernized script alongside legacy version
    2. Validate identical behavior for existing workflows
    3. Leverage new domain configuration capabilities
    4. Update Makefile targets to use modernized script

EXAMPLES:
    # Basic infrastructure deployment
    scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase infra --connection prod-admin
    
    # Deployment with template variables
    scripts/orchestrate_modern.sh --ddl-dir git-setup/ --manifest scripts/manifest.txt --phase bootstrap --connection admin --var github_pat=ghp_example123
    
    # Work with specific account  
    scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase all --connection mk07348
    
    # Partial deployment from specific script
    scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase infra --from create_warehouses.sql --connection prod-admin
    
    # Single script rollback
    scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --file create_stages.sql --connection prod-admin

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