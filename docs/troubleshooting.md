# Framework Troubleshooting Guide

> **Common issues and debugging approaches for the domain-agnostic Snowflake framework**

## Quick Diagnosis

### Framework Component Issues

**Symptom**: `scripts/orchestrate_modern.sh: command not found`  
**Cause**: Framework not installed or not executable  
**Solution**: [Framework Installation](#framework-installation-issues)

**Symptom**: `ERROR [orchestrate_modern] DDL directory is required`  
**Cause**: Missing required parameters  
**Solution**: [Parameter Configuration](#parameter-configuration-issues)

**Symptom**: `Failed to resolve connection: admin`  
**Cause**: Connection configuration problem  
**Solution**: [Connection Issues](#connection-resolution-issues)

**Symptom**: `SQL compilation error: Object does not exist`  
**Cause**: DDL dependency issue or missing objects  
**Solution**: [DDL Execution Issues](#ddl-execution-issues)

## Framework Installation Issues

### Issue: Framework Components Missing

**Symptoms**:
```bash
$ scripts/orchestrate_modern.sh --help
bash: scripts/orchestrate_modern.sh: No such file or directory
```

**Root Cause**: Framework files not copied to project

**Solution**:
```bash
# Check current directory structure
ls -la scripts/

# Copy framework components (adjust source path)
mkdir -p scripts/lib/
cp path/to/framework/scripts/orchestrate_modern.sh scripts/
cp path/to/framework/scripts/lib/connection_resolver.sh scripts/lib/

# Make executable
chmod +x scripts/orchestrate_modern.sh
chmod +x scripts/lib/connection_resolver.sh

# Verify installation
scripts/orchestrate_modern.sh --help
```

### Issue: Permission Denied Errors

**Symptoms**:
```bash
$ scripts/orchestrate_modern.sh --help
bash: scripts/orchestrate_modern.sh: Permission denied
```

**Root Cause**: Framework scripts not executable

**Solution**:
```bash
# Fix permissions
chmod +x scripts/orchestrate_modern.sh
chmod +x scripts/lib/connection_resolver.sh

# Verify permissions
ls -la scripts/orchestrate_modern.sh
ls -la scripts/lib/connection_resolver.sh
```

## Parameter Configuration Issues

### Issue: Missing Required Parameters

**Symptoms**:
```bash
ERROR [orchestrate_modern] DDL directory is required. Use --ddl-dir DIR
ERROR [orchestrate_modern] Manifest file is required. Use --manifest FILE
ERROR [orchestrate_modern] Connection is required. Use --connection NAME
```

**Root Cause**: Framework requires explicit parameters (no defaults)

**Solution**:
```bash
# Wrong (missing parameters)
scripts/orchestrate_modern.sh --phase infra

# Correct (all required parameters)
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

### Issue: Invalid File Paths

**Symptoms**:
```bash
ERROR [orchestrate_modern] DDL directory not found: infrastructure/
ERROR [orchestrate_modern] Manifest file not found: scripts/manifest.txt
```

**Root Cause**: Incorrect path references or missing files

**Solution**:
```bash
# Verify directory structure
ls -la infrastructure/
ls -la scripts/manifest.txt

# Check current working directory
pwd

# Ensure paths are relative to repository root
# Correct path format:
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

### Issue: Invalid Phase Names

**Symptoms**:
```bash
ERROR [orchestrate_modern] Unknown phase: infrastructure
```

**Root Cause**: Invalid phase parameter

**Solution**:
```bash
# Valid phase names
--phase infra          # Execute infrastructure DDL
--phase bootstrap      # Execute Git integration setup  
--phase all            # Execute infrastructure + bootstrap
--phase down           # Execute teardown (drop scripts)

# Example with correct phase
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

## Connection Resolution Issues

### Issue: Connection Not Found

**Symptoms**:
```bash
ERROR [orchestrate_modern] Failed to resolve connection: admin
```

**Root Cause**: Connection not configured in Snowflake CLI

**Diagnosis**:
```bash
# List available connections
snow connection list

# Test specific connection
snow connection test -c admin
```

**Solution**:
```bash
# Add missing connection
snow connection add \
  --connection-name admin \
  --account your-account \
  --user admin-user \
  --private-key-path ~/.snowflake/rsa_key.p8

# Verify connection works
snow connection test -c admin

# Test with framework
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

### Issue: Connection Authentication Failures

**Symptoms**:
```bash
Authentication failed: Invalid username/password
Certificate verification failed
```

**Root Cause**: Invalid connection credentials

**Diagnosis**:
```bash
# Check connection configuration
cat ~/.snowflake/config.toml

# Test connection independently
snow connection test -c admin --verbose
```

**Solution**:
```bash
# Verify private key format and path
openssl rsa -in ~/.snowflake/rsa_key.p8 -check

# Update connection with correct credentials
snow connection add \
  --connection-name admin \
  --account correct-account \
  --user correct-user \
  --private-key-path ~/.snowflake/rsa_key.p8 \
  --replace

# Test updated connection
snow connection test -c admin
```

### Issue: Connection Capability Validation Failures

**Symptoms**:
```bash
ERROR: Connection 'admin' lacks required admin capabilities
```

**Root Cause**: Connection user lacks required permissions

**Diagnosis**:
```bash
# Check user grants
snow sql -c admin -q "SHOW GRANTS TO USER current_user();"

# Check role grants  
snow sql -c admin -q "SHOW GRANTS TO ROLE current_role();"
```

**Solution**:
```bash
# Grant required permissions (run as ACCOUNTADMIN)
# For admin capability:
GRANT CREATE DATABASE, CREATE ROLE, CREATE WAREHOUSE ON ACCOUNT TO ROLE admin_role;
GRANT ROLE admin_role TO USER admin_user;

# For loader capability:
GRANT USAGE ON DATABASE artwork_db TO ROLE loader_role;
GRANT CREATE TABLE ON SCHEMA artwork_db.bronze TO ROLE loader_role;

# Test capability validation
source scripts/lib/connection_resolver.sh
validate_connection_capability admin admin
```

## DDL Execution Issues

### Issue: SQL Compilation Errors

**Symptoms**:
```bash
ERROR [orchestrate_modern] Script execution failed: create_databases.sql
SQL compilation error: Object 'ARTWORK_DB' does not exist
```

**Root Cause**: DDL dependency issues or object reference errors

**Diagnosis**:
```bash
# Test SQL file independently
snow sql -c admin --filename infrastructure/create_databases.sql

# Check for dependency issues in manifest order
cat scripts/manifest.txt
```

**Solution**:
```bash
# Fix manifest ordering (dependencies first)
# Wrong order:
infrastructure/create_schemas.sql    # Depends on database
infrastructure/create_databases.sql  # Creates database

# Correct order:  
infrastructure/create_databases.sql  # Creates database first
infrastructure/create_schemas.sql    # Depends on database

# Test individual scripts
snow sql -c admin --filename infrastructure/create_databases.sql
snow sql -c admin --filename infrastructure/create_schemas.sql
```

### Issue: Permission Denied During DDL Execution

**Symptoms**:
```bash
SQL execution error: Insufficient privileges to operate on database 'ARTWORK_DB'
```

**Root Cause**: Connection user lacks required DDL permissions

**Diagnosis**:
```bash
# Check current role and grants
snow sql -c admin -q "SELECT CURRENT_ROLE();"
snow sql -c admin -q "SHOW GRANTS TO ROLE current_role();"
```

**Solution**:
```bash
# Grant DDL permissions (run as appropriate admin role)
GRANT CREATE DATABASE ON ACCOUNT TO ROLE admin_role;
GRANT CREATE SCHEMA ON DATABASE artwork_db TO ROLE admin_role;

# Use appropriate role in connection
snow connection add \
  --connection-name admin \
  --role ACCOUNTADMIN \
  --account your-account \
  --user admin-user \
  --private-key-path ~/.snowflake/rsa_key.p8 \
  --replace
```

### Issue: Object Already Exists Errors

**Symptoms**:
```bash
SQL execution error: Object 'ARTWORK_DB' already exists
```

**Root Cause**: Non-idempotent DDL operations

**Solution**:
```bash
# Update DDL to be idempotent
# Wrong:
CREATE DATABASE ARTWORK_DB;

# Correct:
CREATE DATABASE IF NOT EXISTS ARTWORK_DB;

# Or use replace semantics:
CREATE OR REPLACE VIEW artwork_db.silver.clean_artworks AS
SELECT * FROM artwork_db.bronze.raw_artworks;
```

## Manifest Configuration Issues

### Issue: Script Not Found in Manifest

**Symptoms**:
```bash
ERROR [orchestrate_modern] Script not found: create_databases.sql
```

**Root Cause**: Manifest paths don't match actual file locations

**Diagnosis**:
```bash
# Check manifest content
cat scripts/manifest.txt

# Verify files exist at specified paths
ls -la infrastructure/create_databases.sql
```

**Solution**:
```bash
# Fix manifest paths (relative to repository root)
# Wrong (filename only):
create_databases.sql

# Correct (full relative path):
infrastructure/create_databases.sql

# Verify manifest format
cat scripts/manifest.txt
```

### Issue: Scripts Execute in Wrong Phase

**Symptoms**: Infrastructure scripts not executing during `--phase infra`

**Root Cause**: Directory-based phase filtering not matching expected paths

**Diagnosis**:
```bash
# Check phase directory mapping
--phase infra     → infrastructure/ directory
--phase bootstrap → git-setup/ directory

# Verify your directory structure matches expectations
ls -la infrastructure/
ls -la git-setup/
```

**Solution**:
```bash
# Organize scripts into correct directories
mkdir -p infrastructure/ git-setup/

# Move scripts to appropriate directories
mv create_databases.sql infrastructure/
mv create_git_integration.sql git-setup/

# Update manifest with correct paths
cat > scripts/manifest.txt << 'EOF'
infrastructure/create_databases.sql
infrastructure/create_schemas.sql
git-setup/create_git_integration.sql
EOF
```

## Multi-Account Configuration Issues

### Issue: Account-Specific Hardcoding

**Symptoms**: Deployment works in dev but fails in prod due to hardcoded references

**Root Cause**: DDL contains environment-specific naming

**Diagnosis**:
```bash
# Search for environment-specific references
grep -r "PROD_\|DEV_\|STAGING_" infrastructure/
```

**Solution**:
```bash
# Remove environment prefixes from DDL
# Wrong:
CREATE DATABASE PROD_ARTWORK_DB;

# Correct:
CREATE DATABASE ARTWORK_DB;

# Use connection context for environment separation
# Deploy to different accounts with same DDL
scripts/orchestrate_modern.sh --connection prod-admin --ddl-dir infrastructure/
scripts/orchestrate_modern.sh --connection dev-admin --ddl-dir infrastructure/
```

### Issue: Cross-Account Permission Problems

**Symptoms**: Works with one connection but fails with another

**Root Cause**: Different permission models across accounts

**Diagnosis**:
```bash
# Compare grants across connections
snow sql -c dev-admin -q "SHOW GRANTS TO USER current_user();"
snow sql -c prod-admin -q "SHOW GRANTS TO USER current_user();"
```

**Solution**:
```bash
# Standardize permissions across accounts
# Ensure consistent role hierarchy and grants
# Document minimum required permissions for framework
```

## Framework Component Debugging

### Issue: Connection Resolver Problems

**Symptoms**: Connection resolution hangs or behaves unexpectedly

**Debug Mode**:
```bash
# Enable debug logging
export SNOW_DEBUG=true

# Test connection resolution directly
source scripts/lib/connection_resolver.sh
connection=$(resolve_connection_with_capability admin)
echo "Resolved: $connection"

# Check session cache
ls -la /tmp/snowflake_framework_connection_cache_*
```

**Cache Issues**:
```bash
# Clear session cache to force fresh resolution
source scripts/lib/connection_resolver.sh
clear_session_cache

# Test fresh resolution
connection=$(resolve_connection_with_capability admin)
```

### Issue: Orchestration Logic Problems

**Symptoms**: Scripts execute in wrong order or phase filtering doesn't work

**Debug Approach**:
```bash
# Test manifest parsing
while IFS= read -r line; do
    echo "Processing: $line"
done < scripts/manifest.txt

# Test phase filtering logic
ddl_dir="infrastructure"
phase="infra"
script_path="infrastructure/create_databases.sql"
script_phase=$(dirname "$script_path")
echo "Script phase: $script_phase, Target phase: $phase"
```

## Performance and Scaling Issues

### Issue: Slow Connection Resolution

**Symptoms**: Long delays during connection prompts

**Solution**:
```bash
# Use explicit connections to bypass resolution
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection explicit-connection-name

# Or set default connection
snow connection set-default admin
```

### Issue: Large DDL Deployments Timing Out

**Symptoms**: Deployment fails on large schema deployments

**Solution**:
```bash
# Deploy in smaller phases
# Break large deployments into chunks
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --from create_warehouses.sql \
  --connection admin

# Use partial deployment to resume from specific script
```

## Getting Help

### Framework-Specific Issues

1. **Check Framework Version**:
   ```bash
   scripts/orchestrate_modern.sh --help | grep -A2 "Framework"
   ```

2. **Review Framework Documentation**:
   - [`README.md`](./README.md) - Quick start guide
   - [`architecture.md`](./architecture.md) - Design principles  
   - [`api-reference.md`](./api-reference.md) - Complete interface documentation

3. **Test Framework Components**:
   ```bash
   # Test connection resolution
   source scripts/lib/connection_resolver.sh
   list_available_connections
   
   # Test orchestration help
   scripts/orchestrate_modern.sh --help
   ```

### Snowflake CLI Issues

1. **Check Snowflake CLI Installation**:
   ```bash
   snow --version
   snow connection list
   snow connection test -c admin
   ```

2. **Review Snowflake Documentation**:
   - [Snowflake CLI Documentation](https://docs.snowflake.com/en/developer-guide/snowflake-cli)
   - [Connection Configuration](https://docs.snowflake.com/en/developer-guide/snowflake-cli/connecting/specify-credentials)

### DDL and SQL Issues

1. **Test SQL Independently**:
   ```bash
   # Test problematic SQL file directly
   snow sql -c admin --filename infrastructure/problematic_script.sql
   ```

2. **Review Snowflake SQL Documentation**:
   - [Snowflake SQL Reference](https://docs.snowflake.com/en/sql-reference)
   - [DDL Commands](https://docs.snowflake.com/en/sql-reference/ddl)

## Prevention Strategies

### Framework Best Practices

1. **Test Early and Often**
   - Test framework installation before major deployments
   - Validate connections before critical operations
   - Use test accounts for framework validation

2. **Maintain Clean Boundaries**
   - Keep user DDL separate from framework logic
   - Use account-agnostic DDL patterns
   - Document dependencies clearly in manifest files

3. **Monitor for Common Anti-Patterns**
   - Environment-specific hardcoding in DDL
   - Non-idempotent operations
   - Missing error handling in custom scripts

### Deployment Safety

1. **Connection Validation**
   ```bash
   # Always test connections before deployment
   snow connection test -c $CONNECTION_NAME
   validate_connection_capability $CONNECTION_NAME admin
   ```

2. **Staged Deployments**
   ```bash
   # Deploy to test environment first
   scripts/orchestrate_modern.sh --connection test-admin --phase infra
   
   # Validate results before production
   # Then deploy to production
   scripts/orchestrate_modern.sh --connection prod-admin --phase infra
   ```

3. **Backup Strategies**
   ```bash
   # Document rollback procedures
   # Test drop scripts before relying on them
   # Maintain deployment logs for troubleshooting
   ```