-- Generic key registration template.
-- Variables substituted by snow CLI --variable at invocation time:
--   <% service_user %>   -- the service user (e.g. ARTWORK_LOADER_SVC)
--   <% rsa_public_key %> -- the RSA public key body (no PEM header/footer)
ALTER USER <% service_user %> SET RSA_PUBLIC_KEY = '<% rsa_public_key %>';
