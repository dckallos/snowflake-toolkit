# Framework Architecture

> **Design principles and boundaries for the domain-agnostic Snowflake infrastructure framework**

## Architectural Overview

This framework implements **pure orchestration** for Snowflake DDL deployment across multiple accounts. The core principle: **orchestrate user artifacts, don't generate them**.

## Design Principles

### **1. Separation of Concerns**

The framework maintains strict boundaries between orchestration utilities and domain-specific content:

```
┌─────────────────────────┬─────────────────────────┐
│     Framework Layer     │      User Layer         │
├─────────────────────────┼─────────────────────────┤
│ • Connection resolution │ • DDL file content      │
│ • Authentication setup  │ • Database/role names   │
│ • File orchestration    │ • Business logic        │
│ • Error handling        │ • Manifest ordering     │
│ • Multi-account support │ • Domain configuration  │
└─────────────────────────┴─────────────────────────┘
```

### **2. Universal Applicability**

Framework components work with **any Snowflake account** and **any DDL project**:

- No hardcoded database names, role names, or connection details
- No domain-specific configuration embedded in framework
- No assumptions about user's schema design or business logic
- Clean interfaces that accept user parameters explicitly

### **3. Connection Flexibility**

Support deployment to any configured Snowflake account through connection parameters:

```bash
# Same DDL, different accounts
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection prod-admin
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection test-admin  
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection dev-admin
```

## Component Architecture

### **Core Components**

#### **Connection Resolver** (`scripts/lib/connection_resolver.sh`)

**Purpose**: Universal connection resolution and validation

**Responsibilities**:
- Priority-based connection resolution with explicit user confirmation
- Session-scoped caching to prevent repeated prompts
- Capability validation to ensure connections can perform required operations
- Comprehensive error handling with actionable guidance

**Interface**:
```bash
# Connection resolution with capability validation
connection=$(resolve_connection_with_capability admin --explicit-connection prod)
validate_connection_capability "$connection" transformer
```

**Design Patterns**:
- **Explicit over implicit**: Requires explicit connection specification
- **Fail-fast validation**: Tests connection capabilities before proceeding
- **User confirmation**: Prompts for confirmation on ambiguous choices
- **Session isolation**: Caches choices within session scope only

#### **Modern Orchestrator** (`scripts/orchestrate_modern.sh`)

**Purpose**: Pure file orchestration without domain assumptions

**Responsibilities**:
- Execute user's DDL files in manifest-defined order
- Provide backward compatibility with legacy `orchestrate.sh`
- Enhanced connection resolution and validation
- Comprehensive error handling and logging

**Interface**:
```bash
scripts/orchestrate_modern.sh \
  --ddl-dir DIR \           # User's DDL directory
  --manifest FILE \         # User's execution order
  --phase PHASE \           # infra|bootstrap|all|down
  --connection CONN         # Snowflake connection name
  [--from SCRIPT] \         # Optional: start from specific script
  [--file FILE]             # Optional: execute single script
```

**Design Patterns**:
- **Parameterized execution**: All paths and connections explicit
- **User-controlled ordering**: Framework executes user's manifest, unchanged
- **Idempotent operations**: Safe to re-run without side effects
- **Atomic phases**: Clear boundaries between infrastructure and bootstrap

### **Deprecated Components** (Phase R1 Cleanup)

These components violated architectural boundaries and were removed:

- **`domain_config_loader.sh`** - REMOVED: Framework shouldn't know domain specifics
- **`ddl_orchestrator.sh`** - DEPRECATED: Replaced by pure orchestration  
- **`dbt_orchestrator.sh`** - DEPRECATED: dbt is user domain responsibility
- **`config/artwork_domain.yml`** - REMOVED: Domain logic belongs with user project

## Architectural Boundaries

### **Framework MUST Provide**

1. **Connection Management**
   - Universal connection resolution across any Snowflake account
   - Connection capability validation and error reporting
   - Session-scoped connection caching and reuse

2. **Authentication Utilities**
   - SSH key generation and registration assistance
   - JWT token validation and troubleshooting
   - Connection testing and verification

3. **File Orchestration**
   - Execute user's DDL files in specified order
   - Proper error handling and rollback capabilities
   - Support for partial deployments and single-file operations

4. **Multi-Account Support**
   - Same framework, different target accounts
   - Connection switching without code changes
   - Account-agnostic deployment patterns

### **Framework MUST NOT**

1. **Modify User Content**
   - No template substitution in DDL files
   - No automated code generation
   - No domain-specific transformations

2. **Embed Domain Knowledge**
   - No hardcoded database/role/warehouse names
   - No business logic assumptions
   - No schema-specific validations

3. **Override User Control**
   - No automatic manifest generation
   - No implicit connection selection
   - No hidden configuration sources

## Error Handling Architecture

### **Failure Categories**

1. **Connection Failures** - Invalid or insufficient connection configuration
2. **Capability Failures** - Connection lacks required permissions
3. **Execution Failures** - DDL script execution errors
4. **Configuration Failures** - Missing or invalid user configuration

### **Error Handling Patterns**

```bash
# Example: Connection validation with clear error messages
if ! validate_snowflake_connection "$connection_name"; then
    echo "ERROR: Connection '$connection_name' failed validation"
    echo "SOLUTION: Run 'snow connection test -c $connection_name'"
    echo "HELP: Check connection configuration in ~/.snowflake/config.toml"
    exit 1
fi
```

**Design Principles**:
- **Fail fast**: Validate prerequisites before starting operations
- **Actionable errors**: Tell user exactly how to fix the problem
- **Context preservation**: Include enough detail for debugging
- **Recovery guidance**: Suggest specific next steps

## Integration Architecture

### **Existing Project Integration**

Framework integrates with existing DDL projects through:

1. **Directory Convention**
   ```
   your-project/
   ├── infrastructure/           # Your DDL files (unchanged)
   ├── scripts/manifest.txt      # Your execution order (unchanged)  
   └── scripts/                  # Add framework scripts here
       ├── orchestrate_modern.sh
       └── lib/connection_resolver.sh
   ```

2. **Makefile Integration**
   ```makefile
   # Existing targets work unchanged
   infra:
   	scripts/orchestrate_modern.sh --ddl-dir infrastructure/ \
   	                              --manifest scripts/manifest.txt \
   	                              --phase infra \
   	                              --connection $(CONN)
   ```

3. **Connection Configuration**
   ```bash
   # Framework uses existing Snowflake CLI connections
   snow connection list    # Shows available connections
   snow connection test -c admin    # Framework validates these
   ```

### **Framework Extension Patterns**

For adding new capabilities:

1. **New Orchestration Types**
   - Add new phases to `orchestrate_modern.sh`
   - Maintain backward compatibility with existing phases
   - Document new phase semantics clearly

2. **New Connection Types**
   - Extend `connection_resolver.sh` capability validation
   - Add new capability types (e.g., `analyst`, `developer`)
   - Preserve existing resolution patterns

3. **New Error Scenarios**
   - Add specific error detection and recovery guidance
   - Maintain consistent error message formatting
   - Include actionable troubleshooting steps

## Multi-Account Architecture

### **Connection-Based Multi-Account Support**

The framework achieves multi-account deployment through connection switching rather than configuration templating:

```bash
# Same DDL project, multiple target accounts
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection prod-admin
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection staging-admin
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection dev-admin
```

### **Account-Agnostic DDL Patterns**

User DDL files should follow account-agnostic patterns:

```sql
-- Good: Uses environment-specific connection context
CREATE DATABASE IF NOT EXISTS ARTWORK_DB;

-- Avoid: Hardcoded account-specific names  
-- CREATE DATABASE IF NOT EXISTS PROD_ARTWORK_DB;
```

### **Connection Configuration Management**

Framework relies on Snowflake CLI connection management:

```toml
# ~/.snowflake/config.toml
[connections.prod-admin]
account = "prod-account"
user = "admin-user"
# ... other prod settings

[connections.staging-admin]  
account = "staging-account"
user = "admin-user"
# ... other staging settings
```

## Testing Architecture

### **Framework Testing Boundaries**

1. **Unit Testing**
   - Connection resolution logic
   - Error handling paths
   - Configuration validation

2. **Integration Testing**
   - Multi-account deployment scenarios
   - DDL execution validation
   - End-to-end orchestration flows

3. **Contract Testing**
   - Framework component interfaces
   - User project integration points
   - Backward compatibility validation

### **Testing Isolation Principles**

- Framework tests never modify user DDL content
- Connection tests use dedicated test accounts
- Integration tests validate framework behavior, not business logic

## Future Evolution

### **Planned Enhancements**

1. **Enhanced Error Recovery**
   - Automatic retry mechanisms for transient failures
   - Checkpoint/resume capabilities for long deployments
   - Intelligent rollback on partial failures

2. **Advanced Connection Features**
   - Connection pooling and reuse optimization
   - Multi-region connection management
   - Dynamic connection discovery

3. **Integration Ecosystem**
   - CI/CD pipeline integration templates
   - Monitoring and observability hooks
   - Configuration management tool integration

### **Architectural Constraints**

Future enhancements must preserve:
- Domain-agnostic design principles
- Clean separation between framework and user concerns
- Universal applicability across Snowflake accounts
- Backward compatibility with existing integrations

## Summary

This architecture enables:
- **Reusable infrastructure** across any Snowflake account or DDL project
- **Clean boundaries** between orchestration and domain logic
- **Connection flexibility** for multi-account deployment patterns
- **Framework evolution** without breaking user projects

The key insight: **orchestration tools should coordinate existing artifacts, not generate or modify business logic**.