# Framework Testing Guide

> **Comprehensive testing and validation approaches for the domain-agnostic Snowflake framework**

## Overview

This guide provides testing strategies that validate framework behavior while maintaining clean architectural boundaries. The framework provides orchestration utilities; testing verifies these work correctly without compromising the separation between framework and user concerns.

## Testing Philosophy

### **Framework Testing Responsibilities**

**✅ Framework Tests Should Validate:**
- Connection resolution logic and priority handling
- CLI parameter parsing and validation  
- Error handling and user guidance
- Component integration boundaries
- Multi-account deployment capabilities

**❌ Framework Tests Should NOT:**
- Test user's DDL content or business logic
- Validate domain-specific schema designs
- Test Snowflake SQL syntax (that's Snowflake's job)
- Mock or simulate user's business requirements

### **Clean Testing Boundaries**

```
┌─────────────────────────┬─────────────────────────┐
│     Framework Tests     │      User Tests         │
├─────────────────────────┼─────────────────────────┤
│ • Connection resolution │ • DDL syntax validation │
│ • Parameter validation  │ • Business logic tests  │
│ • Error handling        │ • Data transformation   │
│ • File orchestration    │ • Schema compliance     │
│ • Multi-account support │ • Performance testing   │
└─────────────────────────┴─────────────────────────┘
```

## Testing Architecture

### **Test Suite Structure**

```
tests/
├── framework/
│   └── unit/                    # Framework component unit tests
│       ├── test_connection_resolver.sh
│       └── test_orchestrate_modern.sh
├── integration/                 # Multi-account integration tests
│   └── test_multi_account_deployment.sh
└── examples/                    # Reference implementations
    └── basic_project_integration.sh
```

### **Test Types and Scope**

#### **Unit Tests** (`tests/framework/unit/`)
- **Purpose**: Test individual framework components in isolation
- **Scope**: Component logic, error handling, interface contracts
- **Dependencies**: Minimal - use mocks where needed
- **Execution**: Fast, no external dependencies

#### **Integration Tests** (`tests/integration/`)  
- **Purpose**: Test framework with real Snowflake connections
- **Scope**: Multi-account deployment, connection validation, end-to-end flows
- **Dependencies**: Valid Snowflake CLI connections
- **Execution**: Slower, requires test accounts

#### **Example Tests** (`tests/examples/`)
- **Purpose**: Demonstrate framework integration patterns
- **Scope**: Complete integration workflows, documentation validation
- **Dependencies**: Framework components, optional Snowflake connections
- **Execution**: Educational, interactive demonstrations

## Unit Testing

### **Running Unit Tests**

```bash
# Run all unit tests
cd tests/framework/unit/
./test_connection_resolver.sh
./test_orchestrate_modern.sh

# Run with verbose output
SNOW_DEBUG=true ./test_connection_resolver.sh
```

### **Connection Resolver Unit Tests**

**Test Coverage**:
- Component loading and function availability
- Explicit connection resolution (bypasses all logic)
- Session cache functionality and security
- Capability validation interface
- Error handling patterns
- Integration boundaries

**Key Test Patterns**:
```bash
# Test explicit connection resolution
result=$(resolve_connection_with_capability "admin" "test-explicit-conn")
assert_condition "[[ '$result' == 'test-explicit-conn' ]]"

# Test session cache security
cache_file="${CACHE_DIR}/snowflake_framework_connection_cache_${SESSION_ID}"
perms=$(stat -c "%a" "$cache_file")
assert_condition "[[ '$perms' == '600' ]]"

# Test error handling
set +e
resolve_connection_with_capability "admin" "" >/dev/null 2>&1
exit_code=$?
set -e
assert_condition "[[ $exit_code -ne 0 ]]"
```

### **Orchestrator Unit Tests**

**Test Coverage**:
- Component availability and help output
- Required parameter validation
- File path validation  
- CLI argument parsing
- Phase validation interface
- Error handling patterns
- Integration boundaries
- Backward compatibility features

**Key Test Patterns**:
```bash
# Test required parameter validation
set +e
output=$("$ORCHESTRATE_SCRIPT" --manifest test.txt --phase infra --connection test 2>&1)
exit_code=$?
set -e
assert_condition "[[ $exit_code -ne 0 && '$output' =~ 'DDL directory is required' ]]"

# Test help interface
help_output=$("$ORCHESTRATE_SCRIPT" --help 2>&1)
assert_condition "[[ '$help_output' =~ 'USAGE:' && '$help_output' =~ 'EXAMPLES:' ]]"

# Test framework boundaries
script_content=$(cat "$ORCHESTRATE_SCRIPT")
assert_condition "[[ ! '$script_content' =~ 'ARTWORK_' ]]"  # No domain-specific hardcoding
```

## Integration Testing

### **Running Integration Tests**

**Prerequisites**:
```bash
# Snowflake CLI configured
snow connection list

# Test connections available (named with test/dev/staging prefix preferred)
snow connection test -c test-admin
snow connection test -c dev-admin
```

**Execution**:
```bash
cd tests/integration/

# Run with automatic cleanup
./test_multi_account_deployment.sh

# Run without cleanup (for debugging)
CLEANUP_ON_SUCCESS=false ./test_multi_account_deployment.sh
```

### **Multi-Account Integration Tests**

**Test Coverage**:
- Framework component availability in real environment
- Connection resolution with actual Snowflake CLI
- Single-account infrastructure deployment
- Idempotent redeployment validation
- Multi-account deployment isolation
- Cross-account object verification

**Test Environment**:
- Creates temporary DDL project with test objects
- Uses `FRAMEWORK_TEST_*` naming for easy cleanup
- Prefers test/dev connections, falls back to available connections
- Validates object creation and isolation

**Key Integration Patterns**:
```bash
# Multi-account deployment test
scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$PRIMARY_TEST_CONNECTION"

scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$SECONDARY_TEST_CONNECTION"

# Verify isolation
primary_count=$(snow sql -c "$PRIMARY_TEST_CONNECTION" -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_%';" | jq length)
secondary_count=$(snow sql -c "$SECONDARY_TEST_CONNECTION" -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_%';" | jq length)
assert_condition "[[ $primary_count -gt 0 && $secondary_count -gt 0 ]]"
```

### **Test Data Management**

**Safe Test Patterns**:
- Use clearly marked test object names (`FRAMEWORK_TEST_*`, `EXAMPLE_*`)
- Include descriptive comments marking objects as test/safe-to-drop
- Implement automatic cleanup on successful test runs
- Provide manual cleanup instructions for failed tests

**DDL Test Patterns**:
```sql
-- Good: Clearly marked test object
CREATE DATABASE IF NOT EXISTS FRAMEWORK_TEST_DB
    COMMENT = 'Framework integration test database - safe to drop';

-- Good: Idempotent operations  
CREATE WAREHOUSE IF NOT EXISTS FRAMEWORK_TEST_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60;

-- Avoid: Production-sounding names
-- CREATE DATABASE PROD_ANALYTICS;
```

## Example Testing

### **Running Example Tests**

**Interactive Demonstration**:
```bash
cd tests/examples/
./basic_project_integration.sh

# Follow prompts for:
# - Project structure creation
# - Framework integration
# - Optional live deployment testing
```

**What Examples Test**:
- Complete project setup workflow
- Framework integration patterns
- DDL structure and dependencies
- Documentation accuracy
- Deployment command validation

### **Basic Project Integration Example**

**Demonstrates**:
- Creating realistic DDL project from scratch
- Installing framework components
- Configuring execution manifest
- Multi-account deployment patterns
- Documentation and usage examples

**Educational Value**:
- Shows complete adoption workflow
- Provides copy-paste deployment commands
- Demonstrates framework benefits
- Validates documentation accuracy

## Test Development Guidelines

### **Writing New Framework Tests**

**Unit Test Guidelines**:
```bash
#!/usr/bin/env bash
# Template for framework unit tests

set -euo pipefail

# Test utilities
log_test_result() {
    local test_name="$1"
    local result="$2" 
    local details="${3:-}"
    
    if [[ "$result" == "PASS" ]]; then
        echo "✅ $test_name"
    else
        echo "❌ $test_name"
        [[ -n "$details" ]] && echo "   Details: $details"
    fi
}

# Test specific framework behavior, not user content
test_framework_feature() {
    # Setup minimal test environment
    # Test framework component behavior
    # Assert framework boundaries maintained
    # Cleanup test environment
}
```

**Integration Test Guidelines**:
```bash
#!/usr/bin/env bash
# Template for integration tests

set -euo pipefail

# Use real connections but test objects only
setup_test_environment() {
    # Create temporary test project
    # Use clearly marked test object names
    # Validate connections before proceeding
}

test_real_deployment() {
    # Test framework orchestration with real Snowflake
    # Validate object creation and cleanup
    # Test multi-account patterns
    # Verify isolation and idempotency
}

cleanup_test_environment() {
    # Remove test objects from Snowflake
    # Clean up temporary files
    # Provide manual cleanup guidance if needed
}
```

### **Test Naming Conventions**

**Unit Tests**:
- `test_[component]_[feature]` - e.g., `test_connection_resolver_caching`
- `test_[interface]_[validation]` - e.g., `test_orchestrator_parameter_validation`

**Integration Tests**:
- `test_[workflow]_[scenario]` - e.g., `test_multi_account_deployment`
- `test_[capability]_[boundary]` - e.g., `test_connection_resolution_isolation`

**Test Functions**:
- `test_[specific_behavior]()` - e.g., `test_explicit_connection_resolution()`
- `test_[error_condition]()` - e.g., `test_invalid_manifest_handling()`

### **Framework Boundary Validation**

**Ensure Tests Maintain Boundaries**:
```bash
# Good: Test framework behavior
test_connection_resolution_priority() {
    result=$(resolve_connection_with_capability "admin" "explicit-conn")
    assert_condition "[[ '$result' == 'explicit-conn' ]]"
}

# Bad: Test user DDL content
test_user_ddl_syntax() {
    # This belongs in user's test suite, not framework tests
}

# Good: Test orchestration interface
test_manifest_file_processing() {
    # Test framework reads manifest correctly
    # Test execution order logic
    # Test error handling for malformed manifests
}

# Bad: Test business logic
test_customer_data_transformation() {
    # This belongs in user's domain tests
}
```

## Continuous Integration

### **CI/CD Pipeline Integration**

**GitHub Actions Example**:
```yaml
name: Framework Test Suite

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Run Unit Tests
        run: |
          chmod +x tests/framework/unit/*.sh
          tests/framework/unit/test_connection_resolver.sh
          tests/framework/unit/test_orchestrate_modern.sh

  integration-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v2
      
      - name: Install Snowflake CLI
        run: |
          curl -sSfL https://github.com/Snowflake-Labs/snowflake-cli/releases/latest/download/snowflake-cli-linux-x64.tar.gz | tar xz
          sudo mv snowflake /usr/local/bin/snow
      
      - name: Configure Test Connection
        run: |
          snow connection add \
            --connection-name ci-test \
            --account ${{ secrets.SNOWFLAKE_TEST_ACCOUNT }} \
            --user ${{ secrets.SNOWFLAKE_TEST_USER }} \
            --private-key-path /tmp/test_key.pem
        env:
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}
      
      - name: Run Integration Tests
        run: |
          chmod +x tests/integration/*.sh
          CLEANUP_ON_SUCCESS=true tests/integration/test_multi_account_deployment.sh
```

### **Test Environment Management**

**Connection Configuration for CI**:
```bash
# Use dedicated test accounts
# Separate from production/development accounts  
# Clear naming convention (ci-test, framework-test)
# Minimal privileges required for test execution
# Automatic cleanup enabled
```

**Secret Management**:
```bash
# Store test account credentials securely
# Use service accounts with restricted permissions
# Rotate credentials regularly
# Monitor test account usage
```

## Test Execution Workflows

### **Development Workflow**

```bash
# 1. Unit tests (fast, no dependencies)
cd tests/framework/unit/
./test_connection_resolver.sh
./test_orchestrate_modern.sh

# 2. Integration tests (requires connections)
cd ../integration/
# Verify test connections available
snow connection list | grep -E 'test|dev'

# Run integration suite
./test_multi_account_deployment.sh

# 3. Example validation
cd ../examples/
./basic_project_integration.sh
```

### **Release Validation Workflow**

```bash
# 1. Full test suite
make test-all  # or equivalent

# 2. Multi-account validation
make test-integration CONNECTIONS="test-admin,staging-admin"

# 3. Documentation validation  
make test-examples

# 4. Backward compatibility
make test-legacy-compatibility
```

### **Debugging Failed Tests**

**Unit Test Debugging**:
```bash
# Enable debug output
SNOW_DEBUG=true ./test_connection_resolver.sh

# Run specific test function
bash -x test_connection_resolver.sh test_explicit_connection_resolution

# Inspect test artifacts
ls -la /tmp/snowflake_framework_*
```

**Integration Test Debugging**:
```bash
# Disable cleanup to inspect objects
CLEANUP_ON_SUCCESS=false ./test_multi_account_deployment.sh

# Manual object inspection
snow sql -c test-admin -q "SHOW DATABASES LIKE 'FRAMEWORK_TEST_%';"

# Manual cleanup
snow sql -c test-admin -q "DROP DATABASE IF EXISTS FRAMEWORK_TEST_DB CASCADE;"
```

## Test Maintenance

### **Keeping Tests Current**

**When Framework Changes**:
- Update unit tests for modified interfaces
- Validate integration tests still pass
- Update example documentation
- Review error message assertions

**Regular Maintenance**:
- Verify test connections remain valid
- Update test object naming if needed
- Review and update documentation examples
- Validate CI/CD pipeline execution

### **Test Quality Metrics**

**Coverage Goals**:
- Unit tests: All public framework functions
- Integration tests: All deployment scenarios  
- Examples: All documented usage patterns
- Error handling: All error conditions with actionable guidance

**Quality Indicators**:
- Tests pass consistently across environments
- Clear, actionable failure messages
- Minimal external dependencies
- Fast execution for unit tests
- Realistic scenarios for integration tests

## Summary

**Testing Strategy**:
1. **Unit tests** validate framework components in isolation
2. **Integration tests** verify multi-account deployment capabilities
3. **Example tests** demonstrate adoption patterns and validate documentation

**Framework Testing Principles**:
- Test framework behavior, not user content
- Maintain clean boundaries between framework and domain concerns
- Use realistic test scenarios with proper cleanup
- Provide clear guidance for test execution and debugging

**Success Criteria**:
- Framework components work correctly across different environments
- Multi-account deployment maintains proper isolation
- Documentation examples are accurate and executable
- Error handling provides actionable guidance
- Tests can be run safely without affecting production systems