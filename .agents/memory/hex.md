# hex memory — ocx-sh/index

## Pointers

- Verification: `task verify` (repo root taskfile; bot gate = `task bot:test`, 100% branch)
- Plans: `.claude/state/plans/` (gitignored; Plan Status Protocol in `.claude/rules/meta-ai-config.md`)
- ADR/research artifacts: `.claude/artifacts/` (`adr_*.md`, `research_*.md`, templates in `.claude/templates/artifacts/`)
- Product context: `.claude/rules/product-context.md`; rule catalog `.claude/rules.md`
- Model policy: repo CLAUDE.md "MODEL POLICY" table (sonnet default for ALL workers; never Fable subagents)
- Federation: `cat` → /home/mherwig/dev/ocx-catalog (no remote — local-only, bootstrapped 2026-08-22); verification documented in plan_catalog_extraction "Executable phases" (package `npm test`, 100% branch)

## Preferences

(defaults — no overrides yet; adversary = codex plugin, one-shot)

## Memory

- Active plan: `.claude/state/plans/plan_catalog_extraction.md` (state: plan-approved, 2026-08-21; tier high)
