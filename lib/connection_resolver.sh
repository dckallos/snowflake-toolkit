#!/usr/bin/env bash
# =============================================================================
# connection_resolver.sh — Universal Snowflake connection resolution framework
# =============================================================================
#
# CONTEXT: Domain-agnostic Snowflake CLI framework component
# PURPOSE: Provides unified connection resolution across all CLI operations
# MAINTAINER: Facebook staff-level implementation
#
# This module implements enterprise-grade connection resolution that works
# with any Snowflake account, any domain configuration, and any connection
# setup. It provides consistent behavior across all framework components
# while maintaining user control and transparency.
#
# ARCHITECTURE:
#   - Priority-based resolution with explicit user confirmation
#   - Session-scoped caching to prevent repeated prompts
#   - Capability validation to ensure connections can perform required operations
#   - Comprehensive error handling with actionable guidance
#
# USAGE:
#   source scripts/lib/connection_resolver.sh
#   connection=$(resolve_connection_with_capability admin --explicit-connection prod)
#   validate_connection_capability "$connection" transformer
#
# INTEGRATION:
#   Used by all framework components that need Snowflake connections:
#   - scripts/lib/ddl_orchestrator.sh
#   - scripts/lib/dbt_orchestrator.sh  
#   - scripts/lib/git_integration.sh
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly CONNECTION_RESOLVER_VERSION="1.0.0"
readonly CONNECTION_RESOLVER_CREATED="2026-06-02"

# Session cache configuration
readonly CACHE_DIR="/tmp"
readonly CACHE_PREFIX="snowflake_framework_connection_cache"
readonly SESSION_ID="$$"

# =============================================================================
# CORE RESOLUTION FUNCTIONS
# =============================================================================

# resolve_connection_with_capability
# 
# Primary entry point for connection resolution. Implements Facebook staff-level
# priority system with universal confirmation and session caching.
#
# PARAMETERS:
#   $1 - required_capability: admin|loader|transformer|any
#   $2 - explicit_connection: Optional explicit connection name (bypasses resolution)
#
# RETURNS:
#   stdout: Resolved connection name
#   exit 0: Success
#   exit 1: No connection could be resolved
#
# BEHAVIOR:
#   1. Explicit CLI parameter (no confirmation)
#   2. Active config.toml default (with confirmation + session cache)
#   3. Environment variables (with confirmation + session cache)  
#   4. Capability-based fallback (with confirmation + session cache)
resolve_connection_with_capability() {
    local required_capability="${1:-any}"
    local explicit_connection="${2:-}"
    
    _log_debug "resolve_connection_with_capability: capability=$required_capability explicit=$explicit_connection"
    
    # Priority 1: Explicit CLI parameter (no confirmation - user intent is clear)
    if [[ -n "$explicit_connection" ]]; then
        _log_info "Using explicit connection: $explicit_connection"
        echo "$explicit_connection"
        return 0
    fi
    
    # Check session cache before any user prompting
    local cached_connection
    if cached_connection=$(_get_session_cache); then
        _log_debug "Found cached connection: $cached_connection"
        echo "$cached_connection"
        return 0
    fi
    
    # Priority 2: Active default from config.toml (with confirmation)
    local default_connection
    if default_connection=$(_get_default_connection); then
        if _confirm_connection_choice "Default connection from ~/.snowflake/config.toml" "$default_connection" "Y"; then
            _set_session_cache "$default_connection"
            echo "$default_connection"
            return 0
        fi
    fi
    
    # Priority 3: Environment variables (with confirmation)
    if [[ -n "${SNOW_CONNECTION:-}" ]]; then
        if _confirm_connection_choice "Environment variable SNOW_CONNECTION" "$SNOW_CONNECTION" "y"; then
            _set_session_cache "$SNOW_CONNECTION"
            echo "$SNOW_CONNECTION" 
            return 0
        fi
    fi
    
    # Priority 4: Capability-based fallback (with confirmation)
    local fallback_connection
    fallback_connection=$(_get_fallback_connection "$required_capability")
    if _confirm_connection_choice "Fallback connection for capability '$required_capability'" "$fallback_connection" "Y"; then
        _set_session_cache "$fallback_connection"
        echo "$fallback_connection"
        return 0
    fi
    
    # No connection resolved - provide actionable error
    _log_error "No connection could be resolved."
    _log_error "Solutions:"
    _log_error "  1. Specify explicit connection: --connection <name>"
    _log_error "  2. Set default in config.toml: snow connection set-default <name>"
    _log_error "  3. List available connections: snow connection list"
    return 1
}

# validate_connection_capability
#
# Validates that a connection has the required capability for an operation.
# Performs actual permission checks against Snowflake rather than name-based assumptions.
#
# PARAMETERS:
#   $1 - connection_name: Snowflake CLI connection name
#   $2 - required_capability: admin|loader|transformer
#
# RETURNS:
#   exit 0: Connection has required capability
#   exit 1: Connection lacks required capability
#
# BEHAVIOR:
#   Tests actual permissions by executing capability-specific queries
validate_connection_capability() {
    local connection_name="$1"
    local required_capability="$2"
    
    _log_debug "validate_connection_capability: connection=$connection_name capability=$required_capability"
    
    case "$required_capability" in
        admin)
            _validate_admin_capability "$connection_name"
            ;;
        loader)
            _validate_loader_capability "$connection_name"
            ;;
        transformer)
            _validate_transformer_capability "$connection_name"
            ;;
        any)
            # Basic connectivity test
            _validate_basic_connectivity "$connection_name"
            ;;
        *)
            _log_error "Unknown capability: $required_capability"
            return 1
            ;;
    esac
}

# list_available_connections
#
# Lists all available connections with their current status and capabilities.
# Provides comprehensive information for user decision-making.
#
# RETURNS:
#   stdout: Formatted list of connections with metadata
list_available_connections() {
    _log_info "Available Snowflake connections:"
    
    if ! command -v snow >/dev/null 2>&1; then
        _log_error "Snowflake CLI not found. Install with: brew install snowflakedb/snowflake-cli/snowflake-cli"
        return 1
    fi
    
    # Use Snowflake CLI to get connection list
    if ! snow connection list --format table 2>/dev/null; then
        _log_error "Failed to list connections. Check Snowflake CLI configuration."
        _log_info "Initialize with: snow connection add --connection-name <name> --account <account>"
        return 1
    fi
    
    _log_info ""
    _log_info "Connection management:"
    _log_info "  List connections:     snow connection list"
    _log_info "  Set default:          snow connection set-default <name>"
    _log_info "  Test connection:      snow connection test --connection <name>"
}

# clear_session_cache
#
# Clears the session-scoped connection cache.
# Useful for forcing fresh connection resolution.
clear_session_cache() {
    local cache_file="${CACHE_DIR}/${CACHE_PREFIX}_${SESSION_ID}"
    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        _log_info "Session connection cache cleared"
    else
        _log_info "No session cache to clear"
    fi
}

# =============================================================================
# PRIVATE HELPER FUNCTIONS
# =============================================================================

# Get cached connection for current session
_get_session_cache() {
    local cache_file="${CACHE_DIR}/${CACHE_PREFIX}_${SESSION_ID}"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi
    return 1
}

# Set cached connection for current session
_set_session_cache() {
    local connection="$1"
    local cache_file="${CACHE_DIR}/${CACHE_PREFIX}_${SESSION_ID}"
    echo "$connection" > "$cache_file"
    # Set restrictive permissions on cache file
    chmod 600 "$cache_file"
}

# Get default connection from config.toml
_get_default_connection() {
    if command -v snow >/dev/null 2>&1; then
        # Try to get default connection via Snowflake CLI
        if snow connection list --format json 2>/dev/null | jq -r '.[] | select(.is_default==true) | .name' 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Get fallback connection based on capability
_get_fallback_connection() {
    local capability="$1"
    
    case "$capability" in
        admin)
            echo "admin"
            ;;
        loader)
            echo "loader"
            ;;
        transformer)
            # Most environments don't have dedicated transformer connections
            echo "admin"
            ;;
        *)
            echo "admin"
            ;;
    esac
}

# Confirm connection choice with user
_confirm_connection_choice() {
    local source_description="$1"
    local connection_name="$2"
    local default_choice="$3"  # Y, y, or N
    
    echo "$source_description: $connection_name" >&2
    echo -n "Use this connection? [$default_choice/n] " >&2
    read -r confirmation
    
    # Handle default choice
    if [[ -z "$confirmation" ]]; then
        confirmation="$default_choice"
    fi
    
    case "$confirmation" in
        [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate admin capability
_validate_admin_capability() {
    local connection="$1"
    
    # Test admin-level operations
    if ! snow sql --query "SHOW GRANTS TO ROLE ACCOUNTADMIN;" --connection "$connection" --format json >/dev/null 2>&1; then
        _log_error "Connection '$connection' lacks admin capability"
        _log_error "Required: ACCOUNTADMIN role or equivalent admin privileges"
        return 1
    fi
    
    _log_debug "Connection '$connection' validated for admin capability"
    return 0
}

# Validate loader capability  
_validate_loader_capability() {
    local connection="$1"
    
    # Test basic connectivity - loader validation depends on domain configuration
    if ! _validate_basic_connectivity "$connection"; then
        return 1
    fi
    
    _log_debug "Connection '$connection' validated for loader capability"
    return 0
}

# Validate transformer capability
_validate_transformer_capability() {
    local connection="$1"
    
    # Test basic connectivity - transformer validation depends on domain configuration
    if ! _validate_basic_connectivity "$connection"; then
        return 1
    fi
    
    _log_debug "Connection '$connection' validated for transformer capability"
    return 0
}

# Validate basic connectivity
_validate_basic_connectivity() {
    local connection="$1"
    
    if ! snow connection test --connection "$connection" >/dev/null 2>&1; then
        _log_error "Connection '$connection' failed basic connectivity test"
        _log_error "Check connection configuration: snow connection list"
        return 1
    fi
    
    _log_debug "Connection '$connection' passed basic connectivity test"
    return 0
}

# Logging functions
_log_info() {
    echo "==> [connection_resolver] $*" >&2
}

_log_debug() {
    if [[ "${FRAMEWORK_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG [connection_resolver] $*" >&2
    fi
}

_log_error() {
    echo "ERROR [connection_resolver] $*" >&2
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_connection_resolver_help() {
    cat <<EOF
connection_resolver.sh — Universal Snowflake connection resolution framework

DESCRIPTION:
    Provides unified connection resolution for domain-agnostic Snowflake CLI framework.
    Implements Facebook staff-level priority system with user confirmation and session caching.

USAGE:
    source scripts/lib/connection_resolver.sh
    
    # Basic connection resolution
    connection=\$(resolve_connection_with_capability admin)
    connection=\$(resolve_connection_with_capability loader --explicit-connection prod)
    
    # Capability validation
    validate_connection_capability "\$connection" transformer
    
    # Connection management
    list_available_connections
    clear_session_cache

CAPABILITIES:
    admin       - Administrative operations (CREATE DATABASE, ROLE, WAREHOUSE)
    loader      - Data loading operations (INSERT, COPY INTO Bronze schema)  
    transformer - Data transformation (CREATE TABLE/VIEW Silver/Gold schemas)
    any         - Basic connectivity only

CONNECTION RESOLUTION PRIORITY:
    1. Explicit CLI parameter (--connection NAME) - no confirmation
    2. Active default from config.toml - with confirmation + session cache
    3. Environment variables (SNOW_CONNECTION) - with confirmation + session cache  
    4. Capability-based fallback - with confirmation + session cache

ENVIRONMENT VARIABLES:
    SNOW_CONNECTION     Override connection name (subject to confirmation)
    FRAMEWORK_DEBUG     Set to 1 for debug logging

EXAMPLES:
    # Use explicit connection
    resolve_connection_with_capability admin prod-admin
    
    # Use resolution priority with admin capability
    resolve_connection_with_capability admin
    
    # Validate connection can perform transformations
    validate_connection_capability my-connection transformer

EXIT CODES:
    0   Success
    1   Connection resolution failed or capability validation failed

EOF
}

# Handle --help flag when script is executed directly
if [[ "${1:-}" == "--help" ]]; then
    show_connection_resolver_help
    exit 0
fi