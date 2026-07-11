# ocx-rs/index

Public package index for **OCX** — namespace governance + sparse index for `ocx.rs`.

- Logical registry `ocx.rs` resolves package names → physical OCI repos (GHCR, `ocx-contrib`).
- Static files in `public/` deploy to Cloudflare Pages at https://ocx.rs via `.github/workflows/deploy.yml`.
- `public/config.json` is the machine entrypoint (`format_version` + endpoints).

Design record: `adr_public_index_registry_indirection.md` in the ocx repo. Entry schema,
announce bot, and reconcile CI are finalized in the planning phase.
