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

The `plan_site_redesign` subplan landed (Waves 1–2, PRs #21–#26), and was
then **superseded** by `plan_catalog_extraction` WP-11 (dogfood switchover):
the catalog/docs theme that plan built (blank custom VitePress theme,
dynamic per-package routes, bot-emitted `/data/catalog/catalog.json`
view-model) has been extracted into the standalone
[`@ocx-sh/catalog`](https://github.com/ocx-sh/catalog) npm package
(published: `@ocx-sh/catalog@0.1.0`, consumed as `^0.1.0` — the npm flip
landed 2026-08-22, closing the last release gap), and this repo now renders
through it instead of its own in-tree theme. `site/` shrank to
consumer-facing content only: `docs/` (hand-authored Markdown) and
`public/` (favicon), plus the root `catalog.config.json`
(`sources: [{path: ".", root: true}]`, brand/nav/docs/publicDir/siteUrl/ci
config) and root `package.json` (`@ocx-sh/catalog: ^0.1.0`).
`task site:build` is `bun install --frozen-lockfile` then `ocx-catalog
build`; `render:build` keeps the same two-pass order as
before (catalog-package build first, `indexbot render --out` second, into
the same tree) because `config.json`/`c/index.json` are optional-per-source
and absent from the raw committed `p/**` tree the package reads, so only
the bot's pass produces them. The bot no longer emits
`/data/catalog/catalog.json` at all — the package's own view-model emitter
does, from the same wire tree.

`.github/workflows/catalog-ci.yml` is **rendered**, never hand-edited:
`ocx-catalog ci` generates it from `catalog.config.json`'s `ci` block
(`forge: github`, `packageManager: bun`), and its own `verify-catalog-ci`
job (`ocx-catalog ci --check`, locally `task cat:ci:check`) fails CI on a
hand-edit or an un-rendered config change. Its `build` job replaced
`ci.yml`'s hand-written `site-build` — post-npm-flip `task site:build`
collapses to exactly the `ocx-catalog build` it runs, so both would be one
assertion billed twice; `render-check` still covers the jq/`RENDER_INDEX_DIR`
and `--out` plumbing the rendered job does not.

The **bot** left too, on 2026-08-24: `bot/` is now
[`ocx-indexbot`](https://pypi.org/p/ocx-indexbot) on PyPI (repo
[ocx-sh/indexbot](https://github.com/ocx-sh/indexbot), import `ocx_indexbot`,
console script still `indexbot`). This repo consumes it through `bot-tools/`,
a project whose only job is to pin it, so the version running in the
privileged governance job changes only by reviewed PR.

**Temporarily a git pin.** `bot-tools/pyproject.toml` points at
`ocx-sh/indexbot` `main` via `[tool.uv.sources]` while this repo dogfoods the
unreleased 0.2.0 — the release that moves an index's identity (`name`,
`name_segments`), its forge and its pipeline files out of the package and into
`.github/index-policy.json`. `uv.lock` records the resolved commit and
`--frozen` enforces it. It goes back to `ocx-indexbot==0.2.0` the moment that
release lands; see
[quality-indexbot-security.md](./.claude/rules/quality-indexbot-security.md).

The five governance workflows are now **generated**: `validate.yml`,
`governance.yml`, `reconcile.yml`, `pr-checks-label.yml` and `stale.yml` come
from `indexbot ci`, rendered from `.github/index-policy.json`'s `ci` block plus
`name_segments`. `ci.yml`'s `verify-indexbot-ci` job (`task bot:ci:check`) is
the drift gate, mirroring `verify-catalog-ci` for the other generator. Never
hand-edit one. `task bot:lint` retired with the source; `task bot:test` now
runs `bot-tools/tests/security/` — the deployment-specific governance
assertions that could not travel with the package (workflow split, `validate.yml`'s
pathspec, the shipped registry policy, retired-surface absences) — and
`task bot:workflows` runs the package's own `indexbot workflows-check`
(WF-01..WF-08) over this repo's workflow tree. `mutmut.yml` went with the
source.

No known release gaps: `@ocx-sh/catalog@0.1.0` is on npm and this repo
consumes it as a real registry dependency — no sibling checkout, no
`cat:build`, every CI job self-contained on this repo's checkout. The
sibling checkout at `~/dev/ocx-catalog` is now only the package's own
development repo, irrelevant to building this one.

`p/` carries real seed data (~1.8k package roots plus their CAS objects),
so the deployed tree renders a populated catalog. `demo/` is the gitignored
throwaway tree `task demo:seed` builds for the identity gate — never
confuse the two when reasoning about what ships.

## Rule Catalog

@.claude/rules.md

## Layout

| Path | Purpose |
|---|---|
| `schema/` | JSON Schemas for the wire contract (`config`, `root`, `image-index`) |
| `bot-tools/` | Pins the released [`ocx-indexbot`](https://pypi.org/p/ocx-indexbot) (`bot-tools/uv.lock`, hash-locked) + `tests/security/` — this deployment's own governance assertions, the half that could not travel with the package. `task bot:test \| bot:workflows \| bot:audit` |
| `.github/index-policy.json` | This deployment's own identity and policy — `name`, `name_segments`, the G-03 registry allowlist, `reserved_namespaces`, `governance.auto_merge`, and the `ci` block `indexbot ci` renders workflows from. A committed file, never a settings-page variable |
| `catalog.config.json` | `@ocx-sh/catalog` config — sources, brand, nav, docs/publicDir mounts, siteUrl, and the `ci` block that renders `catalog-ci.yml` (plan_catalog_extraction WP-11). Install-command strings are NOT config: the `ocx` subcommand names are fixed, so they live in the package as `DEFAULT_INSTALL_FLAVORS` |
| `package.json` | `@ocx-sh/catalog: ^0.1.0` (npm) + its `vitepress`/`vue` peers |
| `site/` | Consumer content only — `docs/` (hand-authored Markdown, mounted via `catalog.config.json`'s `docs`) and `public/` (favicon, via `publicDir`); the catalog/docs theme itself now lives in `@ocx-sh/catalog` |
| `p/` | Package roots (`p/<ns>/<pkg>.json`) + package-local CAS OCI image indices (`p/<ns>/<pkg>/o/sha256/<hex>.json`) — empty until Phase 4 seed data lands |
| `.github/workflows/render-deploy.yml` | Renders `p/` via `task render:build`, deploys `site/.vitepress/dist` to Pages + domain/DNS self-activation (replaces retired `deploy.yml`) |
| `.github/workflows/catalog-ci.yml` | **Generated** by `ocx-catalog ci` from `catalog.config.json`'s `ci` block — never hand-edit; its `verify-catalog-ci` job is the drift gate |
| `.github/workflows/{validate,governance,reconcile,pr-checks-label,stale}.yml` | **Generated** by `indexbot ci` from `.github/index-policy.json` — never hand-edit; `ci.yml`'s `verify-indexbot-ci` job (`task bot:ci:check`) is the drift gate |
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
