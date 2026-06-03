# Snowflake Infrastructure Framework

> **Domain-agnostic framework for Snowflake DDL orchestration and multi-account management**

## Overview

This framework provides **pure orchestration utilities** for deploying DDL to any Snowflake account without domain-specific assumptions. It maintains clean separation between framework responsibilities (connection/orchestration) and user responsibilities (DDL content/business logic).

## Quick Start

```bash
# Basic infrastructure deployment
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin

# Multi-account deployment to different target
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase all \
  --connection mk07348
```

## Framework Principles

### ✅ **Framework Provides**
- **Connection Management** - Universal connection resolution across accounts
- **Authentication Setup** - SSH keys, JWT tokens, connection validation
- **Execution Orchestration** - Apply user DDL files in manifest order
- **Environment Bootstrap** - User/role/warehouse setup for new accounts

### ❌ **Framework Does NOT**
- Modify DDL file contents
- Know about specific database/role names
- Perform template substitution on SQL
- Contain domain-specific configuration

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Project  │    │    Framework     │    │   Snowflake     │
│                 │    │                  │    │   Account       │
│ • DDL Files     │───▶│ • Connection     │───▶│ • Live Objects  │
│ • Manifest      │    │   Resolution     │    │ • Permissions   │
│ • Domain Logic  │    │ • Orchestration  │    │ • Data          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Directory Structure

```
scripts/
├── orchestrate_modern.sh          # Main orchestration interface
└── lib/
    └── connection_resolver.sh      # Universal connection management

docs/framework/                     # This documentation suite
├── README.md                       # This file
├── architecture.md                 # Design principles and boundaries
├── api-reference.md                # Complete CLI documentation
├── integration-guide.md            # Existing project integration
├── testing-guide.md                # Testing and validation
├── deployment-patterns.md          # Production CI/CD patterns
├── migration-guide.md              # Legacy orchestration migration
├── troubleshooting.md              # Common issues and debugging
└── ai-integration.md               # AI/LLM usage guidelines

tests/framework/                    # Test suite (created in Phase 4.4)
├── unit/                           # Component unit tests
├── integration/                    # Multi-account integration tests
└── examples/                       # Reference implementations
```

## Key Components

### **Connection Resolver** (`scripts/lib/connection_resolver.sh`)
- Priority-based connection resolution with user confirmation
- Session-scoped caching to prevent repeated prompts  
- Capability validation for required operations
- Enterprise-grade error handling with actionable guidance

### **Modern Orchestrator** (`scripts/orchestrate_modern.sh`)
- Pure file orchestration without domain assumptions
- Backward compatibility with legacy `orchestrate.sh`
- Enhanced connection resolution and validation
- Comprehensive error handling and logging

## Usage Examples

### Infrastructure Deployment
```bash
# Deploy to primary account
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin

# Deploy to test account  
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection test-admin
```

### Partial Deployment
```bash
# Start from specific script
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --from create_warehouses.sql \
  --connection admin
```

### Single Script Operations
```bash
# Apply single script
./scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --file create_stages.sql \
  --connection admin
```

## Integration Requirements

### **User Project Structure**
Your project must provide:

1. **DDL Directory** - SQL files with your schema definitions
2. **Manifest File** - Ordered list of scripts to execute  
3. **Connection Configuration** - Snowflake connection profiles
4. **Domain Logic** - Business-specific roles, databases, permissions

### **Connection Setup** 
Framework requires valid Snowflake CLI connections:

```bash
# List available connections
snow connection list

# Test connection capability
snow connection test -c admin

# Framework will validate connection has required capabilities
```

## Migration from Legacy Scripts

Existing `scripts/orchestrate.sh` usage translates directly:

```bash
# Legacy
scripts/orchestrate.sh --phase infra --connection admin

# Modern equivalent  
scripts/orchestrate_modern.sh \
  --ddl-dir infrastructure/ \
  --manifest scripts/manifest.txt \
  --phase infra \
  --connection admin
```

## Next Steps

- **Read**: [`architecture.md`](./architecture.md) for detailed design principles
- **Integrate**: [`integration-guide.md`](./integration-guide.md) for existing projects  
- **Deploy**: [`deployment-patterns.md`](./deployment-patterns.md) for production use
- **Test**: [`testing-guide.md`](./testing-guide.md) for validation approaches

## Support

- **API Reference**: Complete CLI documentation in [`api-reference.md`](./api-reference.md)
- **Troubleshooting**: Common issues in [`troubleshooting.md`](./troubleshooting.md)
- **AI Integration**: LLM usage guidelines in [`ai-integration.md`](./ai-integration.md)