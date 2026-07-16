# Product Context — OCX Public Package Index

Canonical identity doc for this repo. Update when positioning shifts.

## What This Repo Is

The **public package index** for [OCX](https://github.com/ocx-sh/ocx) — the OCI-backed
package manager. This repo is the source of truth for the sparse HTTP index served at
**`https://index.ocx.sh`** (Cloudflare Pages project `ocx-index`).

Model: crates.io sparse index (RFC 2789 lineage). Static JSON over HTTPS — no server,
no database, no API. Clients resolve logical package names (`ocx.sh/cmake`) through
pointer files here to physical OCI registries (`ghcr.io/ocx-contrib/cmake`).

## Wire Contract (one-way door)

Published URL shapes + JSON field semantics are **the** backward-compatibility
surface. Once ocx clients ship with the baked endpoint, breaking either breaks
installed binaries. Additive evolution only; `format_version` gates the rest.

- `/config.json` — root: `format_version`, `packages` prefix
- `/p/<namespace>/<package>.json` — per-package pointer files
- Freshness: ETag / If-None-Match conditional GET

## Relationship to Sibling Repos

| Repo | Role |
|---|---|
| `ocx-sh/ocx` | The client. Consumes this index via sparse HTTP client (planned; see handover) |
| `ocx-sh/ocx-mirror` | Publisher tooling — pushes packages to physical registries |
| `ghcr.io/ocx-contrib/*` | Physical storage for public packages |

Design authority: `.claude/artifacts/design_spec_registry_indirection.md` (governance
contracts G-01…G-18) + `adr_public_index_registry_indirection.md` (D1–D15 + A1),
both ported from the ocx repo — see `handover_from_ocx.md`.

## Non-Goals

- Not a registry (no blobs — pointers only)
- Not a search service (`all.json` snapshot deferred)
- No signing/provenance in v1 (deferred ADR)

## Operating Constraints

- **Cache Rule**: never enable Cloudflare caching for `*.json` on the index zone —
  freshness contract depends on origin ETags
- Sharding trigger: `p/ocx-contrib/` at ~1k files
- All GitHub workflows: `permissions:` default-deny, SHA-pinned actions,
  privileged/unprivileged split (no PR-head execution under `pull_request_target`)
