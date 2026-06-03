# Snowflake CLI Setup Examples

Comprehensive setup and management toolkit for Snowflake CLI with JWT authentication, multi-account support, and automated key management.

## Basic Setup

### 1. Complete Bootstrap (Fresh Machine)
```bash
# Full setup: install CLI, generate keys, configure profiles, verify connections
./setup.sh --phase all
```
Sets up everything needed for Snowflake CLI with JWT auth. Creates admin connection, generates RSA keys, and verifies connectivity.

### 2. Install Snowflake CLI Only
```bash
./setup.sh --phase prereq
```
Installs `snow` CLI via Homebrew, creates `~/.snowflake/` structure, generates admin key pair, and locks file permissions.

### 3. Initialize Profile Configuration  
```bash
./setup.sh --phase init-profile
```
Seeds `[connections.admin]` in `~/.snowflake/config.toml` by prompting for account, user, role, and warehouse. Non-destructive.

## Account Management

### 4. List All Configured Connections
```bash
./setup.sh --phase list
```
Shows every `[connections.*]` in config.toml with the current default marked with `*`.

### 5. Switch Active Account
```bash
./setup.sh --profile mk07348 --phase switch
```
Changes `default_connection_name` to use the mk07348 connection profile.

### 6. Setup Second Account (Multi-tenant)
```bash
./setup.sh --profile clientb --phase all
```
Creates `[connections.clientb]` and `[connections.clientb_loader]` with separate key files (`clientb_rsa_key.p8`, `clientb_loader_rsa_key.p8`).

### 7. Custom Connection Names
```bash
./setup.sh --admin-conn prod-admin --loader-conn prod-loader --phase all
```
Override default naming convention with explicit connection names.

## Authentication Setup

### 8. Register Admin Public Key
```bash
./setup.sh --phase admin
```
One-time password authentication to register your RSA public key with Snowflake. Prompts for password (never stored).

### 9. Verify JWT Authentication
```bash
./setup.sh --phase admin
# Or verify existing setup:
./05_verify_admin_jwt.sh
```
Tests JWT-based authentication against current admin warehouse (initially account-default like COMPUTE_WH).

### 10. Setup Service User (Loader)
```bash
./setup.sh --phase loader
```
Creates loader RSA keys, registers public key via admin connection, configures `[connections.loader]` for passwordless auth.

## Infrastructure Integration

### 11. Promote Admin to Project Warehouse
```bash
# After: make iac
./setup.sh --phase promote
```
Switches admin connection from account-default warehouse to ARTWORK_WH. Requires infrastructure to exist first.

### 12. Test Loader Connection
```bash
./07_test_loader_connection.sh
```
Verifies loader service user can authenticate and access Bronze schema.

## Advanced Configuration

### 13. Force Key Rotation (Loader)
```bash
OVERWRITE_LOADER_KEY=1 ./06_setup_loader_keypair.sh
```
Regenerates loader RSA key pair and updates Snowflake registration.

### 14. Manual Profile Creation
```bash
# Set environment variables first
export SNOWFLAKE_ACCOUNT="MYORG-MYACCOUNT"
export SNOWFLAKE_ADMIN_USER="USERNAME"
export SNOWFLAKE_ROLE="SYSADMIN"
./setup.sh --phase init-profile
```
Non-interactive profile creation using environment variables.

### 15. Connection Testing
```bash
# Test specific connection directly
snow connection test -c admin
snow connection test -c loader

# Test via setup script
./setup.sh --phase admin  # includes verification step
```

## Multi-Account Workflows

### 16. Setup Development Account
```bash
./setup.sh --profile dev --phase all
# Switch to it
./setup.sh --profile dev --phase switch
```

### 17. Setup Production Account
```bash
./setup.sh --profile prod --phase prereq
./setup.sh --profile prod --phase init-profile
# Configure prod-specific values when prompted
./setup.sh --profile prod --phase admin
```

### 18. Quick Account Switch
```bash
# Switch between configured accounts
./setup.sh --profile dev --phase switch
./setup.sh --profile prod --phase switch
./setup.sh --profile mk07348 --phase switch
```

## Troubleshooting & Maintenance

### 19. Re-run Failed Steps
```bash
# All phases are idempotent - safe to re-run
./setup.sh --phase admin     # Re-verify JWT auth
./setup.sh --phase loader    # Re-setup loader keys
./setup.sh --phase promote   # Re-promote warehouse
```

### 20. Inspect Configuration
```bash
# List connections and current default
./setup.sh --phase list

# View config file directly  
cat ~/.snowflake/config.toml

# Check key files
ls -la ~/.snowflake/keys/
```

## Environment Variables

- `SNOWFLAKE_ACCOUNT` - Account identifier (e.g., `ORGNAME-ACCOUNTNAME`)
- `SNOWFLAKE_ADMIN_USER` - Login username
- `SNOWFLAKE_ROLE` - Role name (default: `ACCOUNTADMIN`)
- `SNOWFLAKE_WAREHOUSE` - Warehouse name (default: `COMPUTE_WH`)
- `SNOWFLAKE_PASSWORD` - Admin password (prompted if unset)
- `OVERWRITE_LOADER_KEY` - Set to `1` to force key rotation

## File Structure

```
~/.snowflake/
├── config.toml              # Connection profiles
├── keys/
│   ├── admin_rsa_key.p8     # Admin private key
│   ├── admin_rsa_key.pub    # Admin public key  
│   ├── loader_rsa_key.p8    # Loader private key
│   └── loader_rsa_key.pub   # Loader public key
└── logs/                    # CLI logs
```

All setup phases are **idempotent** and **safe to re-run**. The toolkit supports unlimited accounts via the `--profile` system.