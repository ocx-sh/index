# CLAUDE.md

Guide Claude Code in this repo.

## ⛔ MODEL POLICY — NON-NEGOTIABLE

Applies to EVERY subagent spawn (Agent tool, Workflow `agent()`, swarm skills).
Always set `model` explicitly — never rely on inherit (a Fable main loop would
silently spawn Fable workers).

| Task | Model |
|---|---|
| Implementation, research, review, docs, tests, exploration — **the default** | **Sonnet 5** (`sonnet`) |
| Genuinely hard problems where Sonnet demonstrably falls short | Opus (`opus`) — rare, justify in the spawn prompt |
| Synthesizing multiple agent results into architecture conclusions | Fable — main loop only, (near-)NEVER as a subagent |

**Never** spawn Fable subagents for review, research, or implementation.
Parallelize Sonnet workers aggressively instead of escalating model tier.

## What This Repo Is

Source of truth for the **OCX public package index** at `https://index.ocx.sh` —
static sparse HTTP index (crates.io model) rendered to Cloudflare Pages. Root
files map logical names (`ocx.sh/kitware/cmake`) to physical OCI registries
(`ghcr.io/ocx-contrib/cmake`) via content-addressed OCI image indices. No
server, no database.

Identity + wire contract: [product-context.md](./.claude/rules/product-context.md).
Inherited design + history: [handover_from_ocx.md](./.claude/artifacts/handover_from_ocx.md).

## Current State

Design settled: the 2026-07-16 discussion locked the index format (root +
content-addressed OCI image indices, revising inherited D3). Design
authority alongside the [handover](./.claude/artifacts/handover_from_ocx.md):
[decision log](./.claude/artifacts/decision_log_2026-07-16.md) and the Phase-0
ADRs — [adr_locked_observation_index_format.md](./.claude/artifacts/adr_locked_observation_index_format.md),
[adr_namespace_policy.md](./.claude/artifacts/adr_namespace_policy.md),
[adr_catalog_docs_colocation.md](./.claude/artifacts/adr_catalog_docs_colocation.md),
[adr_index_bot_and_workflow_security.md](./.claude/artifacts/adr_index_bot_and_workflow_security.md).
Superseding authority for the `o/` shape specifically:
[adr_oci_index_only_dispatch.md](https://github.com/ocx-sh/ocx/blob/main/.claude/artifacts/adr_oci_index_only_dispatch.md)
(`ocx-sh/ocx`) — `o/` holds verbatim OCI image indices, not a bot-authored
projection.

Execution of `plan_index_v1` is underway. Phase 3 (WP3-A) has landed: the
render pipeline is live. `.github/workflows/render-deploy.yml` runs
`task render:build` (`site:build` then `indexbot render --out`, fixed
order — see `taskfile.yml`) and deploys `site/.vitepress/dist` to
Cloudflare Pages, replacing the retired `public/config.json` + `index.html`
placeholder and `deploy.yml`. Self-activating custom domains (`index.ocx.sh`
canonical, `index.ocx.rs` legacy bootstrap) carried over verbatim into the
new workflow.

The `plan_site_redesign` subplan has also landed (Waves 1–2, PRs #21–#26):
`site/` is a blank custom VitePress theme (no `DefaultTheme`) built against
the committed design mock
([`design_mock_site_redesign/`](./.claude/artifacts/design_mock_site_redesign/)),
with per-package detail pages as dynamic routes
(`site/src/[ns]/[pkg].paths.ts`, globbing `p/*/*.json` at build — bot-
generated wrapper pages retired, see
[`adr_catalog_docs_colocation.md`](./.claude/artifacts/adr_catalog_docs_colocation.md)
Amendment A1) and a render-emitted `/data/catalog/catalog.json` view-model
feeding the catalog grid. `task site:serve` / `task demo:seed` give a local
production-shaped preview for design review.

`p/` is still empty — seed data (Phase 4, 42+ entries) has not landed, so
the deployed tree currently renders `config.json` and an empty catalog.

## Rule Catalog

@.claude/rules.md

## Layout

| Path | Purpose |
|---|---|
| `schema/` | JSON Schemas for the wire contract (`config`, `root`, `image-index`) |
| `bot/` | `indexbot` — `announce \| reconcile \| validate \| render \| seed-import` |
| `site/` | VitePress 2 catalog + docs, served at `index.ocx.sh` |
| `p/` | Package roots (`p/<ns>/<pkg>.json`) + package-local CAS OCI image indices (`p/<ns>/<pkg>/o/sha256/<hex>.json`) — empty until Phase 4 seed data lands |
| `.github/workflows/render-deploy.yml` | Renders `p/` via `task render:build`, deploys `site/.vitepress/dist` to Pages + domain/DNS self-activation (replaces retired `deploy.yml`) |
| `.claude/artifacts/` | Handover, ADR, design spec, research (ported from ocx + Phase-0 additions) |
| `.claude/state/plans/` | Plans (gitignored) — Plan Status Protocol applies |

## Workflow

- **Branch + PR + merge** — never commit on `main`. Pushing feature branches and
  merging PRs in THIS repo is the normal flow (unlike ocx-sh/ocx, where pushes are
  human-gated).
- Commits: [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `ci:`, `chore:`, `docs:`). No `Co-Authored-By` trailers.
- Planning: research → ADR/design → plan → execute. Skills: `/swarm-plan`,
  `/swarm-execute`, `/swarm-review`. Artifacts → `.claude/artifacts/`
  (`research_*.md`, `adr_*.md`, `design_spec_*.md`); templates →
  `.claude/templates/artifacts/`.

## Security Invariants (CI)

- `permissions:` default-deny on every workflow; SHA-pinned actions
- Privileged/unprivileged split — never execute PR-head code under
  `pull_request_target`
- Any `client_payload` field validated (regex, no path traversal) via env-var
  indirection — never `run:` interpolation
- **Cron is upstream-only** — every job a `schedule` can reach carries
  `if: github.repository_owner == 'ocx-sh'` (or excludes the schedule event);
  forks inherit every cron and run it off their own stale YAML
- **Cache Rule**: never enable Cloudflare caching for `*.json` on the index zone

## Wire Contract = One-Way Door

Published URL shapes (`/config.json`, `/p/<ns>/<pkg>.json`,
`/p/<ns>/<pkg>/o/sha256/<hex>.json`, `/c/index.json`) + JSON field semantics
must stay backward compatible once ocx clients bake the endpoint. Additive
changes only; `format_version` gates breaking evolution.
