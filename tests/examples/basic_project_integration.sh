#!/usr/bin/env bash
# =============================================================================
# basic_project_integration.sh — Reference example showing framework integration
# =============================================================================
#
# PURPOSE: Complete example demonstrating framework integration with existing DDL project
# AUDIENCE: Engineers adopting the framework for their own Snowflake projects
# MAINTENANCE: Update when framework interfaces change
#
# This script demonstrates the complete integration process from setup through deployment.
# It serves as a working reference implementation for framework adoption.
#
# =============================================================================

set -euo pipefail

# Project configuration
readonly EXAMPLE_PROJECT_NAME="basic_snowflake_project"
readonly EXAMPLE_WORKSPACE="/tmp/${EXAMPLE_PROJECT_NAME}_demo"

# =============================================================================
# PROJECT SETUP - Creating Example DDL Project
# =============================================================================

setup_example_project() {
    echo "=========================================="
    echo "Setting up example Snowflake DDL project"
    echo "=========================================="
    
    # Clean up any existing workspace
    if [[ -d "$EXAMPLE_WORKSPACE" ]]; then
        echo "Cleaning up existing workspace..."
        rm -rf "$EXAMPLE_WORKSPACE"
    fi
    
    # Create project structure
    echo "Creating project structure..."
    mkdir -p "$EXAMPLE_WORKSPACE"
    cd "$EXAMPLE_WORKSPACE"
    
    # Create typical Snowflake project directory structure
    mkdir -p infrastructure
    mkdir -p git-setup
    mkdir -p scripts
    mkdir -p docs
    
    echo "✅ Project structure created at: $EXAMPLE_WORKSPACE"
}

create_example_ddl() {
    echo ""
    echo "Creating example DDL files..."
    
    # Create database and schema definitions
    cat > infrastructure/create_databases.sql << 'EOF'
-- Example project database
CREATE DATABASE IF NOT EXISTS MYCOMPANY_ANALYTICS
    COMMENT = 'Main analytics database for MyCompany';

-- Data classification
CREATE DATABASE IF NOT EXISTS MYCOMPANY_STAGING  
    COMMENT = 'Staging database for data ingestion';
EOF

    cat > infrastructure/create_schemas.sql << 'EOF'
-- Analytics schemas
CREATE SCHEMA IF NOT EXISTS MYCOMPANY_ANALYTICS.RAW
    COMMENT = 'Raw data ingestion layer';
    
CREATE SCHEMA IF NOT EXISTS MYCOMPANY_ANALYTICS.CLEAN
    COMMENT = 'Cleaned and validated data layer';
    
CREATE SCHEMA IF NOT EXISTS MYCOMPANY_ANALYTICS.MARTS
    COMMENT = 'Business-ready data marts';

-- Staging schemas
CREATE SCHEMA IF NOT EXISTS MYCOMPANY_STAGING.BRONZE
    COMMENT = 'Bronze layer - raw data landing';
EOF

    # Create role definitions
    cat > infrastructure/create_roles.sql << 'EOF'
-- Analytics roles
CREATE ROLE IF NOT EXISTS MYCOMPANY_ANALYTICS_ADMIN
    COMMENT = 'Admin role for analytics database';
    
CREATE ROLE IF NOT EXISTS MYCOMPANY_DATA_ENGINEER
    COMMENT = 'Data engineering role with transformation privileges';
    
CREATE ROLE IF NOT EXISTS MYCOMPANY_ANALYST
    COMMENT = 'Read-only access for business analysts';
    
CREATE ROLE IF NOT EXISTS MYCOMPANY_ETL_SERVICE
    COMMENT = 'Service role for ETL processes';
EOF

    # Create warehouse definitions
    cat > infrastructure/create_warehouses.sql << 'EOF'
-- Analytics warehouses
CREATE WAREHOUSE IF NOT EXISTS MYCOMPANY_ETL_WH
    WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    COMMENT = 'ETL processing warehouse';

CREATE WAREHOUSE IF NOT EXISTS MYCOMPANY_ANALYST_WH
    WITH
    WAREHOUSE_SIZE = 'SMALL' 
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Analyst query warehouse';
EOF

    # Create file format definitions
    cat > infrastructure/create_file_formats.sql << 'EOF'
-- Standard file formats
CREATE OR REPLACE FILE FORMAT MYCOMPANY_ANALYTICS.RAW.CSV_FORMAT
    TYPE = CSV
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    ESCAPE = 'NONE'
    ESCAPE_UNENCLOSED_FIELD = '\134'
    DATE_FORMAT = 'AUTO'
    TIMESTAMP_FORMAT = 'AUTO'
    NULL_IF = ('NULL', 'null', '', '\\N');

CREATE OR REPLACE FILE FORMAT MYCOMPANY_ANALYTICS.RAW.JSON_FORMAT
    TYPE = JSON
    COMPRESSION = AUTO
    ENABLE_OCTAL = FALSE
    ALLOW_DUPLICATE = FALSE
    STRIP_OUTER_ARRAY = FALSE
    STRIP_NULL_VALUES = FALSE;
EOF

    # Create stage definitions
    cat > infrastructure/create_stages.sql << 'EOF'
-- Data ingestion stages
CREATE STAGE IF NOT EXISTS MYCOMPANY_STAGING.BRONZE.CSV_STAGE
    FILE_FORMAT = MYCOMPANY_ANALYTICS.RAW.CSV_FORMAT
    COMMENT = 'Stage for CSV file ingestion';

CREATE STAGE IF NOT EXISTS MYCOMPANY_STAGING.BRONZE.JSON_STAGE
    FILE_FORMAT = MYCOMPANY_ANALYTICS.RAW.JSON_FORMAT
    COMMENT = 'Stage for JSON file ingestion';
EOF

    # Create table definitions
    cat > infrastructure/create_tables.sql << 'EOF'
-- Example raw data table
CREATE TABLE IF NOT EXISTS MYCOMPANY_ANALYTICS.RAW.CUSTOMER_DATA (
    customer_id STRING,
    first_name STRING,
    last_name STRING,
    email STRING,
    registration_date DATE,
    last_login_timestamp TIMESTAMP,
    account_status STRING,
    metadata VARIANT
) COMMENT = 'Raw customer data from source systems';

-- Example clean data table
CREATE TABLE IF NOT EXISTS MYCOMPANY_ANALYTICS.CLEAN.CUSTOMERS (
    customer_key NUMBER AUTOINCREMENT PRIMARY KEY,
    customer_id STRING NOT NULL,
    full_name STRING,
    email STRING,
    registration_date DATE,
    last_login_timestamp TIMESTAMP,
    account_status STRING,
    is_active BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Cleaned and standardized customer data';
EOF

    # Create grant definitions
    cat > infrastructure/create_grants.sql << 'EOF'
-- Database usage grants
GRANT USAGE ON DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_DATA_ENGINEER;
GRANT USAGE ON DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_ANALYST;
GRANT USAGE ON DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_ETL_SERVICE;
GRANT USAGE ON DATABASE MYCOMPANY_STAGING TO ROLE MYCOMPANY_ETL_SERVICE;

-- Schema usage grants
GRANT USAGE ON ALL SCHEMAS IN DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_DATA_ENGINEER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE MYCOMPANY_STAGING TO ROLE MYCOMPANY_ETL_SERVICE;

-- Table access grants
GRANT SELECT ON ALL TABLES IN SCHEMA MYCOMPANY_ANALYTICS.CLEAN TO ROLE MYCOMPANY_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA MYCOMPANY_ANALYTICS.MARTS TO ROLE MYCOMPANY_ANALYST;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN DATABASE MYCOMPANY_ANALYTICS TO ROLE MYCOMPANY_DATA_ENGINEER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN DATABASE MYCOMPANY_STAGING TO ROLE MYCOMPANY_ETL_SERVICE;

-- Warehouse usage grants
GRANT USAGE ON WAREHOUSE MYCOMPANY_ETL_WH TO ROLE MYCOMPANY_DATA_ENGINEER;
GRANT USAGE ON WAREHOUSE MYCOMPANY_ETL_WH TO ROLE MYCOMPANY_ETL_SERVICE;
GRANT USAGE ON WAREHOUSE MYCOMPANY_ANALYST_WH TO ROLE MYCOMPANY_ANALYST;

-- Future grants
GRANT SELECT ON FUTURE TABLES IN SCHEMA MYCOMPANY_ANALYTICS.CLEAN TO ROLE MYCOMPANY_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA MYCOMPANY_ANALYTICS.MARTS TO ROLE MYCOMPANY_ANALYST;
EOF

    # Create git integration setup (optional)
    cat > git-setup/create_git_integration.sql << 'EOF'
-- Git integration setup (example - customize for your repository)
-- CREATE OR REPLACE API INTEGRATION mycompany_git_api_integration
--     API_PROVIDER = git_https_api
--     API_ALLOWED_PREFIXES = ('https://github.com/mycompany/')
--     ENABLED = TRUE
--     COMMENT = 'Git integration for MyCompany repositories';

-- Placeholder for actual git setup
SELECT 'Git integration setup - customize for your repository' AS setup_status;
EOF

    echo "✅ Example DDL files created"
}

create_example_manifest() {
    echo ""
    echo "Creating execution manifest..."
    
    cat > scripts/manifest.txt << 'EOF'
# MyCompany Analytics Platform Deployment Manifest
# 
# This file defines the order of DDL execution for the framework.
# Dependencies must be listed before objects that depend on them.

# Phase 1: Core infrastructure  
infrastructure/create_databases.sql
infrastructure/create_schemas.sql

# Phase 2: Processing infrastructure
infrastructure/create_roles.sql
infrastructure/create_warehouses.sql
infrastructure/create_file_formats.sql
infrastructure/create_stages.sql

# Phase 3: Data objects
infrastructure/create_tables.sql

# Phase 4: Security and access
infrastructure/create_grants.sql

# Phase 5: Git integration (optional)
git-setup/create_git_integration.sql
EOF

    echo "✅ Execution manifest created"
}

create_example_documentation() {
    echo ""
    echo "Creating project documentation..."
    
    cat > README.md << 'EOF'
# MyCompany Analytics Platform

Snowflake DDL project using the domain-agnostic infrastructure framework.

## Project Structure

```
infrastructure/          # DDL files for Snowflake objects
├── create_databases.sql  # Database definitions
├── create_schemas.sql    # Schema organization  
├── create_roles.sql      # Role-based access control
├── create_warehouses.sql # Compute warehouses
├── create_file_formats.sql # Data ingestion formats
├── create_stages.sql     # Data staging areas
├── create_tables.sql     # Table definitions
└── create_grants.sql     # Permission grants

git-setup/               # Git integration setup
└── create_git_integration.sql

scripts/                 # Framework integration
├── manifest.txt         # Execution order definition
├── orchestrate_modern.sh # Framework orchestrator
└── lib/
    └── connection_resolver.sh # Connection management
```

## Framework Integration

This project uses the domain-agnostic Snowflake infrastructure framework:

- **Framework provides**: Connection management, execution orchestration, multi-account support
- **Project provides**: DDL content, manifest ordering, domain-specific business logic

## Deployment

### Prerequisites

1. Install Snowflake CLI: `brew install snowflakedb/snowflake-cli/snowflake-cli`
2. Configure connections: `snow connection add --connection-name admin --account YOUR_ACCOUNT`

### Basic Deployment

```bash
# Deploy to primary account
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin

# Deploy git integration
scripts/orchestrate_modern.sh \
  --ddl-dir git-setup \
  --manifest scripts/manifest.txt \
  --phase bootstrap \
  --connection admin
```

### Multi-Account Deployment

```bash
# Deploy to development
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection dev-admin

# Deploy to production  
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection prod-admin
```

### Partial Deployment

```bash
# Deploy from specific script
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure \
  --manifest scripts/manifest.txt \
  --phase infra \
  --from create_warehouses.sql \
  --connection admin

# Deploy single script
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure \
  --manifest scripts/manifest.txt \
  --file create_tables.sql \
  --connection admin
```

## Framework Benefits

- **Multi-account support**: Same DDL, different target accounts
- **Connection flexibility**: Work with any configured Snowflake account  
- **Idempotent operations**: Safe to re-run deployments
- **Enhanced error handling**: Clear error messages with actionable guidance
- **Session caching**: Avoid repeated connection prompts

## Customization

1. **Update DDL**: Modify files in `infrastructure/` for your schema design
2. **Adjust manifest**: Update `scripts/manifest.txt` for your dependency order
3. **Configure connections**: Add target accounts with `snow connection add`
4. **Extend deployment**: Create custom scripts using framework components

For more information, see the framework documentation.
EOF

    echo "✅ Project documentation created"
}

# =============================================================================
# FRAMEWORK INTEGRATION - Installing Framework Components
# =============================================================================

integrate_framework() {
    echo ""
    echo "=========================================="
    echo "Integrating domain-agnostic framework"
    echo "=========================================="
    
    # Find framework components (adjust path for your installation)
    local framework_source_dir
    framework_source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    
    if [[ ! -f "$framework_source_dir/scripts/orchestrate_modern.sh" ]]; then
        echo "❌ Framework components not found at: $framework_source_dir"
        echo "   Please adjust the framework_source_dir variable or install framework"
        exit 1
    fi
    
    echo "Installing framework components from: $framework_source_dir"
    
    # Create framework directory structure
    mkdir -p scripts/lib
    
    # Copy framework components
    cp "$framework_source_dir/scripts/orchestrate_modern.sh" scripts/
    cp "$framework_source_dir/scripts/lib/connection_resolver.sh" scripts/lib/
    
    # Make executable
    chmod +x scripts/orchestrate_modern.sh
    chmod +x scripts/lib/connection_resolver.sh
    
    # Verify installation
    if scripts/orchestrate_modern.sh --help >/dev/null 2>&1; then
        echo "✅ Framework integration completed"
    else
        echo "❌ Framework installation verification failed"
        exit 1
    fi
}

# =============================================================================
# DEPLOYMENT DEMONSTRATION
# =============================================================================

demonstrate_deployment() {
    echo ""
    echo "=========================================="
    echo "Deployment Demonstration"
    echo "=========================================="
    
    echo "Available deployment commands:"
    echo ""
    
    echo "1. Check available connections:"
    echo "   snow connection list"
    echo ""
    
    echo "2. Test connection:"
    echo "   snow connection test -c YOUR_CONNECTION"
    echo ""
    
    echo "3. Deploy infrastructure:"
    echo "   scripts/orchestrate_modern.sh \\"
    echo "     --ddl-dir infrastructure \\"
    echo "     --manifest scripts/manifest.txt \\"
    echo "     --phase infra \\"
    echo "     --connection YOUR_CONNECTION"
    echo ""
    
    echo "4. Deploy git integration:"
    echo "   scripts/orchestrate_modern.sh \\"
    echo "     --ddl-dir git-setup \\"
    echo "     --manifest scripts/manifest.txt \\"
    echo "     --phase bootstrap \\"
    echo "     --connection YOUR_CONNECTION"
    echo ""
    
    echo "5. Deploy everything:"
    echo "   scripts/orchestrate_modern.sh \\"
    echo "     --ddl-dir infrastructure \\"
    echo "     --manifest scripts/manifest.txt \\"
    echo "     --phase all \\"
    echo "     --connection YOUR_CONNECTION"
    echo ""
    
    # Interactive deployment option
    read -p "Would you like to test the framework with a real connection? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_with_real_connection
    else
        echo "Skipping interactive deployment test"
    fi
}

test_with_real_connection() {
    echo ""
    echo "Testing framework with real connection..."
    
    # Check if Snowflake CLI is available
    if ! command -v snow >/dev/null 2>&1; then
        echo "❌ Snowflake CLI not found. Install with:"
        echo "   brew install snowflakedb/snowflake-cli/snowflake-cli"
        return 1
    fi
    
    # List available connections
    echo "Available connections:"
    if ! snow connection list 2>/dev/null; then
        echo "❌ No connections configured. Add a connection with:"
        echo "   snow connection add --connection-name admin --account YOUR_ACCOUNT"
        return 1
    fi
    
    # Prompt for connection to test
    echo ""
    read -p "Enter connection name to test with: " -r connection_name
    
    if [[ -z "$connection_name" ]]; then
        echo "No connection specified, skipping test"
        return 0
    fi
    
    # Test connection
    echo "Testing connection: $connection_name"
    if ! snow connection test -c "$connection_name"; then
        echo "❌ Connection test failed"
        return 1
    fi
    
    # Test framework help
    echo ""
    echo "Testing framework help:"
    scripts/orchestrate_modern.sh --help
    
    # Optional: Test actual deployment
    echo ""
    read -p "Deploy infrastructure to $connection_name? This will create objects. (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deploying infrastructure..."
        if scripts/orchestrate_modern.sh \
            --ddl-dir infrastructure \
            --manifest scripts/manifest.txt \
            --phase infra \
            --connection "$connection_name"; then
            echo "✅ Deployment successful!"
            echo ""
            echo "You can verify the deployment with:"
            echo "   snow sql -c $connection_name -q 'SHOW DATABASES LIKE \"MYCOMPANY_%\";'"
        else
            echo "❌ Deployment failed"
        fi
    else
        echo "Skipping actual deployment"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

display_introduction() {
    cat << 'EOF'

========================================== 
Domain-Agnostic Framework Integration Demo
==========================================

This demonstration shows how to integrate the framework with an existing
Snowflake DDL project. It creates a complete example project with:

✅ Realistic DDL files with proper dependencies
✅ Framework component integration  
✅ Execution manifest configuration
✅ Multi-account deployment examples
✅ Complete documentation

The example creates a "MyCompany Analytics Platform" with databases,
schemas, roles, warehouses, and data objects following best practices.

EOF
}

main() {
    display_introduction
    
    # Project setup phase
    setup_example_project
    create_example_ddl
    create_example_manifest
    create_example_documentation
    
    # Framework integration phase
    integrate_framework
    
    # Demonstration phase
    demonstrate_deployment
    
    echo ""
    echo "=========================================="
    echo "Demo Complete"
    echo "=========================================="
    echo ""
    echo "Example project created at: $EXAMPLE_WORKSPACE"
    echo ""
    echo "What was demonstrated:"
    echo "✅ Complete DDL project structure with realistic dependencies"
    echo "✅ Framework integration with orchestrate_modern.sh and connection_resolver.sh"  
    echo "✅ Manifest file configuration for execution ordering"
    echo "✅ Multi-account deployment patterns"
    echo "✅ Documentation and usage examples"
    echo ""
    echo "Next steps:"
    echo "1. Explore the generated project structure"
    echo "2. Review the DDL files to understand the patterns"
    echo "3. Examine scripts/manifest.txt for execution ordering"
    echo "4. Try deploying to a test Snowflake account"
    echo "5. Adapt the structure for your own projects"
    echo ""
    echo "Framework benefits demonstrated:"
    echo "• Pure orchestration - framework doesn't modify DDL content"
    echo "• Connection flexibility - same DDL, multiple target accounts"
    echo "• Clean boundaries - user controls business logic, framework handles deployment"
    echo "• Enhanced error handling and validation"
    echo ""
    echo "To clean up the demo:"
    echo "   rm -rf $EXAMPLE_WORKSPACE"
    echo ""
}

# Execute demo if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF