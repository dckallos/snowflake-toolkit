-- =============================================================================
-- register_admin_public_key.sql -- Dual-slot RSA key registration
--
-- Registers the admin RSA public key into the first available slot
-- (RSA_PUBLIC_KEY or RSA_PUBLIC_KEY_2) on the target user, enabling two
-- devices (Macs, CI runners, etc.) to coexist with independent key pairs.
--
-- Algorithm:
--   1. Check if either existing slot already holds this key (fingerprint match).
--      If yes -> no-op (idempotent).
--   2. If slot 1 is empty -> assign to RSA_PUBLIC_KEY.
--   3. If slot 2 is empty -> assign to RSA_PUBLIC_KEY_2.
--   4. If BOTH slots are occupied by OTHER keys -> overwrite slot 2 (the
--      rotation slot; slot 1 belongs to the other device).
--
-- Variables (substituted by `snow sql --variable`):
--   admin_user       - the Snowflake user name to ALTER
--   rsa_public_key   - the PEM-stripped base64 public key body
--   rsa_public_key_fp - the SHA256 fingerprint of the key (SHA256:xxxx...)
--
-- Run context: ACCOUNTADMIN (required for ALTER USER ... SET RSA_PUBLIC_KEY).
--
-- Idempotent: re-running with the same key is a no-op; running from a second
-- device with a different key fills the other slot transparently.
-- =============================================================================

DECLARE
    v_admin_user     VARCHAR DEFAULT '<% admin_user %>';
    v_pubkey         VARCHAR DEFAULT '<% rsa_public_key %>';
    v_local_fp       VARCHAR DEFAULT '<% rsa_public_key_fp %>';
    v_fp1            VARCHAR;
    v_fp2            VARCHAR;
    v_slot           VARCHAR;
BEGIN
    -- Retrieve current fingerprints for both slots via DESCRIBE USER.
    EXECUTE IMMEDIATE 'DESCRIBE USER ' || :v_admin_user;

    -- Extract the two fingerprint properties from the DESCRIBE result set.
    SELECT MAX(CASE WHEN "property" = 'RSA_PUBLIC_KEY_FP' THEN "value" END),
           MAX(CASE WHEN "property" = 'RSA_PUBLIC_KEY_2_FP' THEN "value" END)
    INTO :v_fp1, :v_fp2
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Normalize: treat 'null' string as empty (DESCRIBE returns literal 'null').
    IF (v_fp1 = 'null') THEN v_fp1 := ''; END IF;
    IF (v_fp2 = 'null') THEN v_fp2 := ''; END IF;

    -- Decision logic: where does this key belong?
    IF (:v_local_fp = :v_fp1 OR :v_local_fp = :v_fp2) THEN
        -- Key is already registered in one of the slots. No-op.
        v_slot := 'ALREADY_REGISTERED';
    ELSEIF (:v_fp1 IS NULL OR :v_fp1 = '') THEN
        -- Slot 1 is empty: use it (first device to register).
        EXECUTE IMMEDIATE
            'ALTER USER ' || :v_admin_user || ' SET RSA_PUBLIC_KEY = ''' || :v_pubkey || '''';
        v_slot := 'RSA_PUBLIC_KEY';
    ELSEIF (:v_fp2 IS NULL OR :v_fp2 = '') THEN
        -- Slot 1 occupied by another key, slot 2 empty: use slot 2.
        EXECUTE IMMEDIATE
            'ALTER USER ' || :v_admin_user || ' SET RSA_PUBLIC_KEY_2 = ''' || :v_pubkey || '''';
        v_slot := 'RSA_PUBLIC_KEY_2';
    ELSE
        -- Both slots occupied by OTHER keys: overwrite slot 2 (rotation slot).
        EXECUTE IMMEDIATE
            'ALTER USER ' || :v_admin_user || ' SET RSA_PUBLIC_KEY_2 = ''' || :v_pubkey || '''';
        v_slot := 'RSA_PUBLIC_KEY_2_ROTATED';
    END IF;

    RETURN 'register_admin_public_key: slot=' || :v_slot ||
           ' user=' || :v_admin_user ||
           ' fp=' || :v_local_fp;
END;
