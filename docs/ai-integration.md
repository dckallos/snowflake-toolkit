# AI/LLM Integration Guidelines

> **Guidelines for AI and LLM systems to correctly use the framework while maintaining architectural boundaries**

## Overview for AI Systems

This framework implements **pure orchestration** for Snowflake DDL deployment. The core principle AI systems must follow: **orchestrate user artifacts, don't generate them**.

## Critical Architectural Boundaries

### ✅ **AI Systems SHOULD** 

1. **Use Framework for Orchestration**
   - Call `scripts/orchestrate_modern.sh` with explicit parameters
   - Use `scripts/lib/connection_resolver.sh` for connection management
   - Validate connections before deployment operations

2. **Preserve User DDL Content**
   - Read and understand existing DDL files
   - Execute user's DDL files unchanged via framework
   - Help users debug DDL content issues

3. **Assist with Configuration**
   - Help users create manifest files with proper script ordering
   - Guide users through connection setup and testing
   - Recommend framework integration patterns

4. **Provide Operational Support**
   - Troubleshoot framework deployment issues
   - Explain connection resolution behavior
   - Suggest deployment strategies and best practices

### ❌ **AI Systems MUST NOT**

1. **Modify User DDL Content**
   - Never perform template substitution in SQL files
   - Never automatically edit database/role names in DDL
   - Never generate or rewrite user's business logic

2. **Embed Domain Knowledge in Framework**
   - Never add domain-specific configuration to framework components
   - Never hardcode business assumptions into orchestration logic
   - Never create framework code that knows about user's schema design

3. **Override Framework Boundaries**
   - Never bypass connection resolution and validation
   - Never create implicit configuration or defaults
   - Never modify framework components without architectural justification

## AI Usage Patterns

### Pattern 1: Framework Deployment Assistance

**Good AI Behavior**:
```
User: "Help me deploy my DDL to production"

AI Response:
"I can help you deploy using the framework. First, let me check your setup:

1. Verify your connection: `snow connection test -c prod-admin`
2. Deploy infrastructure using framework:

scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection prod-admin

This will execute your existing DDL files unchanged. Would you like me to explain any of these parameters?"
```

**Bad AI Behavior**:
```
AI Response: "I'll modify your DDL files to use production database names, then deploy them."
```

### Pattern 2: DDL Debugging Support

**Good AI Behavior**:
```
User: "My DDL deployment is failing"

AI Response:
"I can help debug this. Let's check the framework logs and your DDL content:

1. What error message did you see from the framework?
2. Let me examine your DDL file for common issues
3. We can test the connection separately first

The framework executes your DDL unchanged, so the issue is likely in the SQL content or connection setup."
```

**Bad AI Behavior**:
```
AI Response: "I'll fix your DDL by rewriting it to use framework templates."
```

### Pattern 3: Multi-Account Deployment Guidance

**Good AI Behavior**:
```
User: "How do I deploy to multiple environments?"

AI Response:
"The framework supports multi-account deployment through connection switching:

# Same DDL, different connections
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection dev-admin
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection staging-admin  
scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --connection prod-admin

Your DDL files should use account-agnostic patterns. Would you like me to review your DDL for account-specific references?"
```

**Bad AI Behavior**:
```
AI Response: "I'll create environment-specific DDL files for each account."
```

## Code Examples for AI Systems

### Example 1: Connection Resolution Helper

```python
def help_user_deploy_ddl(ddl_dir, manifest_file, connection_name, phase="infra"):
    """
    AI helper function that assists with framework-based deployment.
    IMPORTANT: Never modifies user's DDL content.
    """
    
    # Validate framework components exist
    if not os.path.exists("scripts/orchestrate_modern.sh"):
        return "ERROR: Framework not installed. Please copy framework components."
    
    # Validate user's DDL structure  
    if not os.path.exists(ddl_dir):
        return f"ERROR: DDL directory not found: {ddl_dir}"
        
    if not os.path.exists(manifest_file):
        return f"ERROR: Manifest file not found: {manifest_file}"
    
    # Build framework command (user's files unchanged)
    cmd = [
        "scripts/orchestrate_modern.sh",
        "--ddl-dir", ddl_dir,
        "--manifest", manifest_file, 
        "--phase", phase,
        "--connection", connection_name
    ]
    
    return f"Framework command: {' '.join(cmd)}"
```

### Example 2: DDL Validation Assistant

```python
def validate_ddl_for_framework(ddl_content):
    """
    AI helper to validate user's DDL follows framework-compatible patterns.
    IMPORTANT: Never modifies the DDL content, only provides guidance.
    """
    
    issues = []
    recommendations = []
    
    # Check for account-specific hardcoding
    if re.search(r'(PROD_|DEV_|STAGING_)\w+', ddl_content):
        issues.append("Found environment-specific database names")
        recommendations.append("Use account-agnostic names that work with any connection")
    
    # Check for non-idempotent operations
    if "CREATE DATABASE " in ddl_content and "IF NOT EXISTS" not in ddl_content:
        issues.append("Non-idempotent CREATE DATABASE found")
        recommendations.append("Add IF NOT EXISTS for safe re-execution")
    
    # Return analysis, not modified content
    return {
        "issues": issues,
        "recommendations": recommendations,
        "note": "Framework will execute your DDL unchanged. Please modify as needed."
    }
```

### Example 3: Connection Testing Helper

```bash
# AI-generated script to help users test connections
#!/usr/bin/env bash
# Framework connection test helper (generated by AI)

set -euo pipefail

echo "Testing framework connection capabilities..."

# Source framework utilities
source scripts/lib/connection_resolver.sh

# Test connection resolution
echo "Testing connection resolution..."
if connection=$(resolve_connection_with_capability admin); then
    echo "✅ Connection resolved: $connection"
else
    echo "❌ Connection resolution failed"
    echo "Solutions:"
    echo "  1. Run: snow connection list"
    echo "  2. Add connection: snow connection add --connection-name admin"
    echo "  3. Test connection: snow connection test -c admin"
    exit 1
fi

# Test connection capabilities
echo "Testing connection capabilities..."
if validate_connection_capability "$connection" admin; then
    echo "✅ Connection has admin capabilities"
else
    echo "❌ Connection lacks required admin capabilities"
    echo "Check user permissions in Snowflake"
    exit 1
fi

echo "✅ Connection setup is valid for framework deployment"
```

## AI-Generated Documentation Patterns

### Good Documentation Pattern

```markdown
## Deploying with Framework

The framework orchestrates your existing DDL files without modification:

```bash
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

Your DDL files should follow these patterns:
- Use `IF NOT EXISTS` for idempotent operations
- Avoid environment-specific database names  
- Reference roles/warehouses defined in same project

The framework provides connection management and execution orchestration.
Your business logic remains in your DDL files.
```

### Bad Documentation Pattern

```markdown
## Deploying with Framework Templates

Configure your deployment using framework variables:

```yaml
# framework-config.yml  
database_name: "{{ENVIRONMENT}}_ARTWORK_DB"
admin_role: "{{ENVIRONMENT}}_ADMIN"
```

The framework will substitute these variables in your DDL files automatically.
```

## Common AI Anti-Patterns

### Anti-Pattern 1: Template Generation

**Wrong**:
```python
def generate_ddl_from_template(template, environment):
    """WRONG: Framework doesn't use templates"""
    return template.replace("{{ENV}}", environment)
```

**Correct**:
```python
def validate_ddl_compatibility(ddl_content):
    """CORRECT: Help user validate their DDL"""
    return check_for_hardcoded_references(ddl_content)
```

### Anti-Pattern 2: Configuration File Creation

**Wrong**:
```python
def create_framework_config(user_requirements):
    """WRONG: Framework doesn't use configuration files"""
    config = {
        "database_prefix": user_requirements.environment,
        "role_suffix": "_ROLE"
    }
    write_config("config/framework.yml", config)
```

**Correct**:
```python
def help_create_manifest(ddl_files):
    """CORRECT: Help user create execution manifest"""
    ordered_files = analyze_dependencies(ddl_files)
    return generate_manifest_suggestion(ordered_files)
```

### Anti-Pattern 3: DDL Modification

**Wrong**:
```python
def prepare_ddl_for_environment(ddl_path, target_env):
    """WRONG: Never modify user's DDL content"""
    content = read_file(ddl_path)
    modified = content.replace("ARTWORK_DB", f"{target_env}_ARTWORK_DB")
    write_file(ddl_path, modified)
```

**Correct**:
```python
def suggest_ddl_improvements(ddl_path):
    """CORRECT: Suggest improvements, don't modify"""
    content = read_file(ddl_path)
    issues = analyze_for_portability(content)
    return generate_improvement_suggestions(issues)
```

## AI Debugging Guidelines

### Framework Error Interpretation

When users report framework errors, AI systems should:

1. **Identify Error Category**
   - Connection errors → Guide connection troubleshooting
   - Parameter errors → Explain required parameters  
   - DDL execution errors → Help debug user's SQL content

2. **Provide Specific Solutions**
   - Never suggest modifying framework components
   - Focus on user configuration and DDL content
   - Reference framework documentation for details

3. **Maintain Architectural Boundaries**
   - Framework provides orchestration, user provides DDL content
   - Connection issues are configuration problems, not framework bugs
   - DDL issues are user content problems, not framework limitations

### Sample Error Troubleshooting

**Connection Resolution Error**:
```
User: "Getting 'Failed to resolve connection: admin'"

AI Response:
"This is a connection configuration issue. Let's troubleshoot:

1. Check available connections: `snow connection list`
2. Test specific connection: `snow connection test -c admin`
3. If missing, add connection: `snow connection add --connection-name admin`

The framework requires valid Snowflake CLI connections to operate.
Your connection configuration is separate from the framework."
```

**DDL Execution Error**:
```
User: "Getting 'SQL compilation error' during deployment"

AI Response:
"This is an issue with your DDL content, not the framework. The framework
executes your SQL files unchanged, so we need to debug the SQL:

1. Test the failing SQL directly: `snow sql -c admin -q 'YOUR SQL HERE'`
2. Check for syntax errors in your DDL file
3. Verify object dependencies are created in the right order

Would you like me to examine your DDL file for common issues?"
```

## AI Testing and Validation

### Framework Integration Testing

AI systems should test framework integration by:

```bash
# Test framework availability
./scripts/orchestrate_modern.sh --help

# Test connection resolution
source scripts/lib/connection_resolver.sh
connection=$(resolve_connection_with_capability admin --explicit-connection test)

# Test with minimal DDL
echo "SELECT 1;" > test.sql
echo "test.sql" > test-manifest.txt
./scripts/orchestrate_modern.sh \
  --ddl-dir . \
  --manifest test-manifest.txt \
  --file test.sql \
  --connection test
```

### Boundary Validation

AI systems must verify they maintain boundaries:

```python
def validate_ai_framework_usage():
    """Self-check for AI systems using the framework"""
    
    checks = {
        "modifies_ddl_content": False,  # Must remain False
        "creates_domain_config": False,  # Must remain False  
        "bypasses_connection_resolution": False,  # Must remain False
        "hardcodes_business_logic": False,  # Must remain False
        "uses_explicit_parameters": True,  # Must remain True
        "preserves_user_control": True,  # Must remain True
    }
    
    for check, expected in checks.items():
        actual = evaluate_behavior(check)
        assert actual == expected, f"Boundary violation: {check}"
    
    return "✅ AI framework usage follows architectural boundaries"
```

## Summary for AI Systems

**Framework Purpose**: Pure orchestration of user's DDL across Snowflake accounts

**AI Role**: Assistant for deployment operations, not DDL generation or modification

**Key Principles**:
1. **Preserve user control** - Never modify user's DDL content
2. **Maintain boundaries** - Framework handles orchestration, user handles business logic  
3. **Enable flexibility** - Support any DDL project, any Snowflake account
4. **Provide guidance** - Help users understand framework capabilities and limitations

**Success Metrics**:
- AI suggestions maintain clean architectural separation
- User retains full control over DDL content and business logic
- Framework usage enables deployment without compromising design principles
- Documentation and guidance prevent architectural violations