# Framework API Reference

> **Complete CLI interface and component library documentation**

## CLI Tools

### `orchestrate_modern.sh` - Main Orchestration Interface

**Purpose**: Pure file orchestration for DDL deployment across any Snowflake account

#### Syntax
```bash
scripts/orchestrate_modern.sh [OPTIONS]
```

#### Required Parameters
- `--ddl-dir DIR` - Directory containing DDL scripts  
- `--manifest FILE` - File listing scripts in execution order
- `--phase PHASE` - Deployment phase to execute
- `--connection CONN` - Snowflake connection name

#### Optional Parameters  
- `--from SCRIPT` - Start execution from specific script
- `--file FILE` - Execute/rollback single script (legacy compatibility)
- `--help` - Show usage information

#### Phases
- `infra` - Execute infrastructure DDL (databases, roles, warehouses)
- `bootstrap` - Execute Git integration setup scripts
- `all` - Execute infrastructure then bootstrap phases  
- `down` - Execute teardown using paired drop scripts

#### Examples

**Basic Infrastructure Deployment**
```bash
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

**Multi-Account Deployment**
```bash
# Production account
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase all \
  --connection prod-admin

# Staging account  
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase all \
  --connection staging-admin
```

**Partial Deployment**
```bash
# Start from specific script
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --from create_warehouses.sql \
  --connection admin
```

**Single Script Operations**
```bash
# Apply single script
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --file create_stages.sql \
  --connection admin
```

#### Exit Codes
- `0` - Success
- `1` - Configuration error (missing parameters, invalid paths)
- `2` - Connection resolution failure
- `3` - DDL execution failure

#### Error Messages

**Missing Required Parameters**
```
ERROR [orchestrate_modern] DDL directory is required. Use --ddl-dir DIR
ERROR [orchestrate_modern] Manifest file is required. Use --manifest FILE  
ERROR [orchestrate_modern] Connection is required. Use --connection NAME
```

**File System Errors**
```
ERROR [orchestrate_modern] DDL directory not found: infrastructure/
ERROR [orchestrate_modern] Manifest file not found: scripts/manifest.txt
ERROR [orchestrate_modern] Script not found: infrastructure/create_databases.sql
```

**Execution Errors**  
```
ERROR [orchestrate_modern] Failed to resolve connection: prod-admin
ERROR [orchestrate_modern] Script execution failed: create_databases.sql
ERROR [orchestrate_modern] Paired drop script not found: drop_databases.sql
```

## Framework Components

### Connection Resolver Library

**Source**: `scripts/lib/connection_resolver.sh`

#### `resolve_connection_with_capability()`

**Purpose**: Universal connection resolution with priority-based selection

**Syntax**:
```bash
connection=$(resolve_connection_with_capability CAPABILITY [EXPLICIT_CONNECTION])
```

**Parameters**:
- `CAPABILITY` - Required capability: `admin|loader|transformer|any`
- `EXPLICIT_CONNECTION` - Optional explicit connection name (bypasses resolution)

**Resolution Priority**:
1. Explicit CLI parameter (no confirmation)
2. Active config.toml default (with confirmation + session cache)  
3. Environment variables (with confirmation + session cache)
4. Capability-based fallback (with confirmation + session cache)

**Examples**:
```bash
# Resolve admin-capable connection
connection=$(resolve_connection_with_capability admin)

# Use explicit connection (bypasses resolution)
connection=$(resolve_connection_with_capability admin "prod-admin")

# Resolve any connection  
connection=$(resolve_connection_with_capability any)
```

**Session Caching**: Once confirmed, connection choice cached for session scope (`$$` process ID)

#### `validate_connection_capability()`

**Purpose**: Validates connection has required permissions for operations

**Syntax**:
```bash
validate_connection_capability CONNECTION_NAME CAPABILITY
```

**Parameters**:
- `CONNECTION_NAME` - Snowflake CLI connection name
- `CAPABILITY` - Required capability: `admin|loader|transformer|any`

**Capability Tests**:
- `admin` - CREATE DATABASE, CREATE ROLE, GRANT permissions
- `loader` - INSERT INTO Bronze tables, CREATE TEMPORARY objects  
- `transformer` - SELECT from Bronze, CREATE/INSERT Silver/Gold tables
- `any` - Basic connectivity test only

**Examples**:
```bash
# Test admin capabilities
if validate_connection_capability "prod-admin" "admin"; then
    echo "Connection has admin privileges"
fi

# Test loader capabilities
validate_connection_capability "etl-service" "loader" || {
    echo "ERROR: Connection lacks required loader permissions"
    exit 1
}
```

#### `list_available_connections()`

**Purpose**: Display available connections with status information

**Syntax**:
```bash
list_available_connections
```

**Output**: Formatted table via `snow connection list` with management commands

#### `clear_session_cache()`

**Purpose**: Clear session-scoped connection cache to force fresh resolution

**Syntax**:
```bash
clear_session_cache
```

**Use Cases**:
- Force fresh connection prompt after switching contexts
- Clear cache after connection configuration changes
- Debugging connection resolution issues

### Internal Helper Functions

#### Connection Resolution Helpers

**`_get_session_cache()`** - Retrieve cached connection for current session  
**`_set_session_cache(CONNECTION)`** - Store connection choice in session cache  
**`_get_default_connection()`** - Get default connection from config.toml  
**`_get_fallback_connection(CAPABILITY)`** - Get capability-based fallback  

#### Capability Validation Helpers

**`_validate_admin_capability(CONNECTION)`** - Test admin permissions  
**`_validate_loader_capability(CONNECTION)`** - Test data loading permissions  
**`_validate_transformer_capability(CONNECTION)`** - Test data transformation permissions  
**`_validate_basic_connectivity(CONNECTION)`** - Test basic connection only  

#### User Interaction Helpers

**`_confirm_connection_choice(SOURCE, CONNECTION, DEFAULT)`** - Prompt user for connection confirmation  
**`_log_info(MESSAGE)`** - Output informational message  
**`_log_error(MESSAGE)`** - Output error message  
**`_log_debug(MESSAGE)`** - Output debug message (if debug enabled)  

## Integration Patterns

### Makefile Integration

```makefile
# Standard framework integration
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

# Multi-account support
deploy-prod:
	$(MAKE) infra CONN=prod-admin
	$(MAKE) bootstrap CONN=prod-admin

deploy-staging:  
	$(MAKE) infra CONN=staging-admin
	$(MAKE) bootstrap CONN=staging-admin
```

### Shell Script Integration

```bash
#!/usr/bin/env bash
# Example deployment script using framework

set -euo pipefail

# Source connection resolver
source scripts/lib/connection_resolver.sh

# Resolve connection with confirmation
connection=$(resolve_connection_with_capability admin)

# Validate connection before proceeding
if ! validate_connection_capability "$connection" admin; then
    echo "ERROR: Connection lacks admin privileges"
    exit 1
fi

# Deploy infrastructure
scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/ \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$connection"

echo "Deployment completed to account: $connection"
```

### CI/CD Pipeline Integration

```yaml
# GitHub Actions example
deploy-snowflake:
  steps:
    - name: Setup Snowflake CLI
      run: |
        curl -sSfL https://github.com/Snowflake-Labs/snowflake-cli/releases/latest/download/snowflake-cli-linux-x64.tar.gz | tar xz
        sudo mv snowflake /usr/local/bin/snow
        
    - name: Configure connection
      run: |
        snow connection add \
          --connection-name ci-admin \
          --account ${{ secrets.SNOWFLAKE_ACCOUNT }} \
          --user ${{ secrets.SNOWFLAKE_USER }} \
          --private-key-path /tmp/private_key.pem
          
    - name: Deploy infrastructure  
      run: |
        scripts/orchestrate_modern.sh \
          --ddl-dir infrastructure/ \
          --manifest scripts/manifest.txt \
          --phase infra \
          --connection ci-admin
```

## Environment Variables

### Framework Behavior
- `SNOW_CONNECTION` - Default connection name (resolved with confirmation)
- `SNOW_DEBUG` - Enable debug logging (`1` or `true`)

### Snowflake CLI Configuration
- `SNOWFLAKE_CONFIG_PATH` - Override config.toml location  
- `SNOWFLAKE_ACCOUNT` - Account identifier override
- `SNOWFLAKE_USER` - User name override

## Configuration Files

### Connection Configuration (`~/.snowflake/config.toml`)

```toml
[connections.admin]
account = "your-account"  
user = "admin-user"
private_key_path = "~/.snowflake/rsa_key.p8"

[connections.loader]
account = "your-account"
user = "etl-service"  
private_key_path = "~/.snowflake/etl_key.p8"

[connections.prod-admin]
account = "prod-account"
user = "admin-user"
private_key_path = "~/.snowflake/prod_key.p8"
```

### Manifest File Format (`scripts/manifest.txt`)

```
# Infrastructure phase
infrastructure/create_databases.sql
infrastructure/create_schemas.sql  
infrastructure/create_roles.sql
infrastructure/create_warehouses.sql
infrastructure/create_grants.sql

# Bootstrap phase  
git-setup/create_git_integration.sql
git-setup/create_git_repository.sql
```

**Format Rules**:
- One script path per line
- Comments start with `#` 
- Blank lines ignored
- Phase determined by directory prefix
- Scripts executed in listed order

## Migration from Legacy `orchestrate.sh`

### Command Translation

| Legacy Command | Modern Equivalent |
|---|---|
| `scripts/orchestrate.sh --phase infra --connection admin` | `scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase infra --connection admin` |
| `scripts/orchestrate.sh --phase bootstrap --connection admin` | `scripts/orchestrate_modern.sh --ddl-dir git-setup/ --manifest scripts/manifest.txt --phase bootstrap --connection admin` |
| `scripts/orchestrate.sh --phase all --connection admin` | `scripts/orchestrate_modern.sh --ddl-dir infrastructure/ --manifest scripts/manifest.txt --phase all --connection admin` |

### Key Differences

1. **Explicit Parameters**: Modern version requires explicit `--ddl-dir` and `--manifest`
2. **No Defaults**: No implicit directory or file assumptions  
3. **Connection Resolution**: Enhanced connection management with confirmation
4. **Error Handling**: More detailed error messages with actionable guidance

### Migration Checklist

- [ ] Update Makefile targets to use `orchestrate_modern.sh`
- [ ] Add explicit `--ddl-dir` and `--manifest` parameters
- [ ] Test connection resolution with new confirmation prompts  
- [ ] Validate identical deployment behavior
- [ ] Update CI/CD scripts with new parameter format
- [ ] Train team on new explicit parameter requirements