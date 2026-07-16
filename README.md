# ocx-sh/index

Public package index for **OCX** — namespace governance + sparse HTTP index served at
**https://index.ocx.sh**.

- Logical package names (`ocx.sh/<pkg>`) resolve through pointer files here to
  physical OCI repositories (GHCR, `ocx-contrib`).
- Static files in `public/` deploy to Cloudflare Pages via `.github/workflows/deploy.yml`.
- `public/config.json` is the machine entrypoint (`format_version` + `packages` prefix).

Status: bootstrap. Entry schema, validate/render/announce/reconcile CI, and the seeded
catalog are being designed — see `.claude/artifacts/handover_from_ocx.md` for the
inherited design record (ADR, design spec, research).

## Operating rules

- **Wire contract is a one-way door**: published URL shapes (`/config.json`,
  `/p/<namespace>/<package>.json`) and JSON field semantics stay backward compatible;
  `format_version` gates breaking evolution.
- **Cache Rule**: never enable CDN caching for `*.json` on the index zone — client
  freshness relies on origin ETags.

## Development

Task runner: [`task`](https://taskfile.dev). `task verify` = repo gate (bootstrap:
JSON well-formedness; grows with the design phase).
