# ocx-sh/index

Source of truth for the **OCX public package index**, served as a static sparse
HTTP index at **https://index.ocx.sh** — no server, no database, no API. OCX is
the OCI-backed package manager at [ocx-sh/ocx](https://github.com/ocx-sh/ocx).

Clients resolve logical package names (`ocx.sh/<namespace>/<package>`, e.g.
`ocx.sh/kitware/cmake`) through JSON files in this repo to physical
[OCI](https://opencontainers.org/) registries (`ghcr.io/ocx-contrib/<package>`).

## Wire format at a glance

Three frozen URL shapes, gated by `format_version`:

- `/config.json` — `{"format_version": 1}`
- `/p/<namespace>/<package>.json` — package root: governance fields + a `tags`
  map from every announced tag (owner-curated) to a content digest
- `/p/<namespace>/<package>/o/sha256/<hex>.json` — immutable observation
  object: the set of OCI platforms and the manifest digest each resolved to

**Locked observation**: an observation object is a frozen record of which
platform resolved to which manifest digest at the moment the index bot last
observed the registry — not a live query, not a cache.

Published shapes and field semantics are a one-way door once OCX clients bake
the endpoint in: additive changes only, `format_version` gates the rest. See
[`.claude/artifacts/`](.claude/artifacts/) for the design record (ADRs,
decision log) and [product-context.md](.claude/rules/product-context.md) for
the full contract. Human-facing docs land at `index.ocx.sh/docs` (incoming,
built with [VitePress](https://vitepress.dev/)).

## Repo state

`.github/workflows/render-deploy.yml` renders `p/` (via `indexbot render` +
the VitePress build) into `site/.vitepress/dist` and deploys that tree to
[Cloudflare Pages](https://pages.cloudflare.com/), serving `index.ocx.sh`.
This replaces the earlier `public/` placeholder and `deploy.yml`, both
retired. `p/` is still empty pending Phase 4 seed data, so the deployed
index currently exposes `config.json` only.

## Operating rules

- **Wire contract is a one-way door** — see above.
- **Cache Rule**: never enable CDN caching for `*.json` on the index zone —
  client freshness relies on origin ETags.

## Development

Task runner: [`task`](https://taskfile.dev). `task verify` is the repo gate.
