# Snowflake CLI Setup

JWT key-pair auth, multi-account profiles, automated key management.
Connection **definitions** live in `~/.snowflake/connections.toml`;
`config.toml` keeps only `default_connection_name` + `[cli.*]`.

## Zero → working (one command)

```bash
./scripts/activate_mac.sh --profile mk07348
```

Seeds `connections.toml`, generates the keypair, registers the admin key (prompts
for your Snowflake password **once**), applies all IaC, and sets up the loader +
transformer service-user keys. After it finishes this Mac is the active control
plane and every connection uses key-pair auth.

> All phases are idempotent — safe to re-run. Only ONE Mac can hold the key slot
> at a time (Snowflake slot-1 limit); running `activate_mac.sh` on another Mac
> invalidates this one's keys.

## Phases (`./setup.sh --phase <P>`)

| Phase | Scripts | What it does | Account writes? |
|---|---|---|---|
| `prereq` | 00–02, init_profile, 03 | install snow, init `~/.snowflake`, gen admin key, seed `[<admin>]` in connections.toml, lock perms | no |
| `init-profile` | init_profile | seed `[<admin>]` non-destructively; set `default_connection_name` (config.toml) | no |
| `admin` | 04–05 | register admin pubkey (password one-shot) → verify JWT | yes (ALTER USER) |
| `promote` | 08 | repoint `[<admin>].warehouse` → ARTWORK_WH, re-verify | no (rewrites connections.toml) |
| `loader` | 06–07 | loader key-pair → register on ARTWORK_LOADER_SVC → test | yes (ALTER USER) |
| `transformer` | 09–10 | transformer key-pair → register on ARTWORK_TRANSFORMER_SVC → test | yes (ALTER USER) |
| `all` | prereq + admin | then prints the `make iac` → promote → loader → transformer reminder | yes |
| `list` | — | print connections.toml connections, mark the default | no |
| `switch` | — | set `default_connection_name` to the selected profile | no |

Canonical fresh-account order: `all` → `make iac CONN=<profile>` → `promote` →
`loader` → `transformer` (or just `activate_mac.sh`).

## Multi-account

```bash
./setup.sh --profile clientb --phase all      # [clientb] / [clientb_loader] / [clientb_transformer]
./setup.sh --profile clientb --phase switch   # make it the default
```

`--profile LABEL` derives connection names + key files. Override names explicitly
with `--admin-conn` / `--loader-conn` / `--transformer-conn`. No flags = the
historical `admin` / `loader` / `transformer` (and `admin_rsa_key.p8` paths).

## File layout

```
~/.snowflake/
├── connections.toml   # connection DEFINITIONS ([<profile>], [<profile>_loader], …); chmod 600
├── config.toml        # default_connection_name + [cli.*] only; chmod 600
├── keys/              # <profile>{,_loader,_transformer}_rsa_key.{p8,pub}; .p8 600 / .pub 644
└── logs/
```

Per-script behavior lives in each script's header banner (the source of truth).
Auth model + helper reference: `docs/context/cli-connection.md`.

<details>
<summary>Edge cases &amp; env vars</summary>

- **Non-interactive seed:** `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_ADMIN_USER`,
  `SNOWFLAKE_ROLE` (default `ACCOUNTADMIN`), `SNOWFLAKE_WAREHOUSE` (default
  `COMPUTE_WH`), then `./setup.sh --phase init-profile`.
- **Admin password:** `SNOWFLAKE_PASSWORD` (else prompted; never stored).
- **Force key rotation:** `OVERWRITE_LOADER_KEY=1` / `OVERWRITE_TRANSFORMER_KEY=1`
  / `OVERWRITE_ADMIN_KEY=1`.
- **Direct connection test:** `snow connection test -c <profile>`.
- **Inspect:** `./setup.sh --phase list`; `cat ~/.snowflake/connections.toml`;
  `ls -la ~/.snowflake/keys/`.
- **Field name:** connections.toml uses `private_key_path` (read by the snow CLI,
  the VS Code extension, and the Python connector).
</details>
