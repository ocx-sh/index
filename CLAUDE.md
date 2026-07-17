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
(`ghcr.io/ocx-contrib/cmake`) via content-digest observation objects. No
server, no database.

Identity + wire contract: [product-context.md](./.claude/rules/product-context.md).
Inherited design + history: [handover_from_ocx.md](./.claude/artifacts/handover_from_ocx.md).

## Current State

Design settled: the 2026-07-16 discussion locked the observation-index format
(root + content-addressed observation objects, revising inherited D3). Design
authority alongside the [handover](./.claude/artifacts/handover_from_ocx.md):
[decision log](./.claude/artifacts/decision_log_2026-07-16.md) and the Phase-0
ADRs — [adr_locked_observation_index_format.md](./.claude/artifacts/adr_locked_observation_index_format.md),
[adr_namespace_policy.md](./.claude/artifacts/adr_namespace_policy.md),
[adr_catalog_docs_colocation.md](./.claude/artifacts/adr_catalog_docs_colocation.md),
[adr_index_bot_and_workflow_security.md](./.claude/artifacts/adr_index_bot_and_workflow_security.md).

Execution of `plan_index_v1` is underway. Phase 3 (WP3-A) has landed: the
render pipeline is live. `.github/workflows/render-deploy.yml` runs
`task render:build` (indexbot render + VitePress build, fixed order — see
`taskfile.yml`) and deploys `site/.vitepress/dist` to Cloudflare Pages,
replacing the retired `public/config.json` + `index.html` placeholder and
`deploy.yml`. Self-activating custom domains (`index.ocx.sh` canonical,
`index.ocx.rs` legacy bootstrap) carried over verbatim into the new
workflow. `p/` is still empty — seed data (Phase 4, 42+ entries) has not
landed, so the deployed tree currently renders `config.json` only.

## Rule Catalog

@.claude/rules.md

## Layout

| Path | Purpose |
|---|---|
| `schema/` | JSON Schemas for the wire contract (`config`, `root`, `observation-object`) |
| `bot/` | `indexbot` — `announce \| reconcile \| validate \| render \| seed-import` |
| `site/` | VitePress 2 catalog + docs, served at `index.ocx.sh` |
| `p/` | Package roots (`p/<ns>/<pkg>.json`) + package-local CAS observation objects (`p/<ns>/<pkg>/o/sha256/<hex>.json`) — empty until Phase 4 seed data lands |
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
- **Cache Rule**: never enable Cloudflare caching for `*.json` on the index zone

## Wire Contract = One-Way Door

Published URL shapes (`/config.json`, `/p/<ns>/<pkg>.json`,
`/p/<ns>/<pkg>/o/sha256/<hex>.json`, `/c/index.json`) + JSON field semantics
must stay backward compatible once ocx clients bake the endpoint. Additive
changes only; `format_version` gates breaking evolution.
