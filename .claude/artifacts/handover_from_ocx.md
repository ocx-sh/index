# Handover: Public Index — from ocx-sh/ocx planning (2026-07-16)

Everything this repo inherits from the planning cycle that ran in ocx-sh/ocx
(swarm-plan tier max, 2026-07-12, + owner amendments through 2026-07-16). Read this
first; then the design record for detail.

## Mission

Ship a production-quality public package index at `index.ocx.sh`: entry schema v1,
validation + render CI, announce doorbell, reconcile cron, 42 seeded entries pointing
at `ghcr.io/ocx-contrib/<pkg>`. Standalone value: browsable public catalog. The ocx
client-side work (baked registry map, sparse index client) lives in ocx-sh/ocx and is
**blocked on this repo** proving format v1 stable + migration gate M-1.

Owner direction: this repo runs its **own research → design phase** before
implementation. The ported artifacts below are input, not gospel — re-derive where
evidence says otherwise, EXCEPT the one-way doors (below).

## Live State (verified 2026-07-16)

- `https://index.ocx.sh/config.json` — 200, placeholder `{"format_version": 1, "packages": "/p/", ...}`
- Cloudflare Pages project `ocx-index`, production branch `main`, deploys `public/` verbatim
- Custom domains: `index.ocx.sh` (canonical; proxied CNAME in ocx.sh zone) +
  `index.ocx.rs` (legacy bootstrap — detach at ocx.rs disposal, domain then idles)
- `.github/workflows/deploy.yml`: wrangler deploy + idempotent domain/DNS self-activation
- Repo secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
- 42 public packages currently served from self-hosted Artifactory behind `ocx.sh/v2`
  (nginx). Republish to ghcr.io/ocx-contrib = migration step here (M-1 gate below).

## One-Way Doors (do NOT re-litigate without owner)

1. **Wire contract**: `/config.json` root + `/p/<namespace>/<package>.json` pointer
   files + ETag freshness. Once ocx clients bake the endpoint, URL shapes + field
   semantics are frozen (additive only; `format_version` gates breaks).
2. **Canonical name**: `ocx.sh` (ADR Amendment A1). `ocx.rs` parked — no alias
   anywhere; re-activation later = additive row in the ocx client's baked map.
3. **Physical storage**: `ghcr.io/ocx-contrib/<pkg>`. Published packages embed
   `ocx.sh/...` identifiers verbatim — no identifier rewrite at republish (A1 + D6).
4. **Logical/physical two-plane split** (D10/D15): index = logical plane; endpoint
   URLs are plumbing. The ocx client maps `ocx.sh → index+https://index.ocx.sh`.

## Key Inherited Decisions (ADR D1–D15 + A1 — full text in adr_*.md here)

- Sparse HTTP index, crates.io model — no git-clone index, no API server (D1)
- `all.json` search snapshot deferred (D2); sharding deferred until `p/ocx-contrib/` ~1k files
- Namespace = GitHub org/user ownership; repository-allowlist validation (D6)
- v1 announce transport = `repository_dispatch` + fine-grained PAT (GitHub App = v2)
- Registry truth wins: announce regenerates entry from registry, never trusts payload fields
- Signing/provenance deferred to own ADR; OIDC trusted publishing = v2

## Governance Contracts G-01…G-18 (design spec §; §10/§11 amendments authoritative)

Themes — full text in `design_spec_registry_indirection.md`:

- **Validate** (`validate.yml`): JSON schema + repository-allowlist + ownership
  manifest check (G-15); field-provenance partition — registry-derived vs
  human-governed fields never cross-contaminate (G-09)
- **Render/deploy** (`render-deploy.yml`): replaces bootstrap deploy.yml; Pages deploy
- **Announce** (`announce.yml`): repository_dispatch doorbell → regenerate from
  registry truth; bounded backoff retry; concurrency groups + namespace-scoped
  secrets (G-17); `client_payload.package` validated (regex, no traversal, env-var
  indirection — never `run:` interpolation)
- **Reconcile** (`reconcile.yml`): nightly cron; digest mutation on a published
  version = hard-stop anomaly; bot commits `state/observed-digests.json` (G-13);
  **disabled/dry-run until M-1 passes** (G-18, M-3)
- **Workflow security**: privileged/unprivileged split, no PR-head execution under
  `pull_request_target` (G-16); permissions default-deny + SHA-pinned actions

## Migration Gates (human-gated ops)

- **M-1**: republish 42 packages → ghcr.io/ocx-contrib (batch by namespace, bounded
  concurrency; ocx-mirror scope). Gate = recorded tag×platform parity matrix vs
  Artifactory + `ocx install <logical>` smoke pull per package. curl 200 is NOT the gate.
- **M-2** (ocx repo scope): old binaries hit Artifactory directly regardless of
  lockfiles — verify all active consumers upgraded + announced window before decommission.
- **Handoff gate**: format v1 stable through republish + M-1 passed → ocx client plan
  (`plan_registry_indirection_client.md` in ocx repo) may start.

## Open Design Questions (for the research phase HERE)

- Entry schema v1 final field set (see `research_sparse_index_formats.md` — crates.io/
  BCR/winget comparison + proposed additions: platforms, license, description, owners)
- Rendering pipeline: what transforms `p/` source files → deployed `public/` (currently
  verbatim); human-readable catalog page?
- Announce bot auth + rate limiting details; PAT rotation story
- Ownership/governance model for third-party namespaces (beyond ocx-contrib)
- Repo tooling: task runner, schema validation harness, dogfood ocx toolchain
  (`ocx.toml`) for CI tools?

## Sibling-Repo Coupling

| Repo | Coupling |
|---|---|
| ocx-sh/ocx | Client plan blocked on this repo's M-1 + format stability; release of baked map gated on index.ocx.sh 200s (spec §12.7) |
| ocx-sh/ocx-mirror | Executes the 42-package republish; owner doctrine: mirror drives operations via ocx CLI (arch doctrine in ocx repo) |

## Provenance

Ported artifacts (copied, not linked — ocx repo remains original):
`adr_public_index_registry_indirection.md`, `design_spec_registry_indirection.md`
(read §10/§11/§12 amendments as authoritative over earlier sections),
`research_sparse_index_formats.md`, `research_index_announce_bots.md`,
`research_ghcr_constraints.md`. Client-side artifacts (codebase discovery, C-contracts
detail) intentionally NOT ported — they live with the ocx client plan.
