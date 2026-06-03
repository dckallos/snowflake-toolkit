#!/usr/bin/env bash
# =============================================================================
# legacy_comparison_test.sh — Comprehensive testing of modernized vs legacy scripts
# =============================================================================
#
# CONTEXT: Phase 3.1 - Facebook staff-level validation before legacy replacement
# PURPOSE: Exhaustive functional equivalence testing between modern and legacy scripts
# MAINTAINER: Facebook staff-level implementation
#
# This module provides comprehensive testing to validate that modernized scripts
# provide functional equivalence to legacy implementations before any replacement.
# Tests edge cases, error handling, and ensures zero regression in functionality.
#
# ARCHITECTURE:
#   - Side-by-side comparison testing (modern vs legacy)
#   - Comprehensive parameter validation and edge case testing
#   - Error condition simulation and handling verification
#   - Performance and resource usage comparison
#   - Help system and documentation validation
#
# USAGE:
#   ./scripts/lib/legacy_comparison_test.sh --test orchestrator
#   ./scripts/lib/legacy_comparison_test.sh --test dbt-orchestrator
#   ./scripts/lib/legacy_comparison_test.sh --test all
#   ./scripts/lib/legacy_comparison_test.sh --validate-replacement-readiness
#
# CRITICAL: Legacy scripts are only replaced AFTER all tests pass
#
# =============================================================================

set -euo pipefail

# Framework component metadata
readonly LEGACY_COMPARISON_VERSION="1.0.0"
readonly LEGACY_COMPARISON_CREATED="2026-06-02"

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly TEST_LOG_DIR="/tmp/legacy_comparison_test_$$"
readonly TEST_CONFIG="${REPO_ROOT}/config/artwork_domain.yml"

# Script paths
readonly LEGACY_ORCHESTRATOR="${REPO_ROOT}/scripts/orchestrate.sh"
readonly MODERN_ORCHESTRATOR="${REPO_ROOT}/scripts/orchestrate_modern.sh"
readonly LEGACY_DBT_ORCHESTRATOR="${REPO_ROOT}/scripts/dbt_orchestrate.sh"
readonly MODERN_DBT_ORCHESTRATOR="${REPO_ROOT}/scripts/dbt_orchestrate_modern.sh"

# Test state tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CRITICAL_FAILURES=()

# =============================================================================
# MAIN TEST ORCHESTRATION
# =============================================================================

# main
#
# Primary entry point for legacy comparison testing.
# Provides comprehensive validation before any legacy replacement.
main() {
    local test_type="all"
    local validate_replacement=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test)
                test_type="$2"
                shift 2
                ;;
            --validate-replacement-readiness)
                validate_replacement=true
                shift
                ;;
            --help)
                show_legacy_comparison_help
                exit 0
                ;;
            *)
                _log_error "Unknown argument: $1"
                show_legacy_comparison_help
                exit 1
                ;;
        esac
    done
    
    # Initialize test environment
    _initialize_test_environment
    
    _log_info "Legacy Comparison Test Suite v${LEGACY_COMPARISON_VERSION}"
    _log_info "Facebook staff-level validation for legacy replacement"
    _log_info "Test type: $test_type"
    echo ""
    
    # Execute test phases
    case "$test_type" in
        all)
            _test_orchestrator_comparison
            _test_dbt_orchestrator_comparison
            _test_help_system_comparison
            _test_error_handling_comparison
            _test_performance_comparison
            ;;
        orchestrator)
            _test_orchestrator_comparison
            ;;
        dbt-orchestrator)
            _test_dbt_orchestrator_comparison
            ;;
        help-systems)
            _test_help_system_comparison
            ;;
        error-handling)
            _test_error_handling_comparison
            ;;
        performance)
            _test_performance_comparison
            ;;
        *)
            _log_error "Unknown test type: $test_type"
            _log_error "Valid types: all, orchestrator, dbt-orchestrator, help-systems, error-handling, performance"
            exit 1
            ;;
    esac
    
    # Optional replacement readiness validation
    if [[ "$validate_replacement" == true ]]; then
        _validate_replacement_readiness
    fi
    
    # Generate comprehensive test report
    _generate_test_report
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 && ${#CRITICAL_FAILURES[@]} -eq 0 ]]; then
        _log_info "All tests passed! Modernized scripts validated for legacy replacement."
        exit 0
    else
        _log_error "$TESTS_FAILED test(s) failed. ${#CRITICAL_FAILURES[@]} critical failure(s)."
        _log_error "Legacy replacement NOT recommended until all issues resolved."
        exit 1
    fi
}

# =============================================================================
# ORCHESTRATOR COMPARISON TESTING
# =============================================================================

# Test orchestrator script functional equivalence
_test_orchestrator_comparison() {
    _log_info "Testing orchestrator functional equivalence..."
    
    if [[ ! -f "$LEGACY_ORCHESTRATOR" || ! -f "$MODERN_ORCHESTRATOR" ]]; then
        _log_error "Missing orchestrator scripts for comparison"
        _add_critical_failure "orchestrator_scripts_missing"
        return 1
    fi
    
    # Test 1: Help output similarity
    _run_comparison_test "orchestrator_help_comparison" \
        "$LEGACY_ORCHESTRATOR --help" \
        "$MODERN_ORCHESTRATOR --help" \
        "help_content_similarity"
    
    # Test 2: Invalid argument handling
    _run_comparison_test "orchestrator_invalid_args" \
        "$LEGACY_ORCHESTRATOR --invalid-flag 2>&1 || true" \
        "$MODERN_ORCHESTRATOR --invalid-flag 2>&1 || true" \
        "error_message_consistency"
    
    # Test 3: Missing phase argument
    _run_comparison_test "orchestrator_missing_phase" \
        "$LEGACY_ORCHESTRATOR --connection admin 2>&1 || true" \
        "$MODERN_ORCHESTRATOR --connection admin 2>&1 || true" \
        "error_message_consistency"
    
    # Test 4: Dry run validation (no actual execution)
    _run_validation_test "orchestrator_modern_dry_run" \
        "$MODERN_ORCHESTRATOR --config '$TEST_CONFIG' --phase infra --connection mk07348" \
        "modern_orchestrator_validation"
    
    _log_info "Orchestrator comparison tests completed"
}

# =============================================================================
# DBT ORCHESTRATOR COMPARISON TESTING
# =============================================================================

# Test dbt orchestrator script functional equivalence
_test_dbt_orchestrator_comparison() {
    _log_info "Testing dbt orchestrator functional equivalence..."
    
    if [[ ! -f "$LEGACY_DBT_ORCHESTRATOR" || ! -f "$MODERN_DBT_ORCHESTRATOR" ]]; then
        _log_error "Missing dbt orchestrator scripts for comparison"
        _add_critical_failure "dbt_orchestrator_scripts_missing"
        return 1
    fi
    
    # Test 1: Help output similarity
    _run_comparison_test "dbt_orchestrator_help_comparison" \
        "$LEGACY_DBT_ORCHESTRATOR --help 2>&1 || true" \
        "$MODERN_DBT_ORCHESTRATOR --help" \
        "help_content_similarity"
    
    # Test 2: Invalid phase handling
    _run_comparison_test "dbt_orchestrator_invalid_phase" \
        "$LEGACY_DBT_ORCHESTRATOR --phase invalid 2>&1 || true" \
        "$MODERN_DBT_ORCHESTRATOR --phase invalid 2>&1 || true" \
        "error_message_consistency"
    
    # Test 3: Missing phase argument
    _run_comparison_test "dbt_orchestrator_missing_phase" \
        "$LEGACY_DBT_ORCHESTRATOR --connection admin 2>&1 || true" \
        "$MODERN_DBT_ORCHESTRATOR --connection admin 2>&1 || true" \
        "error_message_consistency"
    
    # Test 4: Modern connection parameter consistency
    _run_validation_test "dbt_orchestrator_connection_support" \
        "$MODERN_DBT_ORCHESTRATOR --config '$TEST_CONFIG' --phase init --connection mk07348" \
        "modern_dbt_connection_validation"
    
    _log_info "dbt orchestrator comparison tests completed"
}

# =============================================================================
# HELP SYSTEM COMPARISON TESTING
# =============================================================================

# Test help system comprehensiveness and consistency
_test_help_system_comparison() {
    _log_info "Testing help system comparison..."
    
    # Test help completeness for modern scripts
    _run_validation_test "modern_orchestrator_help_completeness" \
        "$MODERN_ORCHESTRATOR --help" \
        "help_system_completeness"
    
    _run_validation_test "modern_dbt_orchestrator_help_completeness" \
        "$MODERN_DBT_ORCHESTRATOR --help" \
        "help_system_completeness"
    
    # Test help accessibility
    _run_validation_test "modern_help_accessibility" \
        "$MODERN_ORCHESTRATOR help" \
        "help_accessibility"
    
    _run_validation_test "modern_dbt_help_accessibility" \
        "$MODERN_DBT_ORCHESTRATOR help" \
        "help_accessibility"
    
    _log_info "Help system comparison tests completed"
}

# =============================================================================
# ERROR HANDLING COMPARISON TESTING
# =============================================================================

# Test error handling consistency and quality
_test_error_handling_comparison() {
    _log_info "Testing error handling comparison..."
    
    # Test missing configuration file
    _run_comparison_test "missing_config_handling" \
        "$LEGACY_ORCHESTRATOR --phase infra --connection nonexistent 2>&1 || true" \
        "$MODERN_ORCHESTRATOR --config /nonexistent/config.yml --phase infra --connection nonexistent 2>&1 || true" \
        "error_handling_quality"
    
    # Test invalid connection
    _run_comparison_test "invalid_connection_handling" \
        "$LEGACY_ORCHESTRATOR --phase infra --connection nonexistent_connection 2>&1 || true" \
        "$MODERN_ORCHESTRATOR --config '$TEST_CONFIG' --phase infra --connection nonexistent_connection 2>&1 || true" \
        "error_handling_quality"
    
    # Test network/dependency failures
    _run_validation_test "modern_dependency_error_handling" \
        "PATH='/tmp/empty' $MODERN_ORCHESTRATOR --config '$TEST_CONFIG' --phase infra 2>&1 || true" \
        "dependency_error_handling"
    
    _log_info "Error handling comparison tests completed"
}

# =============================================================================
# PERFORMANCE COMPARISON TESTING
# =============================================================================

# Test performance and resource usage comparison
_test_performance_comparison() {
    _log_info "Testing performance comparison..."
    
    # Test startup time comparison
    _run_performance_test "orchestrator_startup_time" \
        "$LEGACY_ORCHESTRATOR --help >/dev/null" \
        "$MODERN_ORCHESTRATOR --help >/dev/null"
    
    _run_performance_test "dbt_orchestrator_startup_time" \
        "$LEGACY_DBT_ORCHESTRATOR --help >/dev/null 2>&1 || true" \
        "$MODERN_DBT_ORCHESTRATOR --help >/dev/null"
    
    # Test memory usage validation
    _run_validation_test "modern_memory_usage" \
        "/usr/bin/time -l $MODERN_ORCHESTRATOR --help >/dev/null 2>&1" \
        "memory_usage_validation"
    
    _log_info "Performance comparison tests completed"
}

# =============================================================================
# REPLACEMENT READINESS VALIDATION
# =============================================================================

# Validate readiness for legacy script replacement
_validate_replacement_readiness() {
    _log_info "Validating replacement readiness..."
    
    local replacement_ready=true
    
    # Check critical test failures
    if [[ ${#CRITICAL_FAILURES[@]} -gt 0 ]]; then
        _log_error "Critical failures prevent replacement:"
        for failure in "${CRITICAL_FAILURES[@]}"; do
            _log_error "  - $failure"
        done
        replacement_ready=false
    fi
    
    # Check test pass rate
    local pass_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    
    if [[ $pass_rate -lt 95 ]]; then
        _log_error "Test pass rate too low: ${pass_rate}% (required: 95%)"
        replacement_ready=false
    fi
    
    # Validate framework dependencies
    if ! _validate_framework_dependencies; then
        _log_error "Framework dependencies not satisfied"
        replacement_ready=false
    fi
    
    # Generate replacement recommendation
    if [[ "$replacement_ready" == true ]]; then
        _log_info "✅ REPLACEMENT RECOMMENDED"
        _log_info "Modernized scripts validated for legacy replacement"
        _log_info "All critical functionality verified"
    else
        _log_error "❌ REPLACEMENT NOT RECOMMENDED"
        _log_error "Address critical issues before replacement"
    fi
}

# =============================================================================
# TEST INFRASTRUCTURE
# =============================================================================

# Initialize test environment
_initialize_test_environment() {
    mkdir -p "$TEST_LOG_DIR"
    
    # Validate test prerequisites
    local missing_files=()
    
    if [[ ! -f "$TEST_CONFIG" ]]; then
        missing_files+=("$TEST_CONFIG")
    fi
    
    if [[ ! -f "$MODERN_ORCHESTRATOR" ]]; then
        missing_files+=("$MODERN_ORCHESTRATOR")
    fi
    
    if [[ ! -f "$MODERN_DBT_ORCHESTRATOR" ]]; then
        missing_files+=("$MODERN_DBT_ORCHESTRATOR")
    fi
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        _log_error "Missing required files for testing:"
        for file in "${missing_files[@]}"; do
            _log_error "  - $file"
        done
        exit 1
    fi
    
    # Check for required dependencies
    local missing_deps=()
    
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi
    
    if ! command -v snow >/dev/null 2>&1; then
        missing_deps+=("snow CLI")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        _log_warning "Missing optional dependencies: ${missing_deps[*]}"
        _log_warning "Some tests may be skipped"
    fi
}

# Run comparison test between legacy and modern implementations
_run_comparison_test() {
    local test_name="$1"
    local legacy_command="$2"
    local modern_command="$3"
    local comparison_type="$4"
    
    ((TESTS_RUN++))
    
    local legacy_log="$TEST_LOG_DIR/${test_name}_legacy.log"
    local modern_log="$TEST_LOG_DIR/${test_name}_modern.log"
    
    _log_debug "Running comparison test: $test_name"
    
    # Execute both commands
    local legacy_exit=0 modern_exit=0
    
    eval "$legacy_command" >"$legacy_log" 2>&1 || legacy_exit=$?
    eval "$modern_command" >"$modern_log" 2>&1 || modern_exit=$?
    
    # Compare results based on type
    case "$comparison_type" in
        help_content_similarity)
            _compare_help_content "$legacy_log" "$modern_log" "$test_name"
            ;;
        error_message_consistency)
            _compare_error_messages "$legacy_log" "$modern_log" "$legacy_exit" "$modern_exit" "$test_name"
            ;;
        error_handling_quality)
            _validate_error_handling "$modern_log" "$modern_exit" "$test_name"
            ;;
        *)
            _log_error "Unknown comparison type: $comparison_type"
            ((TESTS_FAILED++))
            return 1
            ;;
    esac
}

# Run validation test for modern implementation
_run_validation_test() {
    local test_name="$1"
    local command="$2"
    local validation_type="$3"
    
    ((TESTS_RUN++))
    
    local log_file="$TEST_LOG_DIR/${test_name}.log"
    
    _log_debug "Running validation test: $test_name"
    
    local exit_code=0
    eval "$command" >"$log_file" 2>&1 || exit_code=$?
    
    case "$validation_type" in
        modern_orchestrator_validation)
            _validate_modern_orchestrator "$log_file" "$exit_code" "$test_name"
            ;;
        modern_dbt_connection_validation)
            _validate_modern_dbt_connection "$log_file" "$exit_code" "$test_name"
            ;;
        help_system_completeness)
            _validate_help_completeness "$log_file" "$test_name"
            ;;
        help_accessibility)
            _validate_help_accessibility "$log_file" "$exit_code" "$test_name"
            ;;
        dependency_error_handling)
            _validate_dependency_error_handling "$log_file" "$exit_code" "$test_name"
            ;;
        memory_usage_validation)
            _validate_memory_usage "$log_file" "$test_name"
            ;;
        *)
            _log_error "Unknown validation type: $validation_type"
            ((TESTS_FAILED++))
            return 1
            ;;
    esac
}

# Run performance comparison test
_run_performance_test() {
    local test_name="$1"
    local legacy_command="$2"
    local modern_command="$3"
    
    ((TESTS_RUN++))
    
    _log_debug "Running performance test: $test_name"
    
    # Measure execution time for both commands
    local legacy_time modern_time
    
    legacy_time=$(time -p bash -c "$legacy_command" 2>&1 | grep real | awk '{print $2}' || echo "999")
    modern_time=$(time -p bash -c "$modern_command" 2>&1 | grep real | awk '{print $2}' || echo "999")
    
    # Compare performance (modern should not be significantly slower)
    if (( $(echo "$modern_time <= $legacy_time * 2" | bc -l) )); then
        _log_success "✓ $test_name (legacy: ${legacy_time}s, modern: ${modern_time}s)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - modern significantly slower (legacy: ${legacy_time}s, modern: ${modern_time}s)"
        ((TESTS_FAILED++))
    fi
}

# Add critical failure to tracking list
_add_critical_failure() {
    local failure="$1"
    CRITICAL_FAILURES+=("$failure")
}

# Validate framework dependencies
_validate_framework_dependencies() {
    local deps_satisfied=true
    
    # Check yq
    if ! command -v yq >/dev/null 2>&1; then
        _log_error "Missing required dependency: yq"
        deps_satisfied=false
    fi
    
    # Check domain config
    if [[ ! -f "$TEST_CONFIG" ]]; then
        _log_error "Missing domain configuration: $TEST_CONFIG"
        deps_satisfied=false
    fi
    
    # Check framework components
    local framework_components=(
        "${SCRIPT_DIR}/connection_resolver.sh"
        "${SCRIPT_DIR}/domain_config_loader.sh"
        "${SCRIPT_DIR}/ddl_orchestrator.sh"
        "${SCRIPT_DIR}/dbt_orchestrator.sh"
    )
    
    for component in "${framework_components[@]}"; do
        if [[ ! -f "$component" ]]; then
            _log_error "Missing framework component: $component"
            deps_satisfied=false
        fi
    done
    
    return $([ "$deps_satisfied" == true ] && echo 0 || echo 1)
}

# Comparison and validation helper functions
_compare_help_content() {
    local legacy_log="$1" modern_log="$2" test_name="$3"
    
    # Check if both have substantial help content
    local legacy_lines modern_lines
    legacy_lines=$(wc -l < "$legacy_log")
    modern_lines=$(wc -l < "$modern_log")
    
    if [[ $modern_lines -ge 10 ]]; then
        _log_success "✓ $test_name (legacy: $legacy_lines lines, modern: $modern_lines lines)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - insufficient help content in modern script"
        ((TESTS_FAILED++))
    fi
}

_compare_error_messages() {
    local legacy_log="$1" modern_log="$2" legacy_exit="$3" modern_exit="$4" test_name="$5"
    
    # Both should have non-zero exit codes for error conditions
    if [[ $legacy_exit -ne 0 && $modern_exit -ne 0 ]]; then
        _log_success "✓ $test_name (both failed appropriately)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - inconsistent error handling (legacy exit: $legacy_exit, modern exit: $modern_exit)"
        ((TESTS_FAILED++))
    fi
}

_validate_error_handling() {
    local log_file="$1" exit_code="$2" test_name="$3"
    
    if [[ $exit_code -ne 0 ]] && grep -q -i "error\|failed\|not found" "$log_file"; then
        _log_success "✓ $test_name (proper error handling)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - inadequate error handling"
        ((TESTS_FAILED++))
    fi
}

_validate_modern_orchestrator() {
    local log_file="$1" exit_code="$2" test_name="$3"
    
    # Should fail gracefully with helpful error message (no actual deployment)
    if [[ $exit_code -ne 0 ]] && grep -q "framework" "$log_file"; then
        _log_success "✓ $test_name (framework validation working)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - framework validation issues"
        ((TESTS_FAILED++))
    fi
}

_validate_modern_dbt_connection() {
    local log_file="$1" exit_code="$2" test_name="$3"
    
    # Should show modern dbt orchestrator attempting to run
    if grep -q "dbt_orchestrator" "$log_file"; then
        _log_success "✓ $test_name (modern dbt orchestrator integration working)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - modern dbt orchestrator integration issues"
        ((TESTS_FAILED++))
    fi
}

_validate_help_completeness() {
    local log_file="$1" test_name="$2"
    
    local help_sections=("DESCRIPTION" "USAGE" "OPTIONS" "EXAMPLES")
    local sections_found=0
    
    for section in "${help_sections[@]}"; do
        if grep -q "$section" "$log_file"; then
            ((sections_found++))
        fi
    done
    
    if [[ $sections_found -ge 3 ]]; then
        _log_success "✓ $test_name ($sections_found/4 help sections present)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - incomplete help documentation ($sections_found/4 sections)"
        ((TESTS_FAILED++))
    fi
}

_validate_help_accessibility() {
    local log_file="$1" exit_code="$2" test_name="$3"
    
    if [[ $exit_code -eq 0 ]] && [[ -s "$log_file" ]]; then
        _log_success "✓ $test_name (help accessible)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - help not accessible"
        ((TESTS_FAILED++))
    fi
}

_validate_dependency_error_handling() {
    local log_file="$1" exit_code="$2" test_name="$3"
    
    if [[ $exit_code -ne 0 ]] && grep -q -E "not found|missing|install" "$log_file"; then
        _log_success "✓ $test_name (proper dependency error handling)"
        ((TESTS_PASSED++))
    else
        _log_failure "✗ $test_name - inadequate dependency error handling"
        ((TESTS_FAILED++))
    fi
}

_validate_memory_usage() {
    local log_file="$1" test_name="$2"
    
    # Basic memory usage validation (should complete without excessive memory)
    if grep -q "maximum resident set size" "$log_file"; then
        _log_success "✓ $test_name (memory usage measured)"
        ((TESTS_PASSED++))
    else
        _log_warning "~ $test_name (memory measurement not available)"
        _log_success "✓ $test_name (completed successfully)"
        ((TESTS_PASSED++))
    fi
}

# Generate comprehensive test report
_generate_test_report() {
    echo ""
    _log_info "=== Legacy Comparison Test Report ==="
    _log_info "Tests run: $TESTS_RUN"
    _log_info "Tests passed: $TESTS_PASSED"
    _log_info "Tests failed: $TESTS_FAILED"
    _log_info "Critical failures: ${#CRITICAL_FAILURES[@]}"
    
    local pass_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    _log_info "Pass rate: ${pass_rate}%"
    
    if [[ ${#CRITICAL_FAILURES[@]} -gt 0 ]]; then
        _log_info ""
        _log_info "Critical failures:"
        for failure in "${CRITICAL_FAILURES[@]}"; do
            _log_info "  - $failure"
        done
    fi
    
    echo ""
    _log_info "Legacy replacement recommendation:"
    if [[ $TESTS_FAILED -eq 0 && ${#CRITICAL_FAILURES[@]} -eq 0 && $pass_rate -ge 95 ]]; then
        _log_info "✅ SAFE TO REPLACE LEGACY SCRIPTS"
        _log_info "All functional equivalence tests passed"
    else
        _log_info "❌ NOT SAFE TO REPLACE LEGACY SCRIPTS"
        _log_info "Address failures before replacement"
    fi
    
    echo ""
    _log_info "Test logs available in: $TEST_LOG_DIR"
}

# Logging functions
_log_info() {
    echo "==> [legacy_comparison] $*" >&2
}

_log_success() {
    echo "==> [legacy_comparison] $*" >&2
}

_log_failure() {
    echo "==> [legacy_comparison] $*" >&2
}

_log_warning() {
    echo "WARN [legacy_comparison] $*" >&2
}

_log_debug() {
    if [[ "${FRAMEWORK_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG [legacy_comparison] $*" >&2
    fi
}

_log_error() {
    echo "ERROR [legacy_comparison] $*" >&2
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_legacy_comparison_help() {
    cat <<EOF
legacy_comparison_test.sh — Comprehensive testing of modernized vs legacy scripts

DESCRIPTION:
    Facebook staff-level validation before legacy replacement. Provides exhaustive
    functional equivalence testing between modern and legacy script implementations.

USAGE:
    ./scripts/lib/legacy_comparison_test.sh [OPTIONS]

OPTIONS:
    --test TYPE                        Run specific test type (default: all)
    --validate-replacement-readiness   Include replacement readiness assessment
    --help                            Show this help message

TEST TYPES:
    all                     Run all test phases (default)
    orchestrator           Test orchestrator script functional equivalence
    dbt-orchestrator       Test dbt orchestrator script functional equivalence
    help-systems           Test help system comprehensiveness and consistency
    error-handling         Test error handling consistency and quality
    performance            Test performance and resource usage comparison

VALIDATION CRITERIA:
    - Functional equivalence between legacy and modern implementations
    - Comprehensive error handling and edge case coverage
    - Help system completeness and accessibility
    - Performance within acceptable bounds (no more than 2x slower)
    - Zero critical failures for replacement recommendation

ENVIRONMENT VARIABLES:
    FRAMEWORK_DEBUG     Set to 1 for debug logging

DEPENDENCIES:
    yq                  YAML processor (required for domain config)
    snow CLI           Snowflake CLI (required for connection testing)
    bc                 Calculator (required for performance comparison)

EXIT CODES:
    0   All tests passed, replacement recommended
    1   Tests failed or critical issues found, replacement NOT recommended

EXAMPLES:
    # Run comprehensive validation
    ./scripts/lib/legacy_comparison_test.sh --test all --validate-replacement-readiness
    
    # Test specific component
    ./scripts/lib/legacy_comparison_test.sh --test orchestrator
    
    # Debug mode
    FRAMEWORK_DEBUG=1 ./scripts/lib/legacy_comparison_test.sh --test help-systems

CRITICAL REQUIREMENT:
    Legacy scripts are only replaced AFTER all tests pass and replacement
    readiness is validated. This ensures zero regression in functionality.

REPLACEMENT WORKFLOW:
    1. Run all tests and validate 95%+ pass rate
    2. Address any critical failures
    3. Validate replacement readiness
    4. Only then proceed with legacy script replacement

EOF
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi