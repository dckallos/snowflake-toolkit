# Framework Integration Guide

> **Patterns for integrating the domain-agnostic framework with existing Snowflake DDL projects**

## Overview

This guide shows how to adopt the framework in existing Snowflake projects while maintaining clean separation between framework utilities and domain-specific DDL content.

## Integration Prerequisites

### Required Project Structure

Your existing project must provide:

```
your-project/
├── infrastructure/              # DDL files (your content)
│   ├── create_databases.sql
│   ├── create_schemas.sql
│   ├── create_roles.sql
│   └── ...
├── scripts/
│   └── manifest.txt            # Execution order (your definition)
└── ~/.snowflake/config.toml    # Connection configuration
```

### Required Snowflake CLI Setup

```bash
# Install Snowflake CLI
brew install snowflakedb/snowflake-cli/snowflake-cli

# Add connection(s)
snow connection add \
  --connection-name admin \
  --account your-account \
  --user admin-user \
  --private-key-path ~/.snowflake/rsa_key.p8

# Test connection
snow connection test -c admin
```

## Step-by-Step Integration

### Step 1: Add Framework Components

Copy framework files to your project:

```bash
# Create framework directory
mkdir -p scripts/lib/

# Copy framework components (adjust paths as needed)
cp path/to/framework/scripts/orchestrate_modern.sh scripts/
cp path/to/framework/scripts/lib/connection_resolver.sh scripts/lib/

# Make executable
chmod +x scripts/orchestrate_modern.sh
chmod +x scripts/lib/connection_resolver.sh
```

### Step 2: Create Manifest File

Create `scripts/manifest.txt` defining your DDL execution order:

```
# Infrastructure phase - core objects
infrastructure/create_databases.sql
infrastructure/create_schemas.sql
infrastructure/create_roles.sql
infrastructure/create_warehouses.sql
infrastructure/create_stages.sql
infrastructure/create_file_formats.sql
infrastructure/create_grants.sql

# Bootstrap phase - integration setup  
git-setup/create_git_integration.sql
git-setup/create_git_repository.sql
```

**Guidelines**:
- List scripts in dependency order
- Group by deployment phase using directory prefixes
- One script path per line
- Comments start with `#`

### Step 3: Test Framework Integration

Test the framework with your existing DDL:

```bash
# Test connection resolution
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin \
  --help

# Dry run (framework will prompt for confirmation)
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

### Step 4: Update Build System

#### Makefile Integration

Replace existing orchestration targets:

```makefile
# Framework-based targets
CONN ?= admin

infra:
	scripts/orchestrate_modern.sh \
		--ddl-dir infrastructure/ \
		--manifest scripts/manifest.txt \
		--phase infra \
		--connection $(CONN)

bootstrap:
	scripts/orchestrate_modern.sh \
		--ddl-dir git-setup/ \
		--manifest scripts/manifest.txt \
		--phase bootstrap \
		--connection $(CONN)

# Multi-account deployment
deploy-prod:
	$(MAKE) infra CONN=prod-admin

deploy-staging:  
	$(MAKE) infra CONN=staging-admin

# Legacy compatibility (during transition)
legacy-infra:
	scripts/orchestrate.sh --phase infra --connection $(CONN)
```

#### CI/CD Pipeline Updates

Update deployment scripts to use explicit parameters:

```yaml
# Before (legacy orchestrate.sh)
- name: Deploy infrastructure
  run: scripts/orchestrate.sh --phase infra --connection admin

# After (framework orchestration)  
- name: Deploy infrastructure
  run: |
    scripts/orchestrate_modern.sh \
      --ddl-dir infrastructure/ \
      --manifest scripts/manifest.txt \
      --phase infra \
      --connection admin
```

## Integration Patterns

### Pattern 1: Single Account Integration

**Use Case**: Existing project deploying to one Snowflake account

**Implementation**:
```bash
# Simple replacement of existing orchestration
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

**Benefits**:
- Enhanced error handling and logging
- Connection validation before deployment
- Session-scoped connection caching
- Backward compatibility with existing DDL

### Pattern 2: Multi-Account Integration  

**Use Case**: Deploy same DDL to multiple Snowflake accounts (dev/staging/prod)

**Connection Setup**:
```toml
# ~/.snowflake/config.toml
[connections.dev-admin]
account = "dev-account"
user = "admin-user"
private_key_path = "~/.snowflake/dev_key.p8"

[connections.staging-admin]  
account = "staging-account"
user = "admin-user"
private_key_path = "~/.snowflake/staging_key.p8"

[connections.prod-admin]
account = "prod-account"
user = "admin-user"  
private_key_path = "~/.snowflake/prod_key.p8"
```

**Deployment Script**:
```bash
#!/usr/bin/env bash
# deploy-to-all-environments.sh

set -euo pipefail

source scripts/lib/connection_resolver.sh

for env in dev staging prod; do
    echo "Deploying to ${env}..."
    
    connection="${env}-admin"
    
    # Validate connection before proceeding
    if ! validate_connection_capability "$connection" admin; then
        echo "ERROR: Connection $connection lacks admin privileges"
        exit 1
    fi
    
    # Deploy infrastructure
    scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure/ \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$connection"
        
    echo "✅ Deployed to ${env}"
done
```

### Pattern 3: Gradual Migration Integration

**Use Case**: Migrate from legacy orchestration gradually

**Phase 1 - Parallel Testing**:
```makefile
# Test new framework alongside legacy
test-framework:
	scripts/orchestrate_modern.sh \
		--ddl-dir infrastructure/ \
		--manifest scripts/manifest.txt \
		--phase infra \
		--connection test-admin

# Keep legacy for production
infra:
	scripts/orchestrate.sh --phase infra --connection admin
```

**Phase 2 - Feature Flag Migration**:
```makefile
USE_MODERN_ORCHESTRATOR ?= false

ifeq ($(USE_MODERN_ORCHESTRATOR),true)
infra:
	scripts/orchestrate_modern.sh \
		--ddl-dir infrastructure/ \
		--manifest scripts/manifest.txt \
		--phase infra \
		--connection $(CONN)
else
infra:
	scripts/orchestrate.sh --phase infra --connection $(CONN)
endif
```

**Phase 3 - Complete Migration**:
```makefile
# Legacy removed, framework only
infra:
	scripts/orchestrate_modern.sh \
		--ddl-dir infrastructure/ \
		--manifest scripts/manifest.txt \
		--phase infra \
		--connection $(CONN)
```

### Pattern 4: Custom Orchestration Integration

**Use Case**: Projects with custom deployment logic

**Framework as Library**:
```bash
#!/usr/bin/env bash
# custom-deploy.sh

set -euo pipefail

# Source framework utilities
source scripts/lib/connection_resolver.sh

# Custom pre-deployment logic
echo "Running custom pre-deployment checks..."
if ! ./scripts/validate-environment.sh; then
    echo "Environment validation failed"
    exit 1
fi

# Resolve connection with framework
connection=$(resolve_connection_with_capability admin)

# Custom deployment phases
echo "Deploying core infrastructure..."
scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/core/ \
    --manifest scripts/core-manifest.txt \
    --phase infra \
    --connection "$connection"

echo "Deploying domain-specific objects..."
scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/domain/ \
    --manifest scripts/domain-manifest.txt \
    --phase infra \
    --connection "$connection"

# Custom post-deployment logic  
echo "Running post-deployment validation..."
./scripts/validate-deployment.sh "$connection"
```

## DDL Compatibility Guidelines

### Framework-Compatible DDL Patterns

**✅ Good: Account-agnostic DDL**
```sql
-- Uses connection context, no hardcoded account references
CREATE DATABASE IF NOT EXISTS ARTWORK_DB;
CREATE SCHEMA IF NOT EXISTS ARTWORK_DB.BRONZE;

-- Uses roles defined in same project
GRANT USAGE ON DATABASE ARTWORK_DB TO ROLE ARTWORK_LOADER;
```

**✅ Good: Idempotent operations**
```sql
-- Safe to re-run
CREATE OR REPLACE VIEW ARTWORK_DB.SILVER.CLEAN_ARTWORKS AS
SELECT * FROM ARTWORK_DB.BRONZE.RAW_ARTWORKS
WHERE status = 'active';

-- Conditional creation
CREATE DATABASE IF NOT EXISTS ARTWORK_DB;
```

**❌ Avoid: Account-specific hardcoding**
```sql
-- Bad: Environment-specific names
CREATE DATABASE IF NOT EXISTS PROD_ARTWORK_DB;

-- Bad: Account-specific references
GRANT ROLE ARTWORK_ADMIN TO USER "PROD-ADMIN";
```

**❌ Avoid: Non-idempotent operations**
```sql
-- Bad: Will fail on re-run
CREATE DATABASE ARTWORK_DB;

-- Bad: Depends on external state
ALTER DATABASE ARTWORK_DB RENAME TO ARTWORK_DB_OLD;
```

### Manifest Organization Patterns

**Dependency-Based Ordering**:
```
# Create objects that others depend on first
infrastructure/create_databases.sql
infrastructure/create_schemas.sql
infrastructure/create_file_formats.sql

# Create objects that depend on previous ones
infrastructure/create_tables.sql
infrastructure/create_views.sql

# Set up permissions last
infrastructure/create_roles.sql
infrastructure/create_grants.sql
```

**Phase-Based Grouping**:
```
# Phase 1: Core infrastructure
infrastructure/create_databases.sql
infrastructure/create_schemas.sql
infrastructure/create_warehouses.sql

# Phase 2: Data objects  
infrastructure/create_stages.sql
infrastructure/create_file_formats.sql
infrastructure/create_tables.sql

# Phase 3: Security & access
infrastructure/create_roles.sql
infrastructure/create_grants.sql

# Phase 4: Integration setup
git-setup/create_git_integration.sql
git-setup/create_git_repository.sql
```

## Common Integration Issues

### Issue 1: Missing Required Parameters

**Error**: `ERROR [orchestrate_modern] DDL directory is required. Use --ddl-dir DIR`

**Solution**: Framework requires explicit parameters, no defaults:
```bash
# Wrong (legacy approach)
scripts/orchestrate_modern.sh --phase infra

# Correct (explicit parameters)
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

### Issue 2: Connection Resolution Failures

**Error**: `ERROR [orchestrate_modern] Failed to resolve connection: admin`

**Solution**: Verify connection configuration:
```bash
# Check available connections
snow connection list

# Test specific connection
snow connection test -c admin

# Add missing connection
snow connection add --connection-name admin --account your-account
```

### Issue 3: Manifest Format Issues  

**Error**: `ERROR [orchestrate_modern] Script not found: create_databases.sql`

**Solution**: Check manifest file paths are relative to repository root:
```bash
# Wrong (filename only)
create_databases.sql

# Correct (relative path from repo root)  
infrastructure/create_databases.sql
```

### Issue 4: Phase Directory Mismatches

**Error**: Scripts not executing during expected phase

**Solution**: Ensure directory prefixes match phase expectations:
- `infra` phase: Execute scripts in `infrastructure/` directory
- `bootstrap` phase: Execute scripts in `git-setup/` directory  
- `all` phase: Execute both infrastructure and bootstrap

## Validation and Testing

### Integration Validation Checklist

- [ ] Framework components copied and executable
- [ ] Manifest file created with correct script paths
- [ ] Connection configuration tested with `snow connection test`
- [ ] Framework help output displays correctly  
- [ ] Test deployment runs without errors
- [ ] Connection resolution prompts work as expected
- [ ] DDL execution produces expected Snowflake objects
- [ ] Build system updated to use framework
- [ ] CI/CD pipelines updated with explicit parameters

### Testing Approach

```bash
# 1. Test framework installation
scripts/orchestrate_modern.sh --help

# 2. Test connection resolution
source scripts/lib/connection_resolver.sh
connection=$(resolve_connection_with_capability admin)
echo "Resolved connection: $connection"

# 3. Test DDL validation (dry run)
# Framework will show what it would execute
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection test-admin

# 4. Test actual deployment to test environment
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection test-admin

# 5. Verify deployed objects
snow sql -c test-admin -q "SHOW DATABASES;"
snow sql -c test-admin -q "SHOW SCHEMAS IN DATABASE ARTWORK_DB;"
```

## Next Steps

After successful integration:

1. **Read**: [`deployment-patterns.md`](./deployment-patterns.md) for production deployment strategies
2. **Configure**: [`troubleshooting.md`](./troubleshooting.md) for common issue resolution
3. **Enhance**: [`testing-guide.md`](./testing-guide.md) for comprehensive validation approaches
4. **Scale**: Consider multi-account deployment patterns for larger environments