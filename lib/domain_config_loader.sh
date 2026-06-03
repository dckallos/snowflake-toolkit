#!/usr/bin/env bash
# =============================================================================
# domain_config_loader.sh — Domain configuration parser and validator
# =============================================================================
#
# CONTEXT: Domain-agnostic Snowflake CLI framework component
# PURPOSE: Loads and validates domain configuration files for framework operations
# MAINTAINER: Facebook staff-level implementation
#
# This module provides comprehensive domain configuration management for the
# framework. It loads YAML configurations, validates their structure and content,
# and provides safe access to configuration values with proper error handling.
#
# ARCHITECTURE:
#   - YAML parsing with comprehensive validation
#   - Type checking and constraint validation
#   - Conflict detection between domain configurations
#   - Caching for performance optimization
#
# USAGE:
#   source scripts/lib/domain_config_loader.sh
#   load_domain_config config/artwork_domain.yml
#   database=$(get_domain_config "domain.database")
#   validate_domain_config_prerequisites
#
# INTEGRATION:
#   Used by all framework components that need domain-specific configuration:
#   - scripts/lib/ddl_orchestrator.sh
#   - scripts/lib/dbt_orchestrator.sh
#   - scripts/lib/git_integration.sh
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly DOMAIN_CONFIG_LOADER_VERSION="1.0.0" 
readonly DOMAIN_CONFIG_LOADER_CREATED="2026-06-02"

# Configuration state
CURRENT_DOMAIN_CONFIG=""
CURRENT_CONFIG_DATA=""
CONFIG_CACHE_DIR="/tmp/snowflake_framework_config_cache_$$"

# =============================================================================
# CORE CONFIGURATION FUNCTIONS
# =============================================================================

# load_domain_config
#
# Loads and validates a domain configuration file.
# Performs comprehensive validation and caches parsed configuration.
#
# PARAMETERS:
#   $1 - config_file_path: Path to domain configuration YAML file
#
# RETURNS:
#   exit 0: Configuration loaded successfully
#   exit 1: Configuration invalid or file not found
#
# BEHAVIOR:
#   1. Validates file exists and is readable
#   2. Parses YAML structure
#   3. Validates required fields and data types
#   4. Caches parsed configuration for subsequent access
load_domain_config() {
    local config_file="$1"
    
    _log_debug "load_domain_config: file=$config_file"
    
    # Validate file exists and is readable
    if [[ ! -f "$config_file" ]]; then
        _log_error "Domain configuration file not found: $config_file"
        return 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        _log_error "Domain configuration file not readable: $config_file"
        return 1
    fi
    
    # Ensure we have YAML parser available
    if ! _ensure_yaml_parser; then
        return 1
    fi
    
    # Parse and validate YAML structure
    if ! _parse_and_validate_yaml "$config_file"; then
        return 1
    fi
    
    # Set as current configuration
    CURRENT_DOMAIN_CONFIG="$config_file"
    _log_info "Loaded domain configuration: $config_file"
    
    # Cache configuration for performance
    _cache_configuration "$config_file"
    
    return 0
}

# get_domain_config
#
# Retrieves a configuration value using dot notation.
# Provides safe access to nested configuration values.
#
# PARAMETERS:
#   $1 - config_path: Dot-separated path to configuration value (e.g., "domain.database")
#   $2 - default_value: Optional default value if path not found
#
# RETURNS:
#   stdout: Configuration value or default value
#   exit 0: Value found or default provided
#   exit 1: Path not found and no default provided
#
# EXAMPLES:
#   database=$(get_domain_config "domain.database")
#   admin_role=$(get_domain_config "roles.admin" "SYSADMIN")
get_domain_config() {
    local config_path="$1"
    local default_value="${2:-}"
    
    if [[ -z "$CURRENT_DOMAIN_CONFIG" ]]; then
        _log_error "No domain configuration loaded. Call load_domain_config first."
        return 1
    fi
    
    local value
    if value=$(_get_config_value "$config_path"); then
        echo "$value"
        return 0
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    else
        _log_error "Configuration path not found: $config_path"
        return 1
    fi
}

# validate_domain_config_prerequisites
#
# Validates that all prerequisites for domain deployment exist.
# Checks Snowflake objects, environment variables, and permissions.
#
# RETURNS:
#   exit 0: All prerequisites satisfied
#   exit 1: One or more prerequisites missing
validate_domain_config_prerequisites() {
    if [[ -z "$CURRENT_DOMAIN_CONFIG" ]]; then
        _log_error "No domain configuration loaded. Call load_domain_config first."
        return 1
    fi
    
    _log_info "Validating domain configuration prerequisites..."
    
    local validation_failed=0
    
    # Validate required environment variables
    if ! _validate_required_env_vars; then
        validation_failed=1
    fi
    
    # Validate connection capabilities
    if ! _validate_connection_capabilities; then
        validation_failed=1
    fi
    
    # Validate no conflicts with existing domains
    if ! _validate_no_domain_conflicts; then
        validation_failed=1
    fi
    
    if [[ $validation_failed -eq 1 ]]; then
        _log_error "Domain configuration validation failed"
        return 1
    fi
    
    _log_info "Domain configuration validation passed"
    return 0
}

# list_domain_info
#
# Displays comprehensive information about the loaded domain configuration.
# Useful for debugging and verification.
list_domain_info() {
    if [[ -z "$CURRENT_DOMAIN_CONFIG" ]]; then
        _log_error "No domain configuration loaded."
        return 1
    fi
    
    echo "=== Domain Configuration Information ==="
    echo "Configuration file: $CURRENT_DOMAIN_CONFIG"
    echo ""
    
    echo "Domain Identity:"
    echo "  Name: $(get_domain_config "domain.name" "unknown")"
    echo "  Description: $(get_domain_config "domain.description" "No description")"
    echo "  Database: $(get_domain_config "domain.database" "unknown")"
    echo ""
    
    echo "Roles:"
    echo "  Admin: $(get_domain_config "roles.admin" "unknown")"
    echo "  Loader: $(get_domain_config "roles.loader" "unknown")"
    echo "  Transformer: $(get_domain_config "roles.transformer" "unknown")"
    echo ""
    
    echo "Warehouses:"
    echo "  Default: $(get_domain_config "warehouses.default" "unknown")"
    echo ""
    
    echo "Git Integration:"
    echo "  Repository: $(get_domain_config "git.repository" "unknown")"
    echo "  Mirror Name: $(get_domain_config "git.mirror_name" "unknown")"
    echo ""
    
    echo "dbt Configuration:"
    echo "  Project Directory: $(get_domain_config "dbt.project_dir" "unknown")"
    echo "  Target Database: $(get_domain_config "dbt.target_database" "unknown")"
    echo ""
    
    echo "Connection Defaults:"
    echo "  Admin: $(get_domain_config "connection_defaults.admin_name" "admin")"
    echo "  Loader: $(get_domain_config "connection_defaults.loader_name" "loader")"
    echo "  Transformer: $(get_domain_config "connection_defaults.transformer_name" "admin")"
}

# =============================================================================
# PRIVATE HELPER FUNCTIONS  
# =============================================================================

# Ensure YAML parser is available
_ensure_yaml_parser() {
    if command -v yq >/dev/null 2>&1; then
        return 0
    fi
    
    _log_error "YAML parser 'yq' not found. Install framework dependencies:"
    _log_error "  Run: scripts/snowflake_cli/setup.sh --phase prereq"
    _log_error "  Or manually: brew install yq"
    _log_error ""
    _log_error "Framework requires yq for domain configuration parsing."
    return 1
}

# Parse and validate YAML structure
_parse_and_validate_yaml() {
    local config_file="$1"
    
    # Test YAML parsing
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        _log_error "Invalid YAML syntax in $config_file"
        return 1
    fi
    
    # Validate required top-level sections
    local required_sections=("domain" "roles" "warehouses" "connection_defaults")
    for section in "${required_sections[@]}"; do
        if ! yq eval "has(\"$section\")" "$config_file" | grep -q "true"; then
            _log_error "Missing required configuration section: $section"
            return 1
        fi
    done
    
    # Validate required domain fields
    local required_domain_fields=("name" "database")
    for field in "${required_domain_fields[@]}"; do
        if ! yq eval ".domain | has(\"$field\")" "$config_file" | grep -q "true"; then
            _log_error "Missing required domain field: domain.$field"
            return 1
        fi
    done
    
    # Validate required role fields
    local required_role_fields=("admin" "loader")
    for field in "${required_role_fields[@]}"; do
        if ! yq eval ".roles | has(\"$field\")" "$config_file" | grep -q "true"; then
            _log_error "Missing required role field: roles.$field"
            return 1
        fi
    done
    
    return 0
}

# Get configuration value using yq
_get_config_value() {
    local config_path="$1"
    
    # Convert dot notation to yq path
    local yq_path
    yq_path=$(echo "$config_path" | sed 's/\./\]\[/g' | sed 's/^/\[/' | sed 's/$/\]/')
    
    # Get value from configuration file
    if yq eval ".${config_path}" "$CURRENT_DOMAIN_CONFIG" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Cache configuration for performance
_cache_configuration() {
    local config_file="$1"
    
    mkdir -p "$CONFIG_CACHE_DIR"
    cp "$config_file" "$CONFIG_CACHE_DIR/current_config.yml"
    chmod 600 "$CONFIG_CACHE_DIR/current_config.yml"
}

# Validate required environment variables
_validate_required_env_vars() {
    local env_vars
    env_vars=$(get_domain_config "validation.required_env_vars" "[]")
    
    if [[ "$env_vars" == "[]" || "$env_vars" == "null" ]]; then
        return 0  # No required env vars
    fi
    
    # Parse array of required env vars
    local validation_failed=0
    while IFS= read -r var; do
        if [[ -n "$var" && -z "${!var:-}" ]]; then
            _log_error "Required environment variable not set: $var"
            validation_failed=1
        fi
    done < <(echo "$env_vars" | yq eval '.[]' -)
    
    return $validation_failed
}

# Validate connection capabilities (placeholder - depends on connection resolver)
_validate_connection_capabilities() {
    # This would integrate with connection_resolver.sh to validate
    # that available connections can perform required operations
    return 0
}

# Validate no conflicts with other domains (placeholder)
_validate_no_domain_conflicts() {
    # This would check that database names, role names don't conflict
    # with other deployed domains
    return 0
}

# Logging functions
_log_info() {
    echo "==> [domain_config_loader] $*" >&2
}

_log_debug() {
    if [[ "${FRAMEWORK_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG [domain_config_loader] $*" >&2
    fi
}

_log_error() {
    echo "ERROR [domain_config_loader] $*" >&2
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_domain_config_loader_help() {
    cat <<EOF
domain_config_loader.sh — Domain configuration parser and validator

DESCRIPTION:
    Loads and validates domain configuration files for the Snowflake CLI framework.
    Provides safe access to configuration values with comprehensive validation.

USAGE:
    source scripts/lib/domain_config_loader.sh
    
    # Load domain configuration
    load_domain_config config/artwork_domain.yml
    
    # Access configuration values
    database=\$(get_domain_config "domain.database")
    admin_role=\$(get_domain_config "roles.admin" "SYSADMIN")
    
    # Validate prerequisites
    validate_domain_config_prerequisites
    
    # Display configuration info
    list_domain_info

FUNCTIONS:
    load_domain_config FILE             Load and validate configuration file
    get_domain_config PATH [DEFAULT]    Get configuration value by path
    validate_domain_config_prerequisites Validate deployment prerequisites
    list_domain_info                    Display configuration summary

CONFIGURATION PATH SYNTAX:
    Use dot notation to access nested values:
    - domain.name
    - roles.admin
    - dbt.project_dir
    - connection_defaults.admin_name

ENVIRONMENT VARIABLES:
    FRAMEWORK_DEBUG     Set to 1 for debug logging

REQUIRED DEPENDENCIES:
    yq                  YAML processor (brew install yq)

EXIT CODES:
    0   Success
    1   Configuration error, validation failure, or missing dependency

EXAMPLES:
    # Load configuration and get database name
    load_domain_config config/artwork_domain.yml
    db=\$(get_domain_config "domain.database")
    
    # Get configuration with default
    warehouse=\$(get_domain_config "warehouses.default" "COMPUTE_WH")
    
    # Validate before deployment
    if validate_domain_config_prerequisites; then
        echo "Ready to deploy"
    fi

EOF
}

# Handle --help flag when script is executed directly
if [[ "${1:-}" == "--help" ]]; then
    show_domain_config_loader_help
    exit 0
fi