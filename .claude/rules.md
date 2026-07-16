# Index Repo Rule Catalog

Entry point for `.claude/rules/`. Minimal port from ocx-sh/ocx (2026-07-16) — see
`.claude/artifacts/handover_from_ocx.md` for provenance. Any change to `.claude/rules/`
must reflect here in the same commit.

## By concern

| Concern | Rules & skills |
|---|---|
| What this repo is / wire contract | [product-context.md](./rules/product-context.md) |
| Inherited design decisions | `.claude/artifacts/handover_from_ocx.md`, `design_spec_registry_indirection.md`, `adr_public_index_registry_indirection.md` |
| Code quality (any language) | [quality-core.md](./rules/quality-core.md) |
| Shell scripts | [quality-bash.md](./rules/quality-bash.md) |
| Python scripts | [quality-python.md](./rules/quality-python.md) |
| CI workflows / security | [quality-security.md](./rules/quality-security.md) |
| Vite / VitePress build tooling | [quality-vite.md](./rules/quality-vite.md) |
| Swarm / multi-agent workflows | [workflow-swarm.md](./rules/workflow-swarm.md), skills `swarm-plan`, `swarm-execute`, `swarm-review` |
| Plan status tracking | [meta-ai-config.md](./rules/meta-ai-config.md) "Plan Status Protocol" |

## By auto-load path

| Edit path | Rules that auto-load |
|---|---|
| `**/*.sh`, `**/*.bash` | [quality-bash.md](./rules/quality-bash.md) |
| `**/*.py` | [quality-python.md](./rules/quality-python.md) |
| `.github/workflows/**`, `.github/actions/**` | [quality-security.md](./rules/quality-security.md) |
| `**/vite.config.*`, `**/vitest.config.*`, `**/.vitepress/config.*` | [quality-vite.md](./rules/quality-vite.md) |
| `.claude/**` | [meta-ai-config.md](./rules/meta-ai-config.md) |

Globals (no `paths:`): [quality-core.md](./rules/quality-core.md),
[product-context.md](./rules/product-context.md), this catalog.

## Skills

| Task topic | Skill |
|---|---|
| Planning a feature (multi-agent) | `swarm-plan` |
| Executing a plan (multi-agent) | `swarm-execute` |
| Adversarial review | `swarm-review` |

## Not ported (adopt on demand from ocx-sh/ocx)

Hooks, structural tests (`.claude/tests/`), commit/finalize skills, learnings store,
Rust/TypeScript rules, subsystem rules. When a skill or agent references a rule that
does not exist here (e.g. `quality-rust.md`, `subsystem-tests.md`), treat the
reference as N/A — this repo has no Rust.
