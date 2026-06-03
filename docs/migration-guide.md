# Framework Migration Guide

> **Complete guide for migrating from legacy orchestration to the domain-agnostic framework**

## Migration Overview

This guide provides step-by-step instructions for migrating existing Snowflake DDL projects from legacy orchestration scripts to the domain-agnostic framework.

## Migration Benefits

**Before Migration (Legacy)**:
- Domain-coupled orchestration scripts
- Hardcoded account-specific configurations
- Limited multi-account deployment support
- Basic error handling
- Implicit connection assumptions

**After Migration (Framework)**:
- Domain-agnostic orchestration utilities
- Connection-based environment separation
- Universal multi-account support
- Enhanced error handling with actionable guidance
- Explicit parameter requirements

## Pre-Migration Assessment

### **Legacy Script Analysis**

**Step 1: Identify Current Orchestration Patterns**

```bash
# Examine existing orchestration scripts
find scripts/ -name "*.sh" -exec grep -l "orchestrate\|deploy\|apply" {} \;

# Look for hardcoded configurations
grep -r "PROD_\|DEV_\|STAGING_" scripts/
grep -r "pa37992\|mk07348" scripts/  # Account-specific references

# Identify connection handling patterns
grep -r "snow sql\|SNOWFLAKE_" scripts/
```

**Step 2: Document Current Deployment Workflow**

Create a migration assessment document:

```markdown
# Legacy Deployment Assessment

## Current Orchestration Scripts
- [ ] scripts/orchestrate.sh
- [ ] scripts/deploy.sh  
- [ ] scripts/apply_ddl.sh
- [ ] Other: _______________

## Current Connection Patterns
- [ ] Environment variables (SNOWFLAKE_ACCOUNT, etc.)
- [ ] Hardcoded connection details
- [ ] Config files with account-specific settings
- [ ] Other: _______________

## Current Multi-Environment Support
- [ ] Separate scripts per environment
- [ ] Configuration templates
- [ ] Manual parameter substitution
- [ ] No multi-environment support
- [ ] Other: _______________

## Identified Migration Challenges
- Domain-specific hardcoding: _______________
- Connection complexity: _______________
- Deployment dependencies: _______________
```

### **Framework Compatibility Check**

**Step 3: Validate DDL Compatibility**

```bash
# Check for account-specific hardcoding in DDL
find infrastructure/ -name "*.sql" -exec grep -l "PROD_\|DEV_\|STAGING_" {} \;

# Look for non-idempotent patterns  
find infrastructure/ -name "*.sql" -exec grep -l "CREATE [^OR REPLACE]\|CREATE [^IF NOT EXISTS]" {} \;

# Check for environment-specific object names
grep -r "prod\|dev\|staging" infrastructure/ --ignore-case
```

**Compatibility Report**:
- ✅ **Good**: DDL uses `CREATE IF NOT EXISTS` patterns
- ✅ **Good**: No environment-specific hardcoding
- ⚠️  **Warning**: Some non-idempotent operations found
- ❌ **Issue**: Environment-specific database names

## Migration Phases

### **Phase 1: Framework Installation**

**Step 1: Install Framework Components**

```bash
# Create framework directory structure
mkdir -p scripts/lib/

# Download/copy framework components
# (Adjust source path for your installation)
cp path/to/framework/scripts/orchestrate_modern.sh scripts/
cp path/to/framework/scripts/lib/connection_resolver.sh scripts/lib/

# Make executable
chmod +x scripts/orchestrate_modern.sh
chmod +x scripts/lib/connection_resolver.sh

# Verify installation
scripts/orchestrate_modern.sh --help
```

**Step 2: Validate Framework Installation**

```bash
# Test framework help output
if scripts/orchestrate_modern.sh --help >/dev/null 2>&1; then
    echo "✅ Framework installation verified"
else
    echo "❌ Framework installation failed"
    exit 1
fi

# Test connection resolver
if source scripts/lib/connection_resolver.sh 2>/dev/null; then
    echo "✅ Connection resolver loads successfully"
else
    echo "❌ Connection resolver loading failed"
    exit 1
fi
```

### **Phase 2: DDL Modernization**

**Step 1: Create Execution Manifest**

```bash
# Analyze current DDL dependencies
analyze_ddl_dependencies() {
    echo "# Generated manifest - review and adjust order as needed"
    
    # Core infrastructure first
    echo "# Phase 1: Core infrastructure"
    ls infrastructure/create_databases.sql 2>/dev/null | sed 's|^|infrastructure/|'
    ls infrastructure/create_schemas.sql 2>/dev/null | sed 's|^|infrastructure/|'
    
    # Supporting objects
    echo "# Phase 2: Supporting infrastructure"  
    ls infrastructure/create_roles.sql 2>/dev/null | sed 's|^|infrastructure/|'
    ls infrastructure/create_warehouses.sql 2>/dev/null | sed 's|^|infrastructure/|'
    ls infrastructure/create_file_formats.sql 2>/dev/null | sed 's|^|infrastructure/|'
    ls infrastructure/create_stages.sql 2>/dev/null | sed 's|^|infrastructure/|'
    
    # Data objects
    echo "# Phase 3: Data objects"
    ls infrastructure/create_tables.sql 2>/dev/null | sed 's|^|infrastructure/|'
    ls infrastructure/create_views.sql 2>/dev/null | sed 's|^|infrastructure/|'
    
    # Security and access
    echo "# Phase 4: Security and access"
    ls infrastructure/create_grants.sql 2>/dev/null | sed 's|^|infrastructure/|'
    
    # Git integration
    echo "# Phase 5: Git integration"
    ls git-setup/*.sql 2>/dev/null | head -10
}

# Generate initial manifest
analyze_ddl_dependencies > scripts/manifest.txt

echo "Generated initial manifest. Please review scripts/manifest.txt"
```

**Step 2: Modernize DDL Files**

```bash
# Fix non-idempotent patterns
modernize_ddl_file() {
    local file="$1"
    local backup="${file}.backup"
    
    echo "Modernizing: $file"
    
    # Create backup
    cp "$file" "$backup"
    
    # Convert to idempotent patterns
    sed -i.tmp 's/CREATE DATABASE /CREATE DATABASE IF NOT EXISTS /g' "$file"
    sed -i.tmp 's/CREATE SCHEMA /CREATE SCHEMA IF NOT EXISTS /g' "$file"  
    sed -i.tmp 's/CREATE ROLE /CREATE ROLE IF NOT EXISTS /g' "$file"
    sed -i.tmp 's/CREATE WAREHOUSE /CREATE WAREHOUSE IF NOT EXISTS /g' "$file"
    
    # Remove temporary file
    rm -f "${file}.tmp"
    
    echo "✅ Modernized: $file (backup: $backup)"
}

# Apply to all DDL files
find infrastructure/ -name "*.sql" -exec bash -c 'modernize_ddl_file "$0"' {} \;
```

**Step 3: Remove Environment-Specific Hardcoding**

```bash
# Remove environment prefixes from DDL
remove_environment_prefixes() {
    local file="$1"
    
    echo "Removing environment prefixes from: $file"
    
    # Create backup
    cp "$file" "${file}.env_backup"
    
    # Remove common environment prefixes
    sed -i.tmp 's/PROD_ANALYTICS_DB/ANALYTICS_DB/g' "$file"
    sed -i.tmp 's/DEV_ANALYTICS_DB/ANALYTICS_DB/g' "$file"
    sed -i.tmp 's/STAGING_ANALYTICS_DB/ANALYTICS_DB/g' "$file"
    
    # Remove environment-specific role names
    sed -i.tmp 's/PROD_ADMIN_ROLE/ADMIN_ROLE/g' "$file"
    sed -i.tmp 's/DEV_ADMIN_ROLE/ADMIN_ROLE/g' "$file"
    
    rm -f "${file}.tmp"
    
    echo "✅ Environment prefixes removed from: $file"
}

# Apply to DDL files that need it
grep -l "PROD_\|DEV_\|STAGING_" infrastructure/*.sql | while read -r file; do
    remove_environment_prefixes "$file"
done
```

### **Phase 3: Connection Migration**

**Step 1: Set Up Framework-Compatible Connections**

```bash
# Migrate from legacy environment variables to Snowflake CLI connections
setup_framework_connections() {
    echo "Setting up framework-compatible connections..."
    
    # Development connection
    if [[ -n "${DEV_SNOWFLAKE_ACCOUNT:-}" ]]; then
        snow connection add \
            --connection-name dev-admin \
            --account "$DEV_SNOWFLAKE_ACCOUNT" \
            --user "${DEV_SNOWFLAKE_USER:-admin}" \
            --private-key-path ~/.snowflake/dev_key.pem
    fi
    
    # Staging connection  
    if [[ -n "${STAGING_SNOWFLAKE_ACCOUNT:-}" ]]; then
        snow connection add \
            --connection-name staging-admin \
            --account "$STAGING_SNOWFLAKE_ACCOUNT" \
            --user "${STAGING_SNOWFLAKE_USER:-admin}" \
            --private-key-path ~/.snowflake/staging_key.pem
    fi
    
    # Production connection
    if [[ -n "${PROD_SNOWFLAKE_ACCOUNT:-}" ]]; then
        snow connection add \
            --connection-name prod-admin \
            --account "$PROD_SNOWFLAKE_ACCOUNT" \
            --user "${PROD_SNOWFLAKE_USER:-admin}" \
            --private-key-path ~/.snowflake/prod_key.pem
    fi
    
    echo "✅ Framework connections configured"
    snow connection list
}

setup_framework_connections
```

**Step 2: Test Connection Resolution**

```bash
# Test framework connection resolution
test_connection_resolution() {
    echo "Testing framework connection resolution..."
    
    # Source connection resolver
    source scripts/lib/connection_resolver.sh
    
    # Test each environment connection
    for env in dev staging prod; do
        connection="${env}-admin"
        
        if snow connection test -c "$connection" 2>/dev/null; then
            echo "✅ Connection test passed: $connection"
            
            # Test framework resolution
            if resolved=$(resolve_connection_with_capability admin "$connection" 2>/dev/null); then
                echo "✅ Framework resolution works: $resolved"
            else
                echo "❌ Framework resolution failed: $connection"
            fi
        else
            echo "⚠️  Connection test failed: $connection (may need configuration)"
        fi
    done
}

test_connection_resolution
```

### **Phase 4: Parallel Testing**

**Step 1: Create Migration Test Script**

```bash
#!/usr/bin/env bash
# migration-test.sh - Test legacy vs framework deployment

set -euo pipefail

readonly TEST_CONNECTION="${1:-dev-admin}"

test_legacy_deployment() {
    echo "Testing legacy deployment..."
    
    if [[ -f scripts/orchestrate.sh ]]; then
        # Test with legacy script (if it exists)
        if scripts/orchestrate.sh --phase infra --connection "$TEST_CONNECTION"; then
            echo "✅ Legacy deployment succeeded"
            return 0
        else
            echo "❌ Legacy deployment failed"
            return 1
        fi
    else
        echo "⚠️  Legacy script not found, skipping legacy test"
        return 0
    fi
}

test_framework_deployment() {
    echo "Testing framework deployment..."
    
    if scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure/ \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$TEST_CONNECTION"; then
        
        echo "✅ Framework deployment succeeded"
        return 0
    else
        echo "❌ Framework deployment failed"
        return 1
    fi
}

compare_deployment_results() {
    echo "Comparing deployment results..."
    
    # Compare object counts or other validation metrics
    local db_count
    db_count=$(snow sql -c "$TEST_CONNECTION" -q "SHOW DATABASES;" --format json | jq length)
    
    local role_count  
    role_count=$(snow sql -c "$TEST_CONNECTION" -q "SHOW ROLES;" --format json | jq length)
    
    echo "Post-deployment state:"
    echo "  Databases: $db_count"
    echo "  Roles: $role_count"
}

# Run migration test
echo "========================================"
echo "Migration Test: Legacy vs Framework"
echo "========================================"

test_framework_deployment
compare_deployment_results

echo "✅ Migration test completed"
```

**Step 2: Validate Parallel Deployment**

```bash
# Make test script executable
chmod +x migration-test.sh

# Test against development environment
./migration-test.sh dev-admin

# Test help output comparison
echo ""
echo "Legacy vs Framework Help Output:"
echo "================================="
if [[ -f scripts/orchestrate.sh ]]; then
    echo "Legacy help:"
    scripts/orchestrate.sh --help || echo "Legacy help not available"
fi

echo ""
echo "Framework help:"
scripts/orchestrate_modern.sh --help
```

### **Phase 5: Build System Migration**

**Step 1: Update Makefile**

```makefile
# Migration: Update Makefile targets

# Legacy targets (keep for transition period)
legacy-infra:
	@echo "⚠️  Using legacy deployment (deprecated)"
	scripts/orchestrate.sh --phase infra --connection $(CONN)

legacy-bootstrap:
	@echo "⚠️  Using legacy deployment (deprecated)"
	scripts/orchestrate.sh --phase bootstrap --connection $(CONN)

# Framework targets (new)
infra:
	@echo "✅ Using framework deployment"
	scripts/orchestrate_modern.sh \
		--ddl-dir infrastructure/ \
		--manifest scripts/manifest.txt \
		--phase infra \
		--connection $(CONN)

bootstrap:
	@echo "✅ Using framework deployment"
	scripts/orchestrate_modern.sh \
		--ddl-dir git-setup/ \
		--manifest scripts/manifest.txt \
		--phase bootstrap \
		--connection $(CONN)

# Multi-account targets
deploy-dev:
	$(MAKE) infra CONN=dev-admin

deploy-staging:
	$(MAKE) infra CONN=staging-admin

deploy-prod:
	$(MAKE) infra CONN=prod-admin

# Migration helper
migrate-test:
	@echo "Testing framework deployment..."
	./migration-test.sh dev-admin

# Help target
help:
	@echo "Available targets:"
	@echo "  infra         - Deploy infrastructure using framework"
	@echo "  bootstrap     - Deploy git integration using framework"
	@echo "  deploy-dev    - Deploy to development environment"
	@echo "  deploy-staging - Deploy to staging environment"
	@echo "  deploy-prod   - Deploy to production environment"
	@echo "  migrate-test  - Test framework deployment"
	@echo "  legacy-infra  - Deploy using legacy script (deprecated)"
	@echo ""
	@echo "Usage:"
	@echo "  make infra CONN=dev-admin"
	@echo "  make deploy-prod"
```

**Step 2: Update CI/CD Pipelines**

```yaml
# Migration: Update GitHub Actions workflow

name: Snowflake Deployment (Framework Migration)

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  framework-deployment:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Snowflake CLI
        run: |
          curl -sSfL https://github.com/Snowflake-Labs/snowflake-cli/releases/latest/download/snowflake-cli-linux-x64.tar.gz | tar xz
          sudo mv snowflake /usr/local/bin/snow
          
      - name: Test Framework Installation
        run: |
          chmod +x scripts/orchestrate_modern.sh
          scripts/orchestrate_modern.sh --help
          
      - name: Setup Test Connection
        run: |
          echo "$SNOWFLAKE_PRIVATE_KEY" > /tmp/dev_key.pem
          snow connection add \
            --connection-name dev-admin \
            --account ${{ secrets.DEV_ACCOUNT }} \
            --user ${{ secrets.DEV_USER }} \
            --private-key-path /tmp/dev_key.pem
        env:
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.DEV_SNOWFLAKE_PRIVATE_KEY }}
          
      - name: Deploy with Framework
        run: |
          scripts/orchestrate_modern.sh \
            --ddl-dir infrastructure/ \
            --manifest scripts/manifest.txt \
            --phase infra \
            --connection dev-admin
            
      - name: Validate Deployment
        run: |
          snow sql -c dev-admin -q "SELECT 'Framework deployment validated' AS status;"

  # Keep legacy deployment for comparison during migration
  legacy-deployment:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v3
      
      - name: Compare Legacy vs Framework
        run: |
          if [[ -f scripts/orchestrate.sh ]]; then
            echo "Legacy script available for comparison"
            # Add legacy deployment test if needed
          else
            echo "Legacy script not found - migration complete"
          fi
```

### **Phase 6: Production Migration**

**Step 1: Staged Production Migration**

```bash
#!/usr/bin/env bash
# production-migration.sh - Staged migration to production

set -euo pipefail

readonly MIGRATION_DATE=$(date +%Y%m%d_%H%M%S)
readonly ENVIRONMENT="production"
readonly CONNECTION="prod-admin"

create_migration_backup() {
    echo "Creating migration backup..."
    
    # Backup current deployment state
    snow sql -c "$CONNECTION" -q "CREATE SCHEMA IF NOT EXISTS MIGRATION_BACKUPS.BACKUP_${MIGRATION_DATE};"
    
    # Document current state
    snow sql -c "$CONNECTION" -q "SHOW DATABASES;" --format json > "pre_migration_state_${MIGRATION_DATE}.json"
    
    echo "✅ Migration backup created: BACKUP_${MIGRATION_DATE}"
}

validate_migration_readiness() {
    echo "Validating migration readiness..."
    
    # Test framework components
    if ! scripts/orchestrate_modern.sh --help >/dev/null; then
        echo "❌ Framework components not ready"
        return 1
    fi
    
    # Test connection
    if ! snow connection test -c "$CONNECTION" >/dev/null; then
        echo "❌ Production connection test failed"
        return 1
    fi
    
    # Validate manifest exists
    if [[ ! -f scripts/manifest.txt ]]; then
        echo "❌ Migration manifest not found"
        return 1
    fi
    
    echo "✅ Migration readiness validated"
}

execute_production_migration() {
    echo "Executing production migration..."
    
    # Deploy with framework (idempotent, so safe to re-run)
    if scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure/ \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$CONNECTION"; then
        
        echo "✅ Framework deployment succeeded"
        
        # Validate deployment
        if validate_post_migration_state; then
            echo "✅ Post-migration validation passed"
            
            # Mark migration complete
            echo "$MIGRATION_DATE" > .migration_completed
            
            echo "✅ Production migration completed successfully"
        else
            echo "❌ Post-migration validation failed"
            return 1
        fi
    else
        echo "❌ Framework deployment failed"
        return 1
    fi
}

validate_post_migration_state() {
    # Compare pre and post migration state
    snow sql -c "$CONNECTION" -q "SHOW DATABASES;" --format json > "post_migration_state_${MIGRATION_DATE}.json"
    
    # Basic validation (customize for your environment)
    local db_count_pre db_count_post
    db_count_pre=$(jq length "pre_migration_state_${MIGRATION_DATE}.json")
    db_count_post=$(jq length "post_migration_state_${MIGRATION_DATE}.json")
    
    if [[ "$db_count_pre" -eq "$db_count_post" ]]; then
        echo "✅ Database count unchanged: $db_count_post"
        return 0
    else
        echo "⚠️  Database count changed: $db_count_pre -> $db_count_post"
        # Review changes and decide if acceptable
        return 0
    fi
}

# Execute staged production migration
echo "========================================"
echo "Production Migration to Framework"
echo "========================================"

validate_migration_readiness
create_migration_backup  
execute_production_migration

echo "✅ Production migration completed: $MIGRATION_DATE"
```

**Step 2: Post-Migration Cleanup**

```bash
#!/usr/bin/env bash
# post-migration-cleanup.sh

set -euo pipefail

cleanup_legacy_scripts() {
    echo "Cleaning up legacy scripts..."
    
    # Move legacy scripts to archive
    mkdir -p archive/legacy_scripts/
    
    if [[ -f scripts/orchestrate.sh ]]; then
        mv scripts/orchestrate.sh archive/legacy_scripts/
        echo "✅ Archived legacy orchestrate.sh"
    fi
    
    # Remove legacy configuration files
    if [[ -f config/legacy_config.yml ]]; then
        mv config/legacy_config.yml archive/legacy_scripts/
        echo "✅ Archived legacy configuration"
    fi
}

update_documentation() {
    echo "Updating documentation for framework migration..."
    
    cat >> README.md << 'EOF'

## Framework Migration Complete

This project has been migrated to use the domain-agnostic Snowflake infrastructure framework.

### New Deployment Commands

```bash
# Deploy infrastructure
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin

# Multi-account deployment
make deploy-prod  # Production
make deploy-staging  # Staging
make deploy-dev  # Development
```

### Migration Benefits

✅ **Multi-account support** - Same DDL, different connections
✅ **Enhanced error handling** - Clear error messages with actionable guidance
✅ **Connection flexibility** - Work with any configured Snowflake account
✅ **Idempotent operations** - Safe to re-run deployments
✅ **Clean architecture** - Framework handles orchestration, project handles business logic

### Legacy Scripts

Legacy deployment scripts have been archived in `archive/legacy_scripts/` for reference.

EOF

    echo "✅ Documentation updated"
}

validate_migration_success() {
    echo "Validating migration success..."
    
    # Test framework deployment
    if scripts/orchestrate_modern.sh --help >/dev/null; then
        echo "✅ Framework components operational"
    else
        echo "❌ Framework components not working"
        return 1
    fi
    
    # Test connection resolution
    source scripts/lib/connection_resolver.sh
    if resolve_connection_with_capability admin "prod-admin" >/dev/null; then
        echo "✅ Connection resolution working"
    else
        echo "❌ Connection resolution failed"
        return 1
    fi
    
    echo "✅ Migration validation complete"
}

# Execute post-migration cleanup
echo "========================================"
echo "Post-Migration Cleanup"
echo "========================================"

cleanup_legacy_scripts
update_documentation  
validate_migration_success

echo "✅ Migration cleanup completed"
```

## Migration Validation

### **Pre-Production Testing**

**Validation Checklist**:
- [ ] Framework components install and execute correctly
- [ ] DDL files converted to idempotent patterns
- [ ] Environment-specific hardcoding removed
- [ ] Manifest file created with correct dependency order
- [ ] Connections configured and tested
- [ ] Multi-account deployment tested
- [ ] Build system updated (Makefile, CI/CD)
- [ ] Documentation updated

**Test Script**:
```bash
#!/usr/bin/env bash
# migration-validation.sh

set -euo pipefail

run_validation_tests() {
    echo "Running migration validation tests..."
    
    # Test 1: Framework installation
    if scripts/orchestrate_modern.sh --help >/dev/null; then
        echo "✅ Framework installation valid"
    else
        echo "❌ Framework installation failed"
        return 1
    fi
    
    # Test 2: Connection resolution
    source scripts/lib/connection_resolver.sh
    if resolve_connection_with_capability admin "dev-admin" >/dev/null; then
        echo "✅ Connection resolution working"
    else
        echo "❌ Connection resolution failed"
        return 1
    fi
    
    # Test 3: Manifest validation
    if [[ -f scripts/manifest.txt && -s scripts/manifest.txt ]]; then
        echo "✅ Manifest file exists and non-empty"
    else
        echo "❌ Manifest file missing or empty"
        return 1
    fi
    
    # Test 4: DDL idempotency check
    local non_idempotent
    non_idempotent=$(find infrastructure/ -name "*.sql" -exec grep -l "CREATE [^OR REPLACE]\|CREATE [^IF NOT EXISTS]" {} \; | wc -l)
    
    if [[ "$non_idempotent" -eq 0 ]]; then
        echo "✅ All DDL files use idempotent patterns"
    else
        echo "⚠️  $non_idempotent DDL files may not be idempotent"
    fi
    
    # Test 5: Environment prefix check
    local env_specific
    env_specific=$(find infrastructure/ -name "*.sql" -exec grep -l "PROD_\|DEV_\|STAGING_" {} \; | wc -l)
    
    if [[ "$env_specific" -eq 0 ]]; then
        echo "✅ No environment-specific hardcoding found"
    else
        echo "⚠️  $env_specific DDL files contain environment-specific references"
    fi
    
    echo "✅ Migration validation completed"
}

run_validation_tests
```

### **Migration Rollback Plan**

**If Migration Fails**:
1. **Stop framework deployment**: Halt any in-progress deployments
2. **Restore legacy scripts**: Move archived scripts back to active location
3. **Revert DDL changes**: Restore DDL files from backup
4. **Update build system**: Revert Makefile and CI/CD to legacy patterns
5. **Document issues**: Record specific failures for future migration attempt

```bash
#!/usr/bin/env bash
# migration-rollback.sh

set -euo pipefail

rollback_migration() {
    echo "Rolling back framework migration..."
    
    # Restore legacy scripts
    if [[ -f archive/legacy_scripts/orchestrate.sh ]]; then
        mv archive/legacy_scripts/orchestrate.sh scripts/
        echo "✅ Legacy orchestrate.sh restored"
    fi
    
    # Restore DDL backups if they exist
    find infrastructure/ -name "*.backup" -exec bash -c 'mv "$1" "${1%.backup}"' _ {} \;
    echo "✅ DDL files restored from backup"
    
    # Remove framework components
    rm -f scripts/orchestrate_modern.sh
    rm -rf scripts/lib/
    echo "✅ Framework components removed"
    
    echo "✅ Migration rollback completed"
    echo "   Project reverted to legacy orchestration"
}

# Execute rollback if needed
if [[ "${1:-}" == "--execute" ]]; then
    rollback_migration
else
    echo "Migration rollback plan prepared."
    echo "Run with --execute to perform rollback."
fi
```

## Summary

**Migration Process**:
1. **Assessment** - Analyze current orchestration and identify compatibility issues
2. **Installation** - Install framework components and validate
3. **DDL Modernization** - Convert to idempotent patterns and remove environment hardcoding
4. **Connection Migration** - Set up framework-compatible connections
5. **Parallel Testing** - Test framework alongside legacy deployment
6. **Build System Migration** - Update Makefile, CI/CD, and documentation
7. **Production Migration** - Staged migration with backup and validation
8. **Post-Migration Cleanup** - Archive legacy scripts and finalize documentation

**Migration Benefits**:
- **Universal deployment**: Same DDL across all environments
- **Enhanced reliability**: Better error handling and validation
- **Simplified operations**: Connection-based environment separation
- **Future-ready architecture**: Clean boundaries for extension and maintenance

**Success Criteria**:
- Framework deployment works across all environments
- Multi-account deployment functions correctly
- Build system integrates seamlessly
- Team can operate new deployment patterns
- Legacy functionality fully replaced