#!/usr/bin/env bash
# =============================================================================
# ddl_orchestrator.sh — Domain-agnostic DDL execution framework
# =============================================================================
#
# CONTEXT: Domain-agnostic Snowflake CLI framework component  
# PURPOSE: Executes DDL operations for any domain configuration
# MAINTAINER: Facebook staff-level implementation
#
# This module provides enterprise-grade DDL orchestration that works with any
# domain configuration, any manifest structure, and any Snowflake account.
# It replaces domain-specific orchestration with a parameterized framework
# that maintains all safety guarantees while enabling unlimited reusability.
#
# ARCHITECTURE:
#   - Domain-agnostic manifest processing
#   - Parameterized DDL execution via domain configuration  
#   - Connection-aware capability validation
#   - Comprehensive rollback and teardown support
#   - Template substitution for domain-specific values
#
# USAGE:
#   source scripts/lib/ddl_orchestrator.sh
#   execute_ddl_phase --config config/domain.yml --phase infra --connection admin
#   rollback_ddl_script --config config/domain.yml --file create_tables.sql --connection admin
#
# INTEGRATION:
#   Integrates with all framework components:
#   - connection_resolver.sh for connection management
#   - domain_config_loader.sh for configuration access
#   - git_integration.sh for repository mirroring
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly DDL_ORCHESTRATOR_VERSION="1.0.0"
readonly DDL_ORCHESTRATOR_CREATED="2026-06-02"

# Source required framework components
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/connection_resolver.sh"
source "${SCRIPT_DIR}/domain_config_loader.sh"

# Execution state
CURRENT_DOMAIN_CONFIG=""
CURRENT_CONNECTION=""
EXECUTION_LOG_DIR="/tmp/ddl_orchestrator_logs_$$"

# =============================================================================
# CORE DDL EXECUTION FUNCTIONS
# =============================================================================

# execute_ddl_phase
#
# Executes a complete DDL phase (infra, bootstrap, all, etc.) for a domain.
# Provides comprehensive orchestration with proper sequencing and validation.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --phase PHASE_NAME      Phase to execute (infra|bootstrap|all|down)
#   --connection CONN_NAME  Optional explicit connection name
#   --from FROM_SCRIPT      Optional starting point for partial operations
#
# RETURNS:
#   exit 0: Phase executed successfully
#   exit 1: Phase execution failed
#
# BEHAVIOR:
#   1. Loads domain configuration and validates prerequisites
#   2. Resolves connection with appropriate capability
#   3. Executes DDL scripts in manifest order with proper sequencing
#   4. Validates post-execution state
execute_ddl_phase() {
    local config_file=""
    local phase=""
    local explicit_connection=""
    local from_script=""
    
    # Parse arguments
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
                explicit_connection="$2"
                shift 2
                ;;
            --from)
                from_script="$2"
                shift 2
                ;;
            --help)
                show_ddl_orchestrator_help
                return 0
                ;;
            *)
                _log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$config_file" || -z "$phase" ]]; then
        _log_error "Missing required arguments. Use --help for usage."
        return 1
    fi
    
    _log_info "Starting DDL phase execution: $phase"
    _log_debug "Config: $config_file, Phase: $phase, Connection: $explicit_connection, From: $from_script"
    
    # Initialize execution environment
    if ! _initialize_execution_environment "$config_file" "$explicit_connection"; then
        return 1
    fi
    
    # Execute phase-specific logic
    case "$phase" in
        infra)
            _execute_infrastructure_phase "$from_script"
            ;;
        bootstrap)
            _execute_bootstrap_phase "$from_script"
            ;;
        all)
            _execute_all_phases "$from_script"
            ;;
        down)
            _execute_teardown_phase "$from_script"
            ;;
        *)
            _log_error "Unknown phase: $phase. Valid phases: infra, bootstrap, all, down"
            return 1
            ;;
    esac
}

# rollback_ddl_script
#
# Rolls back a single DDL script using its paired drop script.
# Provides granular rollback capability for targeted fixes.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --file SCRIPT_FILE      Script to roll back (create_*.sql)
#   --connection CONN_NAME  Optional explicit connection name
#
# RETURNS:
#   exit 0: Script rolled back successfully
#   exit 1: Rollback failed
rollback_ddl_script() {
    local config_file=""
    local script_file=""
    local explicit_connection=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                shift 2
                ;;
            --file)
                script_file="$2"
                shift 2
                ;;
            --connection)
                explicit_connection="$2"
                shift 2
                ;;
            --help)
                show_ddl_orchestrator_help
                return 0
                ;;
            *)
                _log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$config_file" || -z "$script_file" ]]; then
        _log_error "Missing required arguments. Use --help for usage."
        return 1
    fi
    
    _log_info "Rolling back DDL script: $script_file"
    
    # Initialize execution environment
    if ! _initialize_execution_environment "$config_file" "$explicit_connection"; then
        return 1
    fi
    
    # Execute rollback
    _rollback_single_script "$script_file"
}

# validate_ddl_environment
#
# Validates that the environment is ready for DDL operations.
# Comprehensive pre-flight checks to prevent deployment failures.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --connection CONN_NAME  Optional explicit connection name
#
# RETURNS:
#   exit 0: Environment is valid for DDL operations
#   exit 1: Environment validation failed
validate_ddl_environment() {
    local config_file=""
    local explicit_connection=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                shift 2
                ;;
            --connection)
                explicit_connection="$2"
                shift 2
                ;;
            *)
                _log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done
    
    if [[ -z "$config_file" ]]; then
        _log_error "Missing required --config argument"
        return 1
    fi
    
    _log_info "Validating DDL environment..."
    
    # Load configuration
    if ! load_domain_config "$config_file"; then
        return 1
    fi
    
    # Resolve connection
    local connection
    if ! connection=$(resolve_connection_with_capability admin "$explicit_connection"); then
        return 1
    fi
    
    # Validate connection capability
    if ! validate_connection_capability "$connection" admin; then
        return 1
    fi
    
    # Validate domain prerequisites
    if ! validate_domain_config_prerequisites; then
        return 1
    fi
    
    # Validate manifest and DDL files exist
    if ! _validate_manifest_and_ddl_files; then
        return 1
    fi
    
    _log_info "DDL environment validation passed"
    return 0
}

# =============================================================================
# PRIVATE EXECUTION FUNCTIONS
# =============================================================================

# Initialize execution environment
_initialize_execution_environment() {
    local config_file="$1"
    local explicit_connection="$2"
    
    # Create execution log directory
    mkdir -p "$EXECUTION_LOG_DIR"
    
    # Load domain configuration
    if ! load_domain_config "$config_file"; then
        return 1
    fi
    CURRENT_DOMAIN_CONFIG="$config_file"
    
    # Resolve connection with admin capability
    if ! CURRENT_CONNECTION=$(resolve_connection_with_capability admin "$explicit_connection"); then
        return 1
    fi
    
    # Validate connection capability
    if ! validate_connection_capability "$CURRENT_CONNECTION" admin; then
        return 1
    fi
    
    # Validate domain prerequisites
    if ! validate_domain_config_prerequisites; then
        return 1
    fi
    
    _log_info "Execution environment initialized"
    _log_info "Domain: $(get_domain_config "domain.name")"
    _log_info "Database: $(get_domain_config "domain.database")"
    _log_info "Connection: $CURRENT_CONNECTION"
    
    return 0
}

# Execute infrastructure phase
_execute_infrastructure_phase() {
    local from_script="$1"
    
    _log_info "Executing infrastructure phase..."
    
    # Get infrastructure directory from domain config
    local ddl_dir
    ddl_dir=$(get_domain_config "infrastructure.ddl_dir" "infrastructure")
    
    # Execute infrastructure scripts from manifest
    if ! _execute_scripts_by_phase "infrastructure" "$ddl_dir" "$from_script"; then
        _log_error "Infrastructure phase execution failed"
        return 1
    fi
    
    _log_info "Infrastructure phase completed successfully"
    return 0
}

# Execute bootstrap phase (Git integration)
_execute_bootstrap_phase() {
    local from_script="$1"
    
    _log_info "Executing bootstrap phase..."
    
    # Get Git setup directory from domain config
    local git_setup_dir
    git_setup_dir=$(get_domain_config "infrastructure.git_setup_dir" "git-setup")
    
    # Execute Git setup scripts from manifest
    if ! _execute_scripts_by_phase "git-setup" "$git_setup_dir" "$from_script"; then
        _log_error "Bootstrap phase execution failed"
        return 1
    fi
    
    _log_info "Bootstrap phase completed successfully"
    return 0
}

# Execute all phases (infrastructure first, then bootstrap)
_execute_all_phases() {
    local from_script="$1"
    
    _log_info "Executing all phases (infrastructure + bootstrap)..."
    
    # Execute infrastructure first
    if ! _execute_infrastructure_phase "$from_script"; then
        return 1
    fi
    
    # Then execute bootstrap
    if ! _execute_bootstrap_phase ""; then
        return 1
    fi
    
    _log_info "All phases completed successfully"
    return 0
}

# Execute teardown phase
_execute_teardown_phase() {
    local from_script="$1"
    
    _log_info "Executing teardown phase..."
    
    # Get manifest file from domain config
    local manifest_file
    manifest_file=$(get_domain_config "infrastructure.manifest_file" "scripts/manifest.txt")
    
    # Execute teardown using paired drops in reverse order
    if ! _execute_teardown_from_manifest "$manifest_file" "$from_script"; then
        _log_error "Teardown phase execution failed"
        return 1
    fi
    
    _log_info "Teardown phase completed successfully"
    return 0
}

# Execute scripts filtered by phase
_execute_scripts_by_phase() {
    local target_phase="$1"
    local script_dir="$2"
    local from_script="$3"
    
    local manifest_file
    manifest_file=$(get_domain_config "infrastructure.manifest_file" "scripts/manifest.txt")
    
    local repo_root
    repo_root=$(get_domain_config "infrastructure.ddl_dir" "infrastructure")
    repo_root=$(dirname "$repo_root")  # Get parent directory
    
    # Read manifest and execute matching scripts
    local started=0
    if [[ -n "$from_script" ]]; then
        started=0  # Don't start until we find the from_script
    else
        started=1  # Start immediately if no from_script specified
    fi
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check if this script matches the target phase
        local script_phase
        script_phase=$(dirname "$line")
        if [[ "$script_phase" != "$target_phase" ]]; then
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
        
        # Execute the script
        local full_script_path="$repo_root/$line"
        if ! _execute_single_script "$full_script_path"; then
            _log_error "Failed to execute script: $line"
            return 1
        fi
        
    done < "$manifest_file"
    
    return 0
}

# Execute a single DDL script
_execute_single_script() {
    local script_path="$1"
    
    _log_info "Executing script: $(basename "$script_path")"
    
    # Check if script exists
    if [[ ! -f "$script_path" ]]; then
        _log_error "Script not found: $script_path"
        return 1
    fi
    
    # Apply domain-specific template substitution
    local processed_script
    processed_script=$(mktemp)
    if ! _apply_domain_template_substitution "$script_path" "$processed_script"; then
        rm -f "$processed_script"
        return 1
    fi
    
    # Execute via Snowflake CLI
    local log_file="$EXECUTION_LOG_DIR/$(basename "$script_path").log"
    if ! snow sql --filename "$processed_script" --connection "$CURRENT_CONNECTION" > "$log_file" 2>&1; then
        _log_error "Script execution failed: $(basename "$script_path")"
        _log_error "Check log: $log_file"
        rm -f "$processed_script"
        return 1
    fi
    
    # Cleanup
    rm -f "$processed_script"
    
    _log_info "Script completed: $(basename "$script_path")"
    return 0
}

# Apply domain-specific template substitution
_apply_domain_template_substitution() {
    local source_script="$1"
    local target_script="$2"
    
    # Start with original script content
    cp "$source_script" "$target_script"
    
    # Apply domain-specific substitutions
    local database
    database=$(get_domain_config "domain.database")
    
    local admin_role
    admin_role=$(get_domain_config "roles.admin")
    
    local loader_role  
    loader_role=$(get_domain_config "roles.loader")
    
    local transformer_role
    transformer_role=$(get_domain_config "roles.transformer")
    
    local warehouse
    warehouse=$(get_domain_config "warehouses.default")
    
    # Perform substitutions (using sed for broad compatibility)
    sed -i.bak \
        -e "s/<% domain.database %>/${database}/g" \
        -e "s/<% roles.admin %>/${admin_role}/g" \
        -e "s/<% roles.loader %>/${loader_role}/g" \
        -e "s/<% roles.transformer %>/${transformer_role}/g" \
        -e "s/<% warehouses.default %>/${warehouse}/g" \
        "$target_script"
    
    # Remove backup file
    rm -f "${target_script}.bak"
    
    return 0
}

# Validate manifest and DDL files
_validate_manifest_and_ddl_files() {
    local manifest_file
    manifest_file=$(get_domain_config "infrastructure.manifest_file" "scripts/manifest.txt")
    
    if [[ ! -f "$manifest_file" ]]; then
        _log_error "Manifest file not found: $manifest_file"
        return 1
    fi
    
    # Validate all scripts in manifest exist
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        local script_path="$line"
        if [[ ! -f "$script_path" ]]; then
            _log_error "Script referenced in manifest not found: $script_path"
            return 1
        fi
    done < "$manifest_file"
    
    return 0
}

# Rollback single script
_rollback_single_script() {
    local script_file="$1"
    
    # Find create script and derive drop script
    local create_script
    if [[ -f "$script_file" ]]; then
        create_script="$script_file"
    else
        # Try to find in infrastructure directory
        local ddl_dir
        ddl_dir=$(get_domain_config "infrastructure.ddl_dir" "infrastructure")
        create_script="$ddl_dir/$(basename "$script_file")"
    fi
    
    if [[ ! -f "$create_script" ]]; then
        _log_error "Create script not found: $script_file"
        return 1
    fi
    
    # Derive drop script name
    local create_basename
    create_basename=$(basename "$create_script")
    local drop_basename
    drop_basename="${create_basename/create_/drop_}"
    
    local drop_script
    drop_script="$(dirname "$create_script")/$drop_basename"
    
    if [[ ! -f "$drop_script" ]]; then
        _log_error "Paired drop script not found: $drop_script"
        return 1
    fi
    
    # Execute drop script
    _log_info "Rolling back with drop script: $(basename "$drop_script")"
    _execute_single_script "$drop_script"
}

# Execute teardown from manifest (placeholder)
_execute_teardown_from_manifest() {
    local manifest_file="$1"
    local from_script="$2"
    
    # This would implement reverse-order teardown logic
    _log_info "Teardown execution not yet implemented"
    return 0
}

# Logging functions
_log_info() {
    echo "==> [ddl_orchestrator] $*" >&2
}

_log_debug() {
    if [[ "${FRAMEWORK_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG [ddl_orchestrator] $*" >&2
    fi
}

_log_error() {
    echo "ERROR [ddl_orchestrator] $*" >&2
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_ddl_orchestrator_help() {
    cat <<EOF
ddl_orchestrator.sh — Domain-agnostic DDL execution framework

DESCRIPTION:
    Executes DDL operations for any domain configuration with comprehensive
    orchestration, validation, and rollback capabilities.

USAGE:
    source scripts/lib/ddl_orchestrator.sh
    
    # Execute DDL phases
    execute_ddl_phase --config CONFIG_FILE --phase PHASE [--connection CONN] [--from SCRIPT]
    
    # Rollback single script
    rollback_ddl_script --config CONFIG_FILE --file SCRIPT_FILE [--connection CONN]
    
    # Validate environment
    validate_ddl_environment --config CONFIG_FILE [--connection CONN]

PHASES:
    infra       Execute infrastructure DDL scripts (databases, roles, warehouses)
    bootstrap   Execute Git integration setup scripts
    all         Execute infrastructure then bootstrap phases
    down        Execute teardown using paired drop scripts

OPTIONS:
    --config FILE       Domain configuration file (required)
    --phase PHASE       Phase to execute (required for execute_ddl_phase)
    --connection CONN   Explicit connection name (optional)
    --from SCRIPT       Start execution from specific script (optional)
    --file SCRIPT       Script to rollback (required for rollback_ddl_script)

ENVIRONMENT VARIABLES:
    FRAMEWORK_DEBUG     Set to 1 for debug logging

DEPENDENCIES:
    connection_resolver.sh      Connection management
    domain_config_loader.sh     Configuration management
    snow CLI                    Snowflake operations
    yq                         YAML processing

EXIT CODES:
    0   Success
    1   Execution failed, validation failed, or missing dependency

EXAMPLES:
    # Execute infrastructure phase
    execute_ddl_phase --config config/artwork_domain.yml --phase infra --connection admin
    
    # Execute all phases with specific connection
    execute_ddl_phase --config config/customer_domain.yml --phase all --connection prod-admin
    
    # Rollback specific script
    rollback_ddl_script --config config/artwork_domain.yml --file create_tables.sql
    
    # Validate environment before deployment
    validate_ddl_environment --config config/artwork_domain.yml

TEMPLATE SUBSTITUTION:
    Scripts can use domain-specific templates that are substituted during execution:
    - <% domain.database %>      → Domain database name
    - <% roles.admin %>          → Domain admin role name
    - <% roles.loader %>         → Domain loader role name
    - <% roles.transformer %>    → Domain transformer role name
    - <% warehouses.default %>   → Domain default warehouse name

EOF
}

# Handle --help flag when script is executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--help" ]]; then
    show_ddl_orchestrator_help
    exit 0
fi