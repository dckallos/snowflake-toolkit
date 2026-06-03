#!/usr/bin/env bash
# =============================================================================
# dbt_orchestrator.sh — Domain-agnostic dbt lifecycle management framework
# =============================================================================
#
# CONTEXT: Domain-agnostic Snowflake CLI framework component
# PURPOSE: Manages dbt operations for any domain configuration and dbt project
# MAINTAINER: Facebook staff-level implementation
#
# This module provides enterprise-grade dbt orchestration that works with any
# domain configuration, any dbt project structure, and any Snowflake account.
# It replaces domain-specific dbt management with a parameterized framework
# that maintains all operational guarantees while enabling unlimited reusability.
#
# ARCHITECTURE:
#   - Dynamic profile generation from domain configuration
#   - Connection-aware capability validation for dbt operations
#   - Unified lifecycle management across all dbt phases
#   - Domain-agnostic project path resolution
#   - Comprehensive error handling and validation
#
# USAGE:
#   source scripts/lib/dbt_orchestrator.sh
#   execute_dbt_phase --config config/domain.yml --phase build --connection transformer
#   generate_dbt_profile --config config/domain.yml --connection transformer
#
# INTEGRATION:
#   Integrates with all framework components:
#   - connection_resolver.sh for connection management
#   - domain_config_loader.sh for configuration access
#   - ddl_orchestrator.sh for schema management
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly DBT_ORCHESTRATOR_VERSION="1.0.0"
readonly DBT_ORCHESTRATOR_CREATED="2026-06-02"

# Source required framework components
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/connection_resolver.sh"
source "${SCRIPT_DIR}/domain_config_loader.sh"

# Execution state
CURRENT_DOMAIN_CONFIG=""
CURRENT_CONNECTION=""
DBT_EXECUTION_LOG_DIR="/tmp/dbt_orchestrator_logs_$$"

# =============================================================================
# CORE DBT EXECUTION FUNCTIONS
# =============================================================================

# execute_dbt_phase
#
# Executes a dbt lifecycle phase for a domain configuration.
# Provides comprehensive dbt orchestration with proper environment setup.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --phase PHASE_NAME      dbt phase (init|deps|build|test|docs|teardown|full-refresh)
#   --connection CONN_NAME  Optional explicit connection name
#   --target TARGET_NAME    Optional dbt target override
#
# RETURNS:
#   exit 0: Phase executed successfully
#   exit 1: Phase execution failed
execute_dbt_phase() {
    local config_file=""
    local phase=""
    local explicit_connection=""
    local target_override=""
    
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
            --target)
                target_override="$2"
                shift 2
                ;;
            --help)
                show_dbt_orchestrator_help
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
    
    _log_info "Starting dbt phase execution: $phase"
    _log_debug "Config: $config_file, Phase: $phase, Connection: $explicit_connection, Target: $target_override"
    
    # Initialize execution environment
    if ! _initialize_dbt_environment "$config_file" "$explicit_connection"; then
        return 1
    fi
    
    # Execute phase-specific logic
    case "$phase" in
        init)
            _execute_dbt_init_phase "$target_override"
            ;;
        deps)
            _execute_dbt_deps_phase
            ;;
        build)
            _execute_dbt_build_phase "$target_override"
            ;;
        test)
            _execute_dbt_test_phase "$target_override"
            ;;
        docs)
            _execute_dbt_docs_phase "$target_override"
            ;;
        teardown)
            _execute_dbt_teardown_phase
            ;;
        full-refresh)
            _execute_dbt_full_refresh_phase "$target_override"
            ;;
        *)
            _log_error "Unknown phase: $phase"
            _log_error "Valid phases: init, deps, build, test, docs, teardown, full-refresh"
            return 1
            ;;
    esac
}

# generate_dbt_profile
#
# Generates a dbt profile for a domain configuration and connection.
# Creates dynamic profiles.yml based on domain config and connection details.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --connection CONN_NAME  Optional explicit connection name
#   --target TARGET_NAME    Optional target name override
#   --output OUTPUT_FILE    Optional output file (default: stdout)
#
# RETURNS:
#   stdout: Generated dbt profile YAML
#   exit 0: Profile generated successfully
#   exit 1: Profile generation failed
generate_dbt_profile() {
    local config_file=""
    local explicit_connection=""
    local target_name="prod"
    local output_file=""
    
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
            --target)
                target_name="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --help)
                show_dbt_orchestrator_help
                return 0
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
    
    # Load domain configuration
    if ! load_domain_config "$config_file"; then
        return 1
    fi
    
    # Resolve connection for transformer capability
    local connection
    if ! connection=$(resolve_connection_with_capability transformer "$explicit_connection"); then
        return 1
    fi
    
    # Generate profile content
    local profile_content
    if ! profile_content=$(_generate_profile_content "$connection" "$target_name"); then
        return 1
    fi
    
    # Output profile
    if [[ -n "$output_file" ]]; then
        echo "$profile_content" > "$output_file"
        _log_info "dbt profile written to: $output_file"
    else
        echo "$profile_content"
    fi
    
    return 0
}

# validate_dbt_environment
#
# Validates that the environment is ready for dbt operations.
# Comprehensive pre-flight checks for dbt execution.
#
# PARAMETERS:
#   --config CONFIG_FILE    Domain configuration file
#   --connection CONN_NAME  Optional explicit connection name
#
# RETURNS:
#   exit 0: Environment is valid for dbt operations
#   exit 1: Environment validation failed
validate_dbt_environment() {
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
    
    _log_info "Validating dbt environment..."
    
    # Load configuration
    if ! load_domain_config "$config_file"; then
        return 1
    fi
    
    # Validate dbt CLI is available
    if ! command -v dbt >/dev/null 2>&1; then
        _log_error "dbt CLI not found. Install with: pip install dbt-snowflake"
        return 1
    fi
    
    # Validate dbt project exists
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    if [[ ! -d "$project_dir" ]]; then
        _log_error "dbt project directory not found: $project_dir"
        return 1
    fi
    
    if [[ ! -f "$project_dir/dbt_project.yml" ]]; then
        _log_error "dbt_project.yml not found in: $project_dir"
        return 1
    fi
    
    # Resolve and validate connection
    local connection
    if ! connection=$(resolve_connection_with_capability transformer "$explicit_connection"); then
        return 1
    fi
    
    if ! validate_connection_capability "$connection" transformer; then
        return 1
    fi
    
    _log_info "dbt environment validation passed"
    return 0
}

# =============================================================================
# PRIVATE DBT EXECUTION FUNCTIONS
# =============================================================================

# Initialize dbt execution environment
_initialize_dbt_environment() {
    local config_file="$1"
    local explicit_connection="$2"
    
    # Create execution log directory
    mkdir -p "$DBT_EXECUTION_LOG_DIR"
    
    # Load domain configuration
    if ! load_domain_config "$config_file"; then
        return 1
    fi
    CURRENT_DOMAIN_CONFIG="$config_file"
    
    # Resolve connection with transformer capability
    if ! CURRENT_CONNECTION=$(resolve_connection_with_capability transformer "$explicit_connection"); then
        return 1
    fi
    
    # Validate connection capability for dbt operations
    if ! validate_connection_capability "$CURRENT_CONNECTION" transformer; then
        return 1
    fi
    
    # Validate dbt environment
    if ! _validate_dbt_project_structure; then
        return 1
    fi
    
    _log_info "dbt execution environment initialized"
    _log_info "Domain: $(get_domain_config "domain.name")"
    _log_info "Project: $(get_domain_config "dbt.project_dir")"
    _log_info "Connection: $CURRENT_CONNECTION"
    
    return 0
}

# Execute dbt init phase
_execute_dbt_init_phase() {
    local target_override="$1"
    
    _log_info "Executing dbt init phase..."
    
    # Generate dynamic profile
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    
    local profiles_dir="$project_dir"
    local profile_file="$profiles_dir/profiles.yml"
    
    if ! generate_dbt_profile --config "$CURRENT_DOMAIN_CONFIG" --connection "$CURRENT_CONNECTION" --target "${target_override:-prod}" --output "$profile_file"; then
        _log_error "Failed to generate dbt profile"
        return 1
    fi
    
    # Install dbt dependencies
    if ! _execute_dbt_command "deps" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    # Run dbt debug to verify connectivity
    if ! _execute_dbt_command "debug" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    _log_info "dbt init phase completed successfully"
    return 0
}

# Execute dbt deps phase
_execute_dbt_deps_phase() {
    _log_info "Executing dbt deps phase..."
    
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    local profiles_dir="$project_dir"
    
    if ! _execute_dbt_command "deps" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    _log_info "dbt deps phase completed successfully"
    return 0
}

# Execute dbt build phase
_execute_dbt_build_phase() {
    local target_override="$1"
    
    _log_info "Executing dbt build phase..."
    
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    local profiles_dir="$project_dir"
    
    # Ensure profile is up-to-date
    local profile_file="$profiles_dir/profiles.yml"
    if ! generate_dbt_profile --config "$CURRENT_DOMAIN_CONFIG" --connection "$CURRENT_CONNECTION" --target "${target_override:-prod}" --output "$profile_file"; then
        return 1
    fi
    
    if ! _execute_dbt_command "build" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    _log_info "dbt build phase completed successfully"
    return 0
}

# Execute dbt test phase
_execute_dbt_test_phase() {
    local target_override="$1"
    
    _log_info "Executing dbt test phase..."
    
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    local profiles_dir="$project_dir"
    
    # Ensure profile is up-to-date
    local profile_file="$profiles_dir/profiles.yml"
    if ! generate_dbt_profile --config "$CURRENT_DOMAIN_CONFIG" --connection "$CURRENT_CONNECTION" --target "${target_override:-prod}" --output "$profile_file"; then
        return 1
    fi
    
    if ! _execute_dbt_command "test" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    _log_info "dbt test phase completed successfully"
    return 0
}

# Execute dbt docs phase
_execute_dbt_docs_phase() {
    local target_override="$1"
    
    _log_info "Executing dbt docs phase..."
    
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    local profiles_dir="$project_dir"
    
    # Generate documentation
    if ! _execute_dbt_command "docs generate" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    # Serve documentation
    _log_info "Starting dbt docs server at http://localhost:8080 (Ctrl-C to stop)"
    if ! _execute_dbt_command "docs serve --port 8080" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    return 0
}

# Execute dbt teardown phase
_execute_dbt_teardown_phase() {
    _log_info "Executing dbt teardown phase..."
    
    local database
    database=$(get_domain_config "domain.database")
    
    # Get schemas for teardown
    local silver_schema gold_schema
    silver_schema=$(get_domain_config "dbt.schema_mapping.prod.staging" "SILVER")
    gold_schema=$(get_domain_config "dbt.schema_mapping.prod.marts" "GOLD")
    
    _log_info "WARNING: This will drop ALL objects in $database.{$silver_schema,$gold_schema}"
    echo -n "Type 'yes' to confirm teardown: "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        _log_info "Teardown aborted"
        return 0
    fi
    
    # Execute teardown via Snowflake CLI
    _log_info "Dropping and recreating dbt schemas..."
    
    if ! snow sql --query "DROP SCHEMA IF EXISTS ${database}.${silver_schema} CASCADE;" --connection "$CURRENT_CONNECTION"; then
        _log_error "Failed to drop Silver schema"
        return 1
    fi
    
    if ! snow sql --query "DROP SCHEMA IF EXISTS ${database}.${gold_schema} CASCADE;" --connection "$CURRENT_CONNECTION"; then
        _log_error "Failed to drop Gold schema"
        return 1
    fi
    
    if ! snow sql --query "CREATE SCHEMA IF NOT EXISTS ${database}.${silver_schema};" --connection "$CURRENT_CONNECTION"; then
        _log_error "Failed to recreate Silver schema"
        return 1
    fi
    
    if ! snow sql --query "CREATE SCHEMA IF NOT EXISTS ${database}.${gold_schema};" --connection "$CURRENT_CONNECTION"; then
        _log_error "Failed to recreate Gold schema"
        return 1
    fi
    
    _log_info "dbt teardown completed successfully"
    _log_info "Run infrastructure grants refresh and dbt build to restore state"
    return 0
}

# Execute dbt full-refresh phase
_execute_dbt_full_refresh_phase() {
    local target_override="$1"
    
    _log_info "Executing dbt full-refresh phase..."
    
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    local profiles_dir="$project_dir"
    
    # Ensure profile is up-to-date
    local profile_file="$profiles_dir/profiles.yml"
    if ! generate_dbt_profile --config "$CURRENT_DOMAIN_CONFIG" --connection "$CURRENT_CONNECTION" --target "${target_override:-prod}" --output "$profile_file"; then
        return 1
    fi
    
    if ! _execute_dbt_command "build --full-refresh" "$project_dir" "$profiles_dir"; then
        return 1
    fi
    
    _log_info "dbt full-refresh phase completed successfully"
    return 0
}

# Generate profile content for domain and connection
_generate_profile_content() {
    local connection="$1"
    local target_name="$2"
    
    # Get connection details via Snowflake CLI
    local connection_info
    if ! connection_info=$(snow connection describe "$connection" --format json 2>/dev/null); then
        _log_error "Failed to get connection details for: $connection"
        return 1
    fi
    
    # Extract connection parameters
    local account user role warehouse database
    account=$(echo "$connection_info" | jq -r '.account // empty')
    user=$(echo "$connection_info" | jq -r '.user // empty')
    role=$(echo "$connection_info" | jq -r '.role // empty')
    warehouse=$(echo "$connection_info" | jq -r '.warehouse // empty')
    database=$(echo "$connection_info" | jq -r '.database // empty')
    
    # Get domain-specific values
    local domain_name project_name target_database silver_schema gold_schema
    domain_name=$(get_domain_config "domain.name")
    project_name="${domain_name}_pipeline"
    target_database=$(get_domain_config "dbt.target_database" "$database")
    silver_schema=$(get_domain_config "dbt.schema_mapping.${target_name}.staging" "SILVER")
    gold_schema=$(get_domain_config "dbt.schema_mapping.${target_name}.marts" "GOLD")
    
    # Get private key path for the connection
    local private_key_path
    private_key_path="$HOME/.snowflake/keys/${connection}_rsa_key.p8"
    
    # Generate profiles.yml content
    cat <<EOF
${project_name}:
  target: ${target_name}
  outputs:
    ${target_name}:
      type: snowflake
      account: ${account}
      user: ${user}
      role: ${role}
      warehouse: ${warehouse}
      database: ${target_database}
      schema: ${silver_schema}
      authenticator: snowflake_jwt
      private_key_path: ${private_key_path}
      
    dev:
      type: snowflake
      account: ${account}
      user: ${user}
      role: ${role}
      warehouse: ${warehouse}
      database: ${target_database}
      schema: ${silver_schema}_DEV
      authenticator: snowflake_jwt
      private_key_path: ${private_key_path}
EOF
}

# Execute dbt command with proper logging
_execute_dbt_command() {
    local command="$1"
    local project_dir="$2"
    local profiles_dir="$3"
    
    local log_file="$DBT_EXECUTION_LOG_DIR/dbt_${command// /_}.log"
    
    _log_info "Executing: dbt $command"
    
    if ! dbt $command --project-dir "$project_dir" --profiles-dir "$profiles_dir" > "$log_file" 2>&1; then
        _log_error "dbt $command failed"
        _log_error "Check log: $log_file"
        return 1
    fi
    
    return 0
}

# Validate dbt project structure
_validate_dbt_project_structure() {
    local project_dir
    project_dir=$(get_domain_config "dbt.project_dir")
    
    if [[ ! -d "$project_dir" ]]; then
        _log_error "dbt project directory not found: $project_dir"
        return 1
    fi
    
    if [[ ! -f "$project_dir/dbt_project.yml" ]]; then
        _log_error "dbt_project.yml not found in: $project_dir"
        return 1
    fi
    
    return 0
}

# Logging functions
_log_info() {
    echo "==> [dbt_orchestrator] $*" >&2
}

_log_debug() {
    if [[ "${FRAMEWORK_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG [dbt_orchestrator] $*" >&2
    fi
}

_log_error() {
    echo "ERROR [dbt_orchestrator] $*" >&2
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_dbt_orchestrator_help() {
    cat <<EOF
dbt_orchestrator.sh — Domain-agnostic dbt lifecycle management framework

DESCRIPTION:
    Manages dbt operations for any domain configuration and dbt project with
    dynamic profile generation and comprehensive lifecycle management.

USAGE:
    source scripts/lib/dbt_orchestrator.sh
    
    # Execute dbt phases
    execute_dbt_phase --config CONFIG_FILE --phase PHASE [--connection CONN] [--target TARGET]
    
    # Generate dbt profile
    generate_dbt_profile --config CONFIG_FILE [--connection CONN] [--target TARGET] [--output FILE]
    
    # Validate environment
    validate_dbt_environment --config CONFIG_FILE [--connection CONN]

PHASES:
    init            Generate profile, install deps, verify connectivity
    deps            Install dbt package dependencies
    build           Execute models and tests
    test            Execute tests only
    docs            Generate and serve documentation
    teardown        Drop all dbt-managed objects (requires confirmation)
    full-refresh    Rebuild all models from scratch

OPTIONS:
    --config FILE       Domain configuration file (required)
    --phase PHASE       dbt phase to execute (required for execute_dbt_phase)
    --connection CONN   Explicit connection name (optional)
    --target TARGET     dbt target override (optional, default: prod)
    --output FILE       Output file for profile generation (optional)

ENVIRONMENT VARIABLES:
    FRAMEWORK_DEBUG     Set to 1 for debug logging

DEPENDENCIES:
    connection_resolver.sh      Connection management
    domain_config_loader.sh     Configuration management
    dbt CLI                     dbt operations (pip install dbt-snowflake)
    snow CLI                   Snowflake operations
    jq                         JSON processing

EXIT CODES:
    0   Success
    1   Execution failed, validation failed, or missing dependency

EXAMPLES:
    # Initialize dbt environment
    execute_dbt_phase --config config/artwork_domain.yml --phase init --connection transformer
    
    # Build models and tests
    execute_dbt_phase --config config/customer_domain.yml --phase build --connection prod-transformer
    
    # Generate profile for inspection
    generate_dbt_profile --config config/artwork_domain.yml --connection transformer --output my_profile.yml
    
    # Validate environment before execution
    validate_dbt_environment --config config/artwork_domain.yml

PROFILE GENERATION:
    Profiles are generated dynamically from:
    - Domain configuration (database, schemas, project name)
    - Connection details (account, user, role, warehouse, key path)
    - Target-specific schema mappings (prod vs dev)

SCHEMA MAPPING:
    Schemas are mapped based on domain configuration:
    - Staging models → domain.dbt.schema_mapping.{target}.staging (default: SILVER)
    - Mart models → domain.dbt.schema_mapping.{target}.marts (default: GOLD)

EOF
}

# Handle --help flag when script is executed directly
if [[ "${1:-}" == "--help" ]]; then
    show_dbt_orchestrator_help
    exit 0
fi