# Production Deployment Patterns

> **Enterprise deployment patterns and best practices for the domain-agnostic Snowflake framework**

## Overview

This guide provides production-ready deployment patterns that leverage framework capabilities while maintaining enterprise-grade reliability, security, and observability.

## Enterprise Deployment Architecture

### **Multi-Environment Pipeline**

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Development │───▶│   Staging   │───▶│     UAT     │───▶│ Production  │
│   Account   │    │   Account   │    │  Account    │    │  Account    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │                  │
       ▼                   ▼                   ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Same DDL + Framework Components                       │
│  • infrastructure/ (unchanged across environments)                 │
│  • scripts/manifest.txt (same execution order)                     │
│  • Different connection configurations only                        │
└─────────────────────────────────────────────────────────────────────┘
```

### **Connection-Based Environment Separation**

**Framework Principle**: Same DDL files, different target connections

```bash
# Development deployment
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --connection dev-admin \
  --phase infra

# Staging deployment  
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --connection staging-admin \
  --phase infra

# Production deployment
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --connection prod-admin \
  --phase infra
```

## CI/CD Pipeline Patterns

### **Pattern 1: GitOps with Framework Orchestration**

**Pipeline Structure**:
```yaml
# .github/workflows/snowflake-deployment.yml
name: Snowflake Infrastructure Deployment

on:
  push:
    branches: [main]
    paths: 
      - 'infrastructure/**'
      - 'scripts/manifest.txt'
  
  pull_request:
    branches: [main]
    paths:
      - 'infrastructure/**'
      - 'scripts/manifest.txt'

jobs:
  validate-ddl:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Snowflake CLI
        run: |
          curl -sSfL https://github.com/Snowflake-Labs/snowflake-cli/releases/latest/download/snowflake-cli-linux-x64.tar.gz | tar xz
          sudo mv snowflake /usr/local/bin/snow
          
      - name: Validate Framework Components
        run: |
          chmod +x scripts/orchestrate_modern.sh
          scripts/orchestrate_modern.sh --help
          
      - name: Validate DDL Syntax
        run: |
          # Basic SQL syntax validation
          find infrastructure/ -name "*.sql" -exec snow sql --dry-run --filename {} \; || true

  deploy-development:
    needs: validate-ddl
    if: github.event_name == 'pull_request'
    environment: development
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Snowflake Connection
        run: |
          echo "$SNOWFLAKE_PRIVATE_KEY" > /tmp/dev_key.pem
          snow connection add \
            --connection-name dev-admin \
            --account ${{ secrets.DEV_ACCOUNT }} \
            --user ${{ secrets.DEV_USER }} \
            --private-key-path /tmp/dev_key.pem
        env:
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.DEV_SNOWFLAKE_PRIVATE_KEY }}
          
      - name: Deploy to Development
        run: |
          chmod +x scripts/orchestrate_modern.sh
          scripts/orchestrate_modern.sh \
            --ddl-dir infrastructure/ \
            --manifest scripts/manifest.txt \
            --phase infra \
            --connection dev-admin

  deploy-staging:
    needs: validate-ddl
    if: github.ref == 'refs/heads/main'
    environment: staging
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Snowflake Connection
        run: |
          echo "$SNOWFLAKE_PRIVATE_KEY" > /tmp/staging_key.pem
          snow connection add \
            --connection-name staging-admin \
            --account ${{ secrets.STAGING_ACCOUNT }} \
            --user ${{ secrets.STAGING_USER }} \
            --private-key-path /tmp/staging_key.pem
        env:
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.STAGING_SNOWFLAKE_PRIVATE_KEY }}
          
      - name: Deploy to Staging
        run: |
          scripts/orchestrate_modern.sh \
            --ddl-dir infrastructure/ \
            --manifest scripts/manifest.txt \
            --phase infra \
            --connection staging-admin
            
      - name: Validate Staging Deployment
        run: |
          snow sql -c staging-admin -q "SHOW DATABASES;"
          snow sql -c staging-admin -q "SELECT 'Deployment validated' AS status;"

  deploy-production:
    needs: deploy-staging
    environment: production
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Snowflake Connection  
        run: |
          echo "$SNOWFLAKE_PRIVATE_KEY" > /tmp/prod_key.pem
          snow connection add \
            --connection-name prod-admin \
            --account ${{ secrets.PROD_ACCOUNT }} \
            --user ${{ secrets.PROD_USER }} \
            --private-key-path /tmp/prod_key.pem
        env:
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.PROD_SNOWFLAKE_PRIVATE_KEY }}
          
      - name: Deploy to Production
        run: |
          scripts/orchestrate_modern.sh \
            --ddl-dir infrastructure/ \
            --manifest scripts/manifest.txt \
            --phase infra \
            --connection prod-admin
            
      - name: Post-Deployment Validation
        run: |
          snow sql -c prod-admin -q "SHOW DATABASES;"
          # Add specific validation queries for your deployment
```

### **Pattern 2: Multi-Account Deployment with Approval Gates**

**Jenkinsfile Example**:
```groovy
pipeline {
    agent any
    
    environment {
        SNOWFLAKE_CLI_VERSION = '2.0.0'
    }
    
    stages {
        stage('Validate Framework') {
            steps {
                sh 'chmod +x scripts/orchestrate_modern.sh'
                sh 'scripts/orchestrate_modern.sh --help'
            }
        }
        
        stage('Deploy to Development') {
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'dev-account', variable: 'DEV_ACCOUNT'),
                        file(credentialsId: 'dev-private-key', variable: 'DEV_KEY_FILE')
                    ]) {
                        sh '''
                            snow connection add \
                              --connection-name dev-admin \
                              --account $DEV_ACCOUNT \
                              --user dev-admin-user \
                              --private-key-path $DEV_KEY_FILE
                              
                            scripts/orchestrate_modern.sh \
                              --ddl-dir infrastructure/ \
                              --manifest scripts/manifest.txt \
                              --phase infra \
                              --connection dev-admin
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to Staging') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'staging-account', variable: 'STAGING_ACCOUNT'),
                        file(credentialsId: 'staging-private-key', variable: 'STAGING_KEY_FILE')
                    ]) {
                        sh '''
                            snow connection add \
                              --connection-name staging-admin \
                              --account $STAGING_ACCOUNT \
                              --user staging-admin-user \
                              --private-key-path $STAGING_KEY_FILE
                              
                            scripts/orchestrate_modern.sh \
                              --ddl-dir infrastructure/ \
                              --manifest scripts/manifest.txt \
                              --phase infra \
                              --connection staging-admin
                        '''
                    }
                }
            }
        }
        
        stage('Production Approval') {
            when {
                branch 'main'
            }
            steps {
                input message: 'Deploy to Production?', ok: 'Deploy',
                      submitterParameter: 'APPROVER'
            }
        }
        
        stage('Deploy to Production') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'prod-account', variable: 'PROD_ACCOUNT'),
                        file(credentialsId: 'prod-private-key', variable: 'PROD_KEY_FILE')
                    ]) {
                        sh '''
                            snow connection add \
                              --connection-name prod-admin \
                              --account $PROD_ACCOUNT \
                              --user prod-admin-user \
                              --private-key-path $PROD_KEY_FILE
                              
                            scripts/orchestrate_modern.sh \
                              --ddl-dir infrastructure/ \
                              --manifest scripts/manifest.txt \
                              --phase infra \
                              --connection prod-admin
                        '''
                    }
                }
            }
            post {
                success {
                    slackSend(
                        channel: '#deployments',
                        message: "✅ Production deployment completed by ${APPROVER}"
                    )
                }
            }
        }
    }
}
```

## Advanced Deployment Strategies

### **Blue-Green Deployment Pattern**

**Use Case**: Zero-downtime database schema changes

```bash
#!/usr/bin/env bash
# blue-green-deployment.sh

set -euo pipefail

readonly ENVIRONMENT="${1:-staging}"
readonly DEPLOYMENT_ID=$(date +%Y%m%d_%H%M%S)

# Deploy to blue environment (new schema version)
echo "Deploying to blue environment..."
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection "${ENVIRONMENT}-blue-admin"

# Validate blue environment
echo "Validating blue environment..."
if validate_deployment_health "${ENVIRONMENT}-blue-admin"; then
    echo "✅ Blue environment validated"
    
    # Switch traffic to blue
    echo "Switching traffic to blue environment..."
    switch_environment_traffic "${ENVIRONMENT}" "blue"
    
    # Mark green as previous (for rollback)
    mark_environment_previous "${ENVIRONMENT}" "green" "$DEPLOYMENT_ID"
    
    echo "✅ Blue-green deployment completed"
else
    echo "❌ Blue environment validation failed"
    echo "Traffic remains on green environment"
    exit 1
fi

validate_deployment_health() {
    local connection="$1"
    
    # Run health checks specific to your deployment
    snow sql -c "$connection" -q "SELECT 'Health check passed' AS status;" >/dev/null
    return $?
}
```

### **Canary Deployment Pattern**

**Use Case**: Gradual rollout with monitoring

```bash
#!/usr/bin/env bash  
# canary-deployment.sh

set -euo pipefail

readonly ENVIRONMENT="${1:-production}"
readonly CANARY_PERCENTAGE="${2:-10}"

echo "Starting canary deployment ($CANARY_PERCENTAGE% traffic)..."

# Deploy to canary environment
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection "${ENVIRONMENT}-canary-admin"

# Route percentage of traffic to canary
route_traffic_percentage "$ENVIRONMENT" "canary" "$CANARY_PERCENTAGE"

echo "Monitoring canary for 30 minutes..."
sleep 1800  # 30 minutes

# Check canary health metrics
if check_canary_health "$ENVIRONMENT" "canary"; then
    echo "✅ Canary healthy, promoting to full deployment"
    
    # Deploy to main environment
    scripts/orchestrate_modern.sh \
      --ddl-dir infrastructure/ \
      --manifest scripts/manifest.txt \
      --phase infra \
      --connection "${ENVIRONMENT}-admin"
      
    # Route all traffic to main
    route_traffic_percentage "$ENVIRONMENT" "main" "100"
    
    echo "✅ Canary deployment promoted successfully"
else
    echo "❌ Canary health check failed, rolling back"
    route_traffic_percentage "$ENVIRONMENT" "main" "100"
    exit 1
fi
```

### **Feature Flag Integration**

**Use Case**: Conditional DDL deployment based on feature flags

```bash
#!/usr/bin/env bash
# feature-flag-deployment.sh

set -euo pipefail

readonly ENVIRONMENT="$1"
readonly FEATURE_FLAG_SERVICE="$2"

# Check feature flags before deployment
check_feature_flag() {
    local feature="$1"
    
    # Call your feature flag service (e.g., LaunchDarkly, Split.io)
    if curl -s "$FEATURE_FLAG_SERVICE/api/flags/$feature" | jq -r '.enabled' | grep -q true; then
        return 0
    else
        return 1
    fi
}

deploy_conditional_features() {
    # Base infrastructure always deploys
    scripts/orchestrate_modern.sh \
      --ddl-dir infrastructure/core/ \
      --manifest scripts/core-manifest.txt \
      --phase infra \
      --connection "${ENVIRONMENT}-admin"
    
    # Conditional feature deployments
    if check_feature_flag "new_analytics_tables"; then
        echo "Deploying new analytics tables (feature enabled)..."
        scripts/orchestrate_modern.sh \
          --ddl-dir infrastructure/analytics/ \
          --manifest scripts/analytics-manifest.txt \
          --phase infra \
          --connection "${ENVIRONMENT}-admin"
    fi
    
    if check_feature_flag "enhanced_security"; then
        echo "Deploying enhanced security (feature enabled)..."
        scripts/orchestrate_modern.sh \
          --ddl-dir infrastructure/security/ \
          --manifest scripts/security-manifest.txt \
          --phase infra \
          --connection "${ENVIRONMENT}-admin"
    fi
}

deploy_conditional_features
```

## Security and Compliance Patterns

### **Credential Management**

**Pattern: Environment-Specific Service Accounts**

```bash
# Connection setup with dedicated service accounts
setup_environment_connections() {
    local env="$1"
    
    case "$env" in
        "development")
            snow connection add \
              --connection-name dev-admin \
              --account "$DEV_ACCOUNT" \
              --user "DDL_DEPLOY_DEV" \
              --private-key-path "/vault/keys/ddl_deploy_dev.pem"
            ;;
        "staging")
            snow connection add \
              --connection-name staging-admin \
              --account "$STAGING_ACCOUNT" \
              --user "DDL_DEPLOY_STAGING" \
              --private-key-path "/vault/keys/ddl_deploy_staging.pem"
            ;;
        "production")
            snow connection add \
              --connection-name prod-admin \
              --account "$PROD_ACCOUNT" \
              --user "DDL_DEPLOY_PROD" \
              --private-key-path "/vault/keys/ddl_deploy_prod.pem"
            ;;
    esac
}
```

**Pattern: Role-Based Access Control**

```sql
-- infrastructure/create_deployment_roles.sql
-- Deployment-specific roles with minimal required permissions

CREATE ROLE IF NOT EXISTS DDL_DEPLOY_ROLE
    COMMENT = 'Role for automated DDL deployment';

-- Grant only necessary privileges
GRANT CREATE DATABASE, CREATE ROLE, CREATE WAREHOUSE ON ACCOUNT TO ROLE DDL_DEPLOY_ROLE;
GRANT ROLE DDL_DEPLOY_ROLE TO USER DDL_DEPLOY_SERVICE;

-- Audit trail for deployments
CREATE TABLE IF NOT EXISTS DEPLOYMENT_AUDIT_LOG (
    deployment_id STRING,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    environment STRING,
    user_name STRING DEFAULT CURRENT_USER(),
    role_name STRING DEFAULT CURRENT_ROLE(),
    ddl_file STRING,
    execution_status STRING,
    error_message STRING
);
```

### **Audit and Compliance Patterns**

**Pattern: Deployment Tracking**

```bash
#!/usr/bin/env bash
# deployment-with-audit.sh

set -euo pipefail

readonly DEPLOYMENT_ID="$(uuidgen)"
readonly ENVIRONMENT="$1"
readonly CONNECTION="${ENVIRONMENT}-admin"

log_deployment_start() {
    snow sql -c "$CONNECTION" -q "
        INSERT INTO DEPLOYMENT_AUDIT_LOG 
        (deployment_id, environment, ddl_file, execution_status)
        VALUES ('$DEPLOYMENT_ID', '$ENVIRONMENT', 'deployment_start', 'STARTED');
    "
}

log_deployment_end() {
    local status="$1"
    local error_msg="${2:-}"
    
    snow sql -c "$CONNECTION" -q "
        INSERT INTO DEPLOYMENT_AUDIT_LOG 
        (deployment_id, environment, ddl_file, execution_status, error_message)
        VALUES ('$DEPLOYMENT_ID', '$ENVIRONMENT', 'deployment_end', '$status', '$error_msg');
    "
}

# Main deployment with audit logging
log_deployment_start

if scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/ \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$CONNECTION"; then
    
    log_deployment_end "SUCCESS"
    echo "✅ Deployment $DEPLOYMENT_ID completed successfully"
else
    log_deployment_end "FAILED" "Framework deployment failed"
    echo "❌ Deployment $DEPLOYMENT_ID failed"
    exit 1
fi
```

## Monitoring and Observability

### **Deployment Health Checks**

**Pattern: Post-Deployment Validation**

```bash
#!/usr/bin/env bash
# post-deployment-validation.sh

set -euo pipefail

readonly CONNECTION="$1"

validate_deployment_health() {
    echo "Running post-deployment health checks..."
    
    # Check database accessibility
    if ! snow sql -c "$CONNECTION" -q "SHOW DATABASES;" >/dev/null; then
        echo "❌ Database access failed"
        return 1
    fi
    
    # Check role assignments
    local role_count
    role_count=$(snow sql -c "$CONNECTION" -q "SHOW ROLES;" --format json | jq length)
    if [[ "$role_count" -lt 1 ]]; then
        echo "❌ No roles found"
        return 1
    fi
    
    # Check warehouse status
    local warehouse_status
    warehouse_status=$(snow sql -c "$CONNECTION" -q "SHOW WAREHOUSES;" --format json | jq -r '.[0].state')
    if [[ "$warehouse_status" != "SUSPENDED" && "$warehouse_status" != "STARTED" ]]; then
        echo "❌ Unexpected warehouse status: $warehouse_status"
        return 1
    fi
    
    # Application-specific health checks
    run_application_health_checks "$CONNECTION"
    
    echo "✅ All health checks passed"
    return 0
}

run_application_health_checks() {
    local connection="$1"
    
    # Example: Check table row counts
    local customer_count
    customer_count=$(snow sql -c "$connection" -q "SELECT COUNT(*) FROM ANALYTICS.CUSTOMERS;" --format json | jq -r '.[0]["COUNT(*)"]')
    
    if [[ "$customer_count" -gt 0 ]]; then
        echo "✅ Customer data available ($customer_count rows)"
    else
        echo "⚠️  Customer table empty (new deployment?)"
    fi
}

validate_deployment_health "$CONNECTION"
```

### **Metrics and Alerting**

**Pattern: Deployment Metrics Collection**

```bash
#!/usr/bin/env bash
# deployment-with-metrics.sh

set -euo pipefail

readonly DEPLOYMENT_START=$(date +%s)
readonly ENVIRONMENT="$1"
readonly CONNECTION="${ENVIRONMENT}-admin"

send_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local tags="$3"
    
    # Send to your metrics system (e.g., DataDog, CloudWatch)
    curl -X POST "https://api.datadoghq.com/api/v1/series" \
        -H "Content-Type: application/json" \
        -H "DD-API-KEY: $DATADOG_API_KEY" \
        -d "{
            \"series\": [{
                \"metric\": \"snowflake.deployment.$metric_name\",
                \"points\": [[$(date +%s), $metric_value]],
                \"tags\": [$tags]
            }]
        }"
}

# Deploy with metrics
if scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/ \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$CONNECTION"; then
    
    deployment_end=$(date +%s)
    deployment_duration=$((deployment_end - DEPLOYMENT_START))
    
    # Send success metrics
    send_metric "duration" "$deployment_duration" "\"environment:$ENVIRONMENT\",\"status:success\""
    send_metric "success" "1" "\"environment:$ENVIRONMENT\""
    
    echo "✅ Deployment completed in ${deployment_duration}s"
else
    deployment_end=$(date +%s)
    deployment_duration=$((deployment_end - DEPLOYMENT_START))
    
    # Send failure metrics
    send_metric "duration" "$deployment_duration" "\"environment:$ENVIRONMENT\",\"status:failure\""
    send_metric "failure" "1" "\"environment:$ENVIRONMENT\""
    
    echo "❌ Deployment failed after ${deployment_duration}s"
    exit 1
fi
```

## Disaster Recovery and Rollback

### **Automated Rollback Pattern**

```bash
#!/usr/bin/env bash
# deployment-with-rollback.sh

set -euo pipefail

readonly ENVIRONMENT="$1"
readonly CONNECTION="${ENVIRONMENT}-admin"
readonly BACKUP_PREFIX="backup_$(date +%Y%m%d_%H%M%S)"

create_backup() {
    echo "Creating backup before deployment..."
    
    # Create backup schema
    snow sql -c "$CONNECTION" -q "CREATE SCHEMA IF NOT EXISTS BACKUPS.${BACKUP_PREFIX};"
    
    # Backup critical objects (customize for your needs)
    local tables
    tables=$(snow sql -c "$CONNECTION" -q "SHOW TABLES IN SCHEMA ANALYTICS.MARTS;" --format json | jq -r '.[].name')
    
    for table in $tables; do
        snow sql -c "$CONNECTION" -q "
            CREATE TABLE BACKUPS.${BACKUP_PREFIX}.${table} AS 
            SELECT * FROM ANALYTICS.MARTS.${table};
        "
    done
    
    echo "✅ Backup created: $BACKUP_PREFIX"
    echo "$BACKUP_PREFIX" > "/tmp/last_backup_${ENVIRONMENT}.txt"
}

rollback_deployment() {
    local backup_name="$1"
    
    echo "Rolling back to backup: $backup_name"
    
    # Restore from backup (customize for your objects)
    local backup_tables
    backup_tables=$(snow sql -c "$CONNECTION" -q "SHOW TABLES IN SCHEMA BACKUPS.${backup_name};" --format json | jq -r '.[].name')
    
    for table in $backup_tables; do
        snow sql -c "$CONNECTION" -q "
            CREATE OR REPLACE TABLE ANALYTICS.MARTS.${table} AS 
            SELECT * FROM BACKUPS.${backup_name}.${table};
        "
    done
    
    echo "✅ Rollback completed"
}

# Main deployment with backup/rollback capability
create_backup

if scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/ \
    --manifest scripts/manifest.txt \
    --phase infra \
    --connection "$CONNECTION"; then
    
    # Validate deployment
    if validate_deployment_health "$CONNECTION"; then
        echo "✅ Deployment successful and validated"
        
        # Optional: Clean up old backups
        cleanup_old_backups "$CONNECTION" 7  # Keep 7 days
    else
        echo "❌ Deployment validation failed, rolling back"
        rollback_deployment "$BACKUP_PREFIX"
        exit 1
    fi
else
    echo "❌ Deployment failed, rolling back"
    rollback_deployment "$BACKUP_PREFIX"
    exit 1
fi
```

## Performance Optimization

### **Parallel Deployment Pattern**

**Use Case**: Deploy to multiple environments simultaneously

```bash
#!/usr/bin/env bash
# parallel-deployment.sh

set -euo pipefail

deploy_to_environment() {
    local env="$1"
    local connection="${env}-admin"
    
    echo "Starting deployment to $env..."
    
    if scripts/orchestrate_modern.sh \
        --ddl-dir infrastructure/ \
        --manifest scripts/manifest.txt \
        --phase infra \
        --connection "$connection"; then
        
        echo "✅ $env deployment completed"
        return 0
    else
        echo "❌ $env deployment failed"
        return 1
    fi
}

# Deploy to multiple environments in parallel
environments=("development" "staging" "uat")
deployment_pids=()

for env in "${environments[@]}"; do
    deploy_to_environment "$env" &
    deployment_pids+=($!)
done

# Wait for all deployments and collect results
deployment_results=()
for i in "${!deployment_pids[@]}"; do
    wait "${deployment_pids[i]}"
    deployment_results[i]=$?
done

# Report results
echo ""
echo "Deployment Results:"
for i in "${!environments[@]}"; do
    env="${environments[i]}"
    result="${deployment_results[i]}"
    
    if [[ $result -eq 0 ]]; then
        echo "✅ $env: SUCCESS"
    else
        echo "❌ $env: FAILED"
    fi
done

# Exit with error if any deployment failed
for result in "${deployment_results[@]}"; do
    if [[ $result -ne 0 ]]; then
        echo "❌ One or more deployments failed"
        exit 1
    fi
done

echo "✅ All parallel deployments completed successfully"
```

### **Incremental Deployment Pattern**

**Use Case**: Deploy only changed files for faster iterations

```bash
#!/usr/bin/env bash
# incremental-deployment.sh

set -euo pipefail

readonly ENVIRONMENT="$1"
readonly CONNECTION="${ENVIRONMENT}-admin"
readonly LAST_DEPLOYMENT_COMMIT=$(cat ".last_deployment_${ENVIRONMENT}" 2>/dev/null || echo "HEAD~1")

get_changed_ddl_files() {
    # Get DDL files changed since last deployment
    git diff --name-only "$LAST_DEPLOYMENT_COMMIT" HEAD -- infrastructure/ | grep '\.sql$' || true
}

create_incremental_manifest() {
    local changed_files="$1"
    local temp_manifest="/tmp/incremental_manifest_${ENVIRONMENT}.txt"
    
    # Create manifest with only changed files in dependency order
    # Read original manifest and filter for changed files
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Check if this file was changed
        if echo "$changed_files" | grep -q "$line"; then
            echo "$line" >> "$temp_manifest"
        fi
    done < scripts/manifest.txt
    
    echo "$temp_manifest"
}

# Main incremental deployment
changed_files=$(get_changed_ddl_files)

if [[ -z "$changed_files" ]]; then
    echo "No DDL files changed since last deployment"
    exit 0
fi

echo "Changed DDL files:"
echo "$changed_files"

# Create incremental manifest
incremental_manifest=$(create_incremental_manifest "$changed_files")

if [[ ! -s "$incremental_manifest" ]]; then
    echo "No changed files found in manifest order"
    rm -f "$incremental_manifest"
    exit 0
fi

echo "Incremental manifest:"
cat "$incremental_manifest"

# Deploy changed files only
if scripts/orchestrate_modern.sh \
    --ddl-dir infrastructure/ \
    --manifest "$incremental_manifest" \
    --phase infra \
    --connection "$CONNECTION"; then
    
    # Record successful deployment
    git rev-parse HEAD > ".last_deployment_${ENVIRONMENT}"
    echo "✅ Incremental deployment completed"
else
    echo "❌ Incremental deployment failed"
    exit 1
fi

# Cleanup
rm -f "$incremental_manifest"
```

## Summary

**Enterprise Deployment Patterns**:
1. **Multi-environment pipelines** with connection-based separation
2. **CI/CD integration** with approval gates and validation
3. **Advanced strategies** (blue-green, canary, feature flags)
4. **Security and compliance** with audit trails and RBAC
5. **Monitoring and observability** with health checks and metrics
6. **Disaster recovery** with automated backup and rollback
7. **Performance optimization** with parallel and incremental deployment

**Framework Benefits in Production**:
- **Consistency**: Same DDL across all environments
- **Reliability**: Idempotent operations and error handling
- **Security**: Connection-based access control
- **Scalability**: Multi-account support without code changes
- **Observability**: Clear deployment logging and validation