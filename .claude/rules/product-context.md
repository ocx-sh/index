# Product Context — OCX Public Package Index

Canonical identity doc for this repo. Update when positioning shifts.

## What This Repo Is

The **public package index** for [OCX](https://github.com/ocx-sh/ocx) — the OCI-backed
package manager. This repo is the source of truth for the sparse HTTP index served at
**`https://index.ocx.sh`** (Cloudflare Pages project `ocx-index`).

Model: crates.io sparse index (RFC 2789 lineage). Static JSON over HTTPS — no server,
no database, no API. Clients resolve logical package names (`ocx.sh/kitware/cmake`)
through root files here to physical OCI registries (`ghcr.io/ocx-contrib/cmake`);
each root records every announced tag (owner-curated) as a content digest pointing at
an immutable observation object (see Wire Contract below).

## Wire Contract (one-way door)

Published URL shapes + JSON field semantics are **the** backward-compatibility
surface. Once ocx clients ship with the baked endpoint, breaking either breaks
installed binaries. Additive evolution only; `format_version` gates the rest.
Design authority: [adr_locked_observation_index_format.md](../artifacts/adr_locked_observation_index_format.md)
(index format), [adr_namespace_policy.md](../artifacts/adr_namespace_policy.md)
(namespace segment, reserved names), and
[adr_fork_pr_announce.md](../artifacts/adr_fork_pr_announce.md) (announce transport +
`tags` provenance: fork PRs, owner-curated tags, verify-only reconcile).

Four frozen URL shapes:

- `/config.json` — `{"format_version": 1}`, nothing else
- `/p/<namespace>/<package>.json` — package root: governance fields (`name`,
  `repository`, `owners`, `status`, `created`, `upstream`, `desc`, …) + `tags`,
  a map from **every announced tag** (owner-curated — the owner announces the tags
  they choose, each CI-verified against registry truth; see
  [adr_fork_pr_announce.md](../artifacts/adr_fork_pr_announce.md)) to its content
  digest (`sha256` of the observation object it points at)
- `/p/<namespace>/<package>/o/sha256/<hex>.json` — observation object:
  content-addressed, immutable, `platforms[{platform, digest}]` where
  `platform` is an OCI platform object and `digest` is the manifest digest it
  resolved to. Lock unit is the **platform manifest**, never the image index
  (revises inherited D3)
- `/c/index.json` — enumeration index: `{"format_version": 1, "packages":
  {"<ns>/<pkg>": "sha256:<hex>", ...}}`, a sorted map from every published
  package to the exact-bytes digest of its package root, for whole-catalog
  sync via conditional GET + digest diff (additive, 2026-07-17; see
  [adr_enumeration_index.md](../artifacts/adr_enumeration_index.md))

Desc blobs (`/p/<namespace>/<package>/o/sha256/<hex>.{md,svg,png}` — README,
logo) reuse the same content-addressed CAS convention as the observation
object path above, and — like all package-local CAS content — their bytes are
CI hash-verified against their path digest on announce (see
[adr_fork_pr_announce.md](../artifacts/adr_fork_pr_announce.md) FP-4). They are
not, however, one of the three enumerated frozen shapes:
`plan_index_v1.md`'s Wire Format block leaves the desc-blob path unannotated
for frozen-contract status, and this doc does not resolve that ambiguity on
its own.

Example: `ocx.sh/kitware/cmake` resolves through `/p/kitware/cmake.json`.

`/data/catalog/**` and the VitePress catalog/docs pages (`/`, `/docs/**`) are
**not** wire contract — free to evolve, never baked into a client.

Freshness: ETag / If-None-Match conditional GET.

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
- Not a search service — full-text/browse search stays deferred; name+digest
  enumeration exists at `/c/index.json` (see
  [adr_enumeration_index.md](../artifacts/adr_enumeration_index.md))
- No signing/provenance in v1 (deferred ADR)

## Operating Constraints

- **Cache Rule**: never enable Cloudflare caching for `*.json` on the index zone —
  freshness contract depends on origin ETags
- Sharding trigger: `p/ocx-contrib/` at ~1k files
- All GitHub workflows: `permissions:` default-deny, SHA-pinned actions,
  privileged/unprivileged split (no PR-head execution under `pull_request_target`)
