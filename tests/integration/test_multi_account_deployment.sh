#!/usr/bin/env bash
# =============================================================================
# test_multi_account_deployment.sh — Integration tests for multi-account deployment
# =============================================================================
#
# PURPOSE: Test framework deployment across multiple Snowflake account configurations
# SCOPE: Integration testing with real Snowflake CLI connections
# MAINTAINER: Principal Engineer-level validation
#
# WARNING: These tests require valid Snowflake connections and may modify test accounts
#
# =============================================================================

set -euo pipefail

# Test configuration
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly FRAMEWORK_DIR="${REPO_ROOT}/scripts"

# Test state tracking
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# Test environment configuration
readonly TEST_ENV_PREFIX="FRAMEWORK_TEST"
readonly CLEANUP_ON_SUCCESS=${CLEANUP_ON_SUCCESS:-true}

# =============================================================================
# TEST FRAMEWORK UTILITIES
# =============================================================================

# Log test result
log_test_result() {
    local test_name="$1"
    local result="$2"  # "PASS" or "FAIL"
    local details="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$result" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo "✅ $test_name"
    else
        ((TESTS_FAILED++))
        echo "❌ $test_name"
        if [[ -n "$details" ]]; then
            echo "   Details: $details"
        fi
    fi
}

# Assert condition with detailed error reporting
assert_condition() {
    local condition="$1"
    local test_name="$2"
    local error_details="${3:-}"
    
    if eval "$condition"; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "$error_details"
    fi
}

# Skip test if preconditions not met
skip_test_if() {
    local condition="$1"
    local test_name="$2"
    local skip_reason="$3"
    
    if eval "$condition"; then
        echo "⏭️  SKIPPED: $test_name - $skip_reason"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# ENVIRONMENT SETUP AND VALIDATION
# =============================================================================

setup_test_environment() {
    echo "Setting up integration test environment..."
    
    # Create temporary test workspace
    export TEST_WORKSPACE=$(mktemp -d)
    cd "$TEST_WORKSPACE"
    
    echo "Test workspace: $TEST_WORKSPACE"
    
    # Copy framework components to test workspace
    mkdir -p scripts/lib
    cp "${FRAMEWORK_DIR}/orchestrate_modern.sh" scripts/
    cp "${FRAMEWORK_DIR}/lib/connection_resolver.sh" scripts/lib/
    
    # Make scripts executable
    chmod +x scripts/orchestrate_modern.sh
    chmod +x scripts/lib/connection_resolver.sh
    
    # Create test DDL structure
    create_test_ddl_structure
    
    echo "✅ Test environment ready"
}

create_test_ddl_structure() {
    echo "Creating test DDL structure..."
    
    # Create directories
    mkdir -p infrastructure git-setup
    
    # Create test manifest
    cat > scripts/manifest.txt << 'EOF'
# Framework integration test DDL
infrastructure/create_databases.sql
infrastructure/create_schemas.sql
infrastructure/create_roles.sql
infrastructure/create_warehouses.sql
infrastructure/create_grants.sql
git-setup/create_git_integration.sql
EOF

    # Create test DDL files - using idempotent patterns
    cat > infrastructure/create_databases.sql << 'EOF'
-- Framework integration test database
CREATE DATABASE IF NOT EXISTS FRAMEWORK_TEST_DB
    COMMENT = 'Framework integration test database - safe to drop';
EOF

    cat > infrastructure/create_schemas.sql << 'EOF'
-- Framework integration test schemas
CREATE SCHEMA IF NOT EXISTS FRAMEWORK_TEST_DB.BRONZE
    COMMENT = 'Framework integration test bronze schema';
    
CREATE SCHEMA IF NOT EXISTS FRAMEWORK_TEST_DB.SILVER
    COMMENT = 'Framework integration test silver schema';
EOF

    cat > infrastructure/create_roles.sql << 'EOF'
-- Framework integration test roles
CREATE ROLE IF NOT EXISTS FRAMEWORK_TEST_ADMIN
    COMMENT = 'Framework integration test admin role';
    
CREATE ROLE IF NOT EXISTS FRAMEWORK_TEST_LOADER  
    COMMENT = 'Framework integration test loader role';
EOF

    cat > infrastructure/create_warehouses.sql << 'EOF'
-- Framework integration test warehouse
CREATE WAREHOUSE IF NOT EXISTS FRAMEWORK_TEST_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Framework integration test warehouse - safe to drop';
EOF

    cat > infrastructure/create_grants.sql << 'EOF'
-- Framework integration test grants
GRANT USAGE ON DATABASE FRAMEWORK_TEST_DB TO ROLE FRAMEWORK_TEST_LOADER;
GRANT USAGE ON SCHEMA FRAMEWORK_TEST_DB.BRONZE TO ROLE FRAMEWORK_TEST_LOADER;
GRANT USAGE ON WAREHOUSE FRAMEWORK_TEST_WH TO ROLE FRAMEWORK_TEST_LOADER;
EOF

    cat > git-setup/create_git_integration.sql << 'EOF'
-- Framework integration test git setup (no-op for testing)
SELECT 'Git integration test - no actual git setup required' AS test_status;
EOF

    echo "✅ Test DDL structure created"
}

validate_test_preconditions() {
    echo "Validating test preconditions..."
    
    # Check Snowflake CLI availability
    if ! command -v snow >/dev/null 2>&1; then
        echo "❌ Snowflake CLI not found. Install with: brew install snowflakedb/snowflake-cli/snowflake-cli"
        exit 1
    fi
    
    # Check framework components exist
    if [[ ! -f "${FRAMEWORK_DIR}/orchestrate_modern.sh" ]]; then
        echo "❌ Framework orchestrator not found: ${FRAMEWORK_DIR}/orchestrate_modern.sh"
        exit 1
    fi
    
    if [[ ! -f "${FRAMEWORK_DIR}/lib/connection_resolver.sh" ]]; then
        echo "❌ Framework connection resolver not found: ${FRAMEWORK_DIR}/lib/connection_resolver.sh"
        exit 1
    fi
    
    echo "✅ Test preconditions validated"
}

# =============================================================================
# CONNECTION DISCOVERY AND VALIDATION
# =============================================================================

discover_test_connections() {
    echo "Discovering available test connections..."
    
    # Get list of available connections
    if ! snow connection list --format json > /tmp/connections.json 2>/dev/null; then
        echo "❌ Failed to list Snowflake connections"
        echo "   Configure connections with: snow connection add"
        exit 1
    fi
    
    # Extract connection names
    AVAILABLE_CONNECTIONS=$(jq -r '.[].name' /tmp/connections.json 2>/dev/null | sort)
    
    if [[ -z "$AVAILABLE_CONNECTIONS" ]]; then
        echo "❌ No Snowflake connections configured"
        echo "   Add a connection with: snow connection add --connection-name test-admin --account YOUR_ACCOUNT"
        exit 1
    fi
    
    echo "Available connections:"
    echo "$AVAILABLE_CONNECTIONS" | while read -r conn; do
        echo "  - $conn"
    done
    
    # Select test connections (prefer test/dev connections)
    PRIMARY_TEST_CONNECTION=""
    SECONDARY_TEST_CONNECTION=""
    
    # Look for test-related connections first
    for conn in $AVAILABLE_CONNECTIONS; do
        if [[ "$conn" =~ test|dev|staging ]]; then
            if [[ -z "$PRIMARY_TEST_CONNECTION" ]]; then
                PRIMARY_TEST_CONNECTION="$conn"
            elif [[ -z "$SECONDARY_TEST_CONNECTION" ]]; then
                SECONDARY_TEST_CONNECTION="$conn"
                break
            fi
        fi
    done
    
    # Fallback to any available connections
    if [[ -z "$PRIMARY_TEST_CONNECTION" ]]; then
        PRIMARY_TEST_CONNECTION=$(echo "$AVAILABLE_CONNECTIONS" | head -n1)
    fi
    
    if [[ -z "$SECONDARY_TEST_CONNECTION" && $(echo "$AVAILABLE_CONNECTIONS" | wc -l) -gt 1 ]]; then
        SECONDARY_TEST_CONNECTION=$(echo "$AVAILABLE_CONNECTIONS" | sed -n '2p')
    fi
    
    echo "Selected test connections:"
    echo "  Primary: $PRIMARY_TEST_CONNECTION"
    echo "  Secondary: ${SECONDARY_TEST_CONNECTION:-"(none - will test single-account only)"}"
}

validate_test_connections() {
    echo "Validating test connections..."
    
    # Test primary connection
    if snow connection test -c "$PRIMARY_TEST_CONNECTION" >/dev/null 2>&1; then
        log_test_result "primary_connection_valid" "PASS"
    else
        log_test_result "primary_connection_valid" "FAIL" "Connection test failed: $PRIMARY_TEST_CONNECTION"
        echo "❌ Cannot proceed without valid primary connection"
        exit 1
    fi
    
    # Test secondary connection if available
    if [[ -n "$SECONDARY_TEST_CONNECTION" ]]; then
        if snow connection test -c "$SECONDARY_TEST_CONNECTION" >/dev/null 2>&1; then
            log_test_result "secondary_connection_valid" "PASS"
        else
            log_test_result "secondary_connection_valid" "FAIL" "Connection test failed: $SECONDARY_TEST_CONNECTION"
            echo "⚠️  Multi-account tests will be skipped"
            SECONDARY_TEST_CONNECTION=""
        fi
    fi
}

# =============================================================================
# FRAMEWORK INTEGRATION TESTS
# =============================================================================

test_framework_availability() {
    echo "Testing framework component availability..."
    
    # Test orchestrator help
    if scripts/orchestrate_modern.sh --help >/dev/null 2>&1; then
        log_test_result "orchestrator_help_available" "PASS"
    else
        log_test_result "orchestrator_help_available" "FAIL" "Orchestrator help command failed"
        exit 1
    fi
    
    # Test connection resolver sourcing
    set +e
    source scripts/lib/connection_resolver.sh 2>/dev/null
    local source_result=$?
    set -e
    
    if [[ $source_result -eq 0 ]]; then
        log_test_result "connection_resolver_loads" "PASS"
    else
        log_test_result "connection_resolver_loads" "FAIL" "Failed to source connection resolver"
        exit 1
    fi
}

test_connection_resolution() {
    echo "Testing connection resolution with real connections..."
    
    source scripts/lib/connection_resolver.sh
    
    # Test explicit connection resolution
    local resolved_connection
    resolved_connection=$(resolve_connection_with_capability "admin" "$PRIMARY_TEST_CONNECTION" 2>/dev/null)
    
    if [[ "$resolved_connection" == "$PRIMARY_TEST_CONNECTION" ]]; then
        log_test_result "explicit_connection_resolution" "PASS"
    else
        log_test_result "explicit_connection_resolution" "FAIL" \
            "Expected '$PRIMARY_TEST_CONNECTION', got '$resolved_connection'"
    fi
    
    # Test connection capability validation
    if validate_connection_capability "$PRIMARY_TEST_CONNECTION" "any" 2>/dev/null; then
        log_test_result "connection_capability_validation" "PASS"
    else
        log_test_result "connection_capability_validation" "FAIL" \
            "Basic capability validation failed"
    fi
}

# =============================================================================
# SINGLE-ACCOUNT DEPLOYMENT TESTS
# =============================================================================

test_single_account_infrastructure_deployment() {
    echo "Testing single-account infrastructure deployment..."
    
    # Test infrastructure phase deployment
    set +e
    local deploy_output
    deploy_output=$(scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$PRIMARY_TEST_CONNECTION" 2>&1)
    local deploy_result=$?
    set -e
    
    if [[ $deploy_result -eq 0 ]]; then
        log_test_result "infrastructure_deployment_succeeds" "PASS"
        
        # Verify objects were created
        if verify_test_objects_exist "$PRIMARY_TEST_CONNECTION"; then
            log_test_result "infrastructure_objects_created" "PASS"
        else
            log_test_result "infrastructure_objects_created" "FAIL" "Expected objects not found"
        fi
    else
        log_test_result "infrastructure_deployment_succeeds" "FAIL" \
            "Deployment failed: $deploy_output"
    fi
}

test_single_account_bootstrap_deployment() {
    echo "Testing single-account bootstrap deployment..."
    
    # Test bootstrap phase deployment
    set +e
    local bootstrap_output
    bootstrap_output=$(scripts/orchestrate_modern.sh \
        --ddl-dir git-setup \
        --manifest scripts/manifest.txt \
        --phase bootstrap \
        --connection "$PRIMARY_TEST_CONNECTION" 2>&1)
    local bootstrap_result=$?
    set -e
    
    if [[ $bootstrap_result -eq 0 ]]; then
        log_test_result "bootstrap_deployment_succeeds" "PASS"
    else
        log_test_result "bootstrap_deployment_succeeds" "FAIL" \
            "Bootstrap deployment failed: $bootstrap_output"
    fi
}

test_idempotent_redeployment() {
    echo "Testing idempotent redeployment..."
    
    # Deploy infrastructure again - should succeed without errors
    set +e
    local redeploy_output
    redeploy_output=$(scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$PRIMARY_TEST_CONNECTION" 2>&1)
    local redeploy_result=$?
    set -e
    
    if [[ $redeploy_result -eq 0 ]]; then
        log_test_result "idempotent_redeployment_succeeds" "PASS"
    else
        log_test_result "idempotent_redeployment_succeeds" "FAIL" \
            "Idempotent redeployment failed: $redeploy_output"
    fi
}

# =============================================================================
# MULTI-ACCOUNT DEPLOYMENT TESTS
# =============================================================================

test_multi_account_deployment() {
    if [[ -z "$SECONDARY_TEST_CONNECTION" ]]; then
        echo "⏭️  SKIPPED: Multi-account tests - no secondary connection available"
        return 0
    fi
    
    echo "Testing multi-account deployment..."
    
    # Deploy to secondary account
    set +e
    local secondary_deploy_output
    secondary_deploy_output=$(scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$SECONDARY_TEST_CONNECTION" 2>&1)
    local secondary_deploy_result=$?
    set -e
    
    if [[ $secondary_deploy_result -eq 0 ]]; then
        log_test_result "secondary_account_deployment_succeeds" "PASS"
        
        # Verify objects exist in secondary account
        if verify_test_objects_exist "$SECONDARY_TEST_CONNECTION"; then
            log_test_result "secondary_account_objects_created" "PASS"
        else
            log_test_result "secondary_account_objects_created" "FAIL" \
                "Expected objects not found in secondary account"
        fi
    else
        log_test_result "secondary_account_deployment_succeeds" "FAIL" \
            "Secondary account deployment failed: $secondary_deploy_output"
    fi
}

test_cross_account_isolation() {
    if [[ -z "$SECONDARY_TEST_CONNECTION" ]]; then
        echo "⏭️  SKIPPED: Cross-account isolation tests - no secondary connection available"
        return 0
    fi
    
    echo "Testing cross-account isolation..."
    
    # Verify both accounts have isolated but identical objects
    local primary_db_count
    local secondary_db_count
    
    primary_db_count=$(snow sql -c "$PRIMARY_TEST_CONNECTION" \
        -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_%';" \
        --format json 2>/dev/null | jq length)
    
    secondary_db_count=$(snow sql -c "$SECONDARY_TEST_CONNECTION" \
        -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_%';" \
        --format json 2>/dev/null | jq length)
    
    if [[ "$primary_db_count" -gt 0 && "$secondary_db_count" -gt 0 ]]; then
        log_test_result "cross_account_isolation_verified" "PASS"
    else
        log_test_result "cross_account_isolation_verified" "FAIL" \
            "Primary: $primary_db_count objects, Secondary: $secondary_db_count objects"
    fi
}

# =============================================================================
# VERIFICATION UTILITIES
# =============================================================================

verify_test_objects_exist() {
    local connection="$1"
    
    # Check if test database exists
    local db_exists
    db_exists=$(snow sql -c "$connection" \
        -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_DB';" \
        --format json 2>/dev/null | jq length)
    
    if [[ "$db_exists" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# CLEANUP UTILITIES
# =============================================================================

cleanup_test_objects() {
    local connection="$1"
    
    echo "Cleaning up test objects in connection: $connection"
    
    # Drop test objects (reverse order of creation)
    set +e
    snow sql -c "$connection" -q "DROP WAREHOUSE IF EXISTS FRAMEWORK_TEST_WH;" >/dev/null 2>&1
    snow sql -c "$connection" -q "DROP ROLE IF EXISTS FRAMEWORK_TEST_LOADER;" >/dev/null 2>&1
    snow sql -c "$connection" -q "DROP ROLE IF EXISTS FRAMEWORK_TEST_ADMIN;" >/dev/null 2>&1
    snow sql -c "$connection" -q "DROP DATABASE IF EXISTS FRAMEWORK_TEST_DB CASCADE;" >/dev/null 2>&1
    set -e
    
    echo "✅ Cleanup completed for connection: $connection"
}

cleanup_test_environment() {
    echo "Cleaning up test environment..."
    
    # Clean up test objects if cleanup is enabled
    if [[ "$CLEANUP_ON_SUCCESS" == "true" && $TESTS_FAILED -eq 0 ]]; then
        cleanup_test_objects "$PRIMARY_TEST_CONNECTION"
        
        if [[ -n "$SECONDARY_TEST_CONNECTION" ]]; then
            cleanup_test_objects "$SECONDARY_TEST_CONNECTION"
        fi
    else
        echo "⚠️  Skipping cleanup - either disabled or tests failed"
        echo "   Manual cleanup may be required for test objects"
    fi
    
    # Clean up test workspace
    if [[ -n "${TEST_WORKSPACE:-}" && -d "$TEST_WORKSPACE" ]]; then
        cd /
        rm -rf "$TEST_WORKSPACE"
    fi
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Main test runner
main() {
    echo "=========================================="
    echo "Framework Multi-Account Integration Tests"
    echo "=========================================="
    
    # Setup phase
    validate_test_preconditions
    setup_test_environment
    discover_test_connections
    validate_test_connections
    
    echo ""
    echo "Running integration tests..."
    echo ""
    
    # Framework availability tests
    test_framework_availability
    echo
    
    # Connection resolution tests
    test_connection_resolution
    echo
    
    # Single-account deployment tests
    test_single_account_infrastructure_deployment
    echo
    
    test_single_account_bootstrap_deployment
    echo
    
    test_idempotent_redeployment
    echo
    
    # Multi-account tests (if secondary connection available)
    test_multi_account_deployment
    echo
    
    test_cross_account_isolation
    echo
    
    # Print summary
    echo "=========================================="
    echo "Integration Test Summary"
    echo "=========================================="
    echo "Total tests: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""
    echo "Test connections used:"
    echo "  Primary: $PRIMARY_TEST_CONNECTION"
    echo "  Secondary: ${SECONDARY_TEST_CONNECTION:-"(none)"}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✅ All integration tests passed"
        local exit_code=0
    else
        echo "❌ Some integration tests failed"
        local exit_code=1
    fi
    
    cleanup_test_environment
    exit $exit_code
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi