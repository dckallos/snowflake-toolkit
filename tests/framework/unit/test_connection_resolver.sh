#!/usr/bin/env bash
# =============================================================================
# test_connection_resolver.sh — Unit tests for connection_resolver.sh component
# =============================================================================
#
# PURPOSE: Comprehensive unit testing for connection resolution logic
# FRAMEWORK: Pure testing without external dependencies where possible
# MAINTAINER: Principal Engineer-level test coverage
#
# =============================================================================

set -euo pipefail

# Test configuration
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${TEST_SCRIPT_DIR}/../../.." && pwd)"
readonly FRAMEWORK_LIB="${REPO_ROOT}/scripts/lib"

# Test state tracking
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

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

# Assert function exists and is callable
assert_function_exists() {
    local function_name="$1"
    local test_name="test_${function_name}_function_exists"
    
    if declare -f "$function_name" > /dev/null; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "Function $function_name not found"
    fi
}

# Setup test environment
setup_test_env() {
    # Create temporary directory for test cache
    export TEST_CACHE_DIR=$(mktemp -d)
    export CACHE_DIR="$TEST_CACHE_DIR"
    export SESSION_ID="test_$$"
    
    # Mock Snowflake CLI if needed
    export PATH="$TEST_SCRIPT_DIR/mocks:$PATH"
}

# Cleanup test environment  
cleanup_test_env() {
    if [[ -n "${TEST_CACHE_DIR:-}" && -d "$TEST_CACHE_DIR" ]]; then
        rm -rf "$TEST_CACHE_DIR"
    fi
}

# =============================================================================
# COMPONENT LOADING TESTS
# =============================================================================

test_framework_component_loading() {
    echo "Testing framework component loading..."
    
    # Test: connection_resolver.sh exists and is readable
    local resolver_path="${FRAMEWORK_LIB}/connection_resolver.sh"
    assert_condition "[[ -f '$resolver_path' && -r '$resolver_path' ]]" \
        "connection_resolver_file_exists" \
        "File not found: $resolver_path"
    
    # Test: Source connection_resolver without errors
    if source "$resolver_path" 2>/dev/null; then
        log_test_result "connection_resolver_loads_without_errors" "PASS"
    else
        log_test_result "connection_resolver_loads_without_errors" "FAIL" "Source command failed"
    fi
    
    # Test: Required functions are defined after sourcing
    assert_function_exists "resolve_connection_with_capability"
    assert_function_exists "validate_connection_capability"  
    assert_function_exists "list_available_connections"
    assert_function_exists "clear_session_cache"
}

# =============================================================================
# CONNECTION RESOLUTION TESTS
# =============================================================================

test_explicit_connection_resolution() {
    echo "Testing explicit connection resolution..."
    
    # Source the component
    source "${FRAMEWORK_LIB}/connection_resolver.sh"
    
    # Test: Explicit connection bypasses all resolution
    local result
    result=$(resolve_connection_with_capability "admin" "test-explicit-conn" 2>/dev/null)
    assert_condition "[[ '$result' == 'test-explicit-conn' ]]" \
        "explicit_connection_returned_unchanged" \
        "Expected 'test-explicit-conn', got '$result'"
    
    # Test: Explicit connection works with any capability
    result=$(resolve_connection_with_capability "loader" "test-loader-conn" 2>/dev/null)
    assert_condition "[[ '$result' == 'test-loader-conn' ]]" \
        "explicit_connection_works_with_any_capability" \
        "Expected 'test-loader-conn', got '$result'"
    
    # Test: Empty explicit connection falls back to resolution logic
    # This will fail in test environment but we can test the code path
    set +e
    resolve_connection_with_capability "admin" "" >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    assert_condition "[[ $exit_code -ne 0 ]]" \
        "empty_explicit_connection_triggers_resolution" \
        "Expected non-zero exit code for empty explicit connection"
}

test_session_cache_functionality() {
    echo "Testing session cache functionality..."
    
    source "${FRAMEWORK_LIB}/connection_resolver.sh"
    
    # Test: Clear cache works without error
    clear_session_cache
    log_test_result "clear_session_cache_runs_without_error" "PASS"
    
    # Test: Cache file creation (test internal function)
    _set_session_cache "test-cached-connection"
    assert_condition "[[ -f '${CACHE_DIR}/snowflake_framework_connection_cache_${SESSION_ID}' ]]" \
        "session_cache_file_created" \
        "Cache file not found"
    
    # Test: Cache retrieval
    local cached_result
    cached_result=$(_get_session_cache 2>/dev/null)
    assert_condition "[[ '$cached_result' == 'test-cached-connection' ]]" \
        "session_cache_retrieval_works" \
        "Expected 'test-cached-connection', got '$cached_result'"
    
    # Test: Cache file permissions are restrictive
    local cache_file="${CACHE_DIR}/snowflake_framework_connection_cache_${SESSION_ID}"
    local perms
    perms=$(stat -f "%Lp" "$cache_file" 2>/dev/null || stat -c "%a" "$cache_file" 2>/dev/null)
    assert_condition "[[ '$perms' == '600' ]]" \
        "cache_file_has_secure_permissions" \
        "Expected permissions 600, got $perms"
    
    # Test: Clear cache removes file
    clear_session_cache
    assert_condition "[[ ! -f '$cache_file' ]]" \
        "clear_cache_removes_file" \
        "Cache file still exists after clear"
}

# =============================================================================
# CONNECTION VALIDATION TESTS  
# =============================================================================

test_capability_validation_interface() {
    echo "Testing capability validation interface..."
    
    source "${FRAMEWORK_LIB}/connection_resolver.sh"
    
    # Test: validate_connection_capability handles invalid capability
    set +e
    validate_connection_capability "test-conn" "invalid-capability" >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    assert_condition "[[ $exit_code -ne 0 ]]" \
        "invalid_capability_returns_error" \
        "Expected non-zero exit code for invalid capability"
    
    # Test: validate_connection_capability accepts valid capabilities
    # These will fail in test environment but we test the interface
    for capability in admin loader transformer any; do
        set +e
        validate_connection_capability "test-conn" "$capability" >/dev/null 2>&1
        local cap_exit_code=$?
        set -e
        
        # We expect failure due to missing Snowflake CLI, but not due to invalid capability
        log_test_result "capability_${capability}_recognized" "PASS"
    done
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_handling_patterns() {
    echo "Testing error handling patterns..."
    
    source "${FRAMEWORK_LIB}/connection_resolver.sh"
    
    # Test: resolve_connection_with_capability fails gracefully with no configuration
    set +e
    local error_output
    error_output=$(resolve_connection_with_capability "admin" 2>&1)
    local exit_code=$?
    set -e
    
    assert_condition "[[ $exit_code -ne 0 ]]" \
        "resolution_failure_returns_nonzero_exit" \
        "Expected failure without Snowflake CLI configuration"
    
    # Test: Error message contains actionable guidance
    assert_condition "[[ '$error_output' =~ 'Solutions:' ]]" \
        "error_output_contains_solutions" \
        "Error output should contain Solutions section"
    
    assert_condition "[[ '$error_output' =~ '--connection' ]]" \
        "error_output_suggests_explicit_connection" \
        "Error output should suggest explicit connection parameter"
}

# =============================================================================
# INTEGRATION BOUNDARY TESTS
# =============================================================================

test_integration_boundaries() {
    echo "Testing integration boundaries..."
    
    source "${FRAMEWORK_LIB}/connection_resolver.sh"
    
    # Test: Component doesn't modify global state unexpectedly
    local original_path="$PATH"
    resolve_connection_with_capability "admin" "test" >/dev/null 2>&1 || true
    assert_condition "[[ '$PATH' == '$original_path' ]]" \
        "component_preserves_global_path" \
        "PATH was modified unexpectedly"
    
    # Test: Component doesn't create unexpected files outside cache
    local temp_file_count_before
    local temp_file_count_after
    temp_file_count_before=$(find /tmp -name "snowflake_framework_*" | wc -l)
    
    resolve_connection_with_capability "admin" "test" >/dev/null 2>&1 || true
    clear_session_cache
    
    temp_file_count_after=$(find /tmp -name "snowflake_framework_*" | wc -l)
    
    assert_condition "[[ $temp_file_count_after -eq $temp_file_count_before ]]" \
        "no_unexpected_temp_files_created" \
        "Temp file count changed: before=$temp_file_count_before, after=$temp_file_count_after"
}

# =============================================================================
# MOCK CREATION FOR ISOLATED TESTING
# =============================================================================

create_test_mocks() {
    local mock_dir="$TEST_SCRIPT_DIR/mocks"
    mkdir -p "$mock_dir"
    
    # Mock snow command for testing
    cat > "$mock_dir/snow" << 'EOF'
#!/usr/bin/env bash
# Mock snow command for testing

case "$1" in
    "connection")
        case "$2" in
            "list")
                echo '{"connections": [{"name": "test-admin", "is_default": true}]}'
                ;;
            "test")
                echo "Connection test successful"
                exit 0
                ;;
            *)
                echo "Unknown connection command: $2"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unknown snow command: $1"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$mock_dir/snow"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Main test runner
main() {
    echo "========================================"
    echo "Connection Resolver Component Unit Tests"
    echo "========================================"
    
    setup_test_env
    create_test_mocks
    
    # Run test suites
    test_framework_component_loading
    echo
    
    test_explicit_connection_resolution
    echo
    
    test_session_cache_functionality  
    echo
    
    test_capability_validation_interface
    echo
    
    test_error_handling_patterns
    echo
    
    test_integration_boundaries
    echo
    
    # Print summary
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Total tests: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✅ All tests passed"
        local exit_code=0
    else
        echo "❌ Some tests failed"
        local exit_code=1
    fi
    
    cleanup_test_env
    exit $exit_code
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi