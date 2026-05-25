-- =============================================================================
-- Register the admin RSA public key so the snow CLI 'admin' connection can
-- authenticate with SNOWFLAKE_JWT against the configured private_key_file.
--
-- Run ONCE per account (or after key rotation) via a snow sql one-shot:
--
--   PUBKEY=$(awk 'NR>1 && !/-----END/ {printf "%s", $0}' \
--       ~/.snowflake/keys/admin_rsa_key.pub)
--   SNOWFLAKE_PASSWORD='<admin_temp_password>' \
--   snow sql \
--       --account       "$SNOWFLAKE_ACCOUNT" \
--       --user          YOUR_ADMIN_USER \
--       --role          ACCOUNTADMIN \
--       --warehouse     ARTWORK_WH \
--       --authenticator snowflake \
--       --filename      git-setup/operator/register_admin_public_key.sql \
--       --variable      admin_user=YOUR_ADMIN_USER \
--       --variable      rsa_public_key="$PUBKEY" \
--       --enhanced-exit-codes
--
-- The 'admin_user' and 'rsa_public_key' variables are substituted at runtime
-- by the snow CLI (see snow sql command reference). After this script runs,
-- DESCRIBE USER reports a populated RSA_PUBLIC_KEY_FP and 'snow connection
-- test -c admin' succeeds.
--
-- Idempotent: re-running with the same key value is a no-op; re-running with
-- a new key rotates the credential.
-- =============================================================================

ALTER USER &{ admin_user }
    SET RSA_PUBLIC_KEY = '&{ rsa_public_key }';

DESCRIBE USER &{ admin_user };
