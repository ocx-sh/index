---
paths:
  - .claude/**
---

# AI Configuration Meta-Rule (index repo — slim port)

Slim port from ocx-sh/ocx. Carries only what the swarm skills need here: the Plan
Status Protocol. Full version (activation layers, context budget, learnings store,
structural tests) lives in the ocx repo; adopt more sections only when this repo
actually grows the corresponding machinery.

## Context Budget (essentials)

- CLAUDE.md <200 lines; rules <200 lines each; SKILL.md <500 lines
- Path-scope rules (`paths:` frontmatter) over globals; catalog `.claude/rules.md`
  must reflect any rules change in the same commit

## Plan Status Protocol

Every plan in `.claude/state/plans/plan_*.md` carries a `## Status` block at the top —
first 30 lines after H1.

### Schema

```markdown
## Status

- **Plan:** plan_<slug>
- **Active phase:** <N> — <phase title>
- **Step:** <skill or activity, e.g. /swarm-execute → implementation>
- **Last update:** <YYYY-MM-DD> (after <commit-sha-short>: <subject>)
```

Allowed `Step` values:
- `/swarm-plan → plan-approved`
- `/swarm-execute → <stage>` (Stub, Specify, Implement, Review-Fix Loop)
- `/swarm-review → round N`
- `awaiting /swarm-review`
- `awaiting /swarm-execute (review-fix loop)`
- `awaiting /finalize`
- `finalized` (terminal)

### Global pointer

`.claude/state/current_plan.md` (gitignored):

```markdown
# Current Plan Pointer

- **Plan:** .claude/state/plans/plan_<slug>.md
- **Branch:** <branch-name>
- **Updated:** <YYYY-MM-DD HH:MM UTC>
```

### Mutation rules

| Skill | Reads | Writes |
|---|---|---|
| `/swarm-plan` | — | Init Status in new plan; write `current_plan.md` |
| `/swarm-execute` | Status | Flip `Step` on phase entry/advance; bump `Last update` |
| `/swarm-review` | Status | Flip `Step` on round entry; set awaiting-verdict steps |

Phase advancement (`Active phase: N → N+1`) is an explicit orchestrator decision —
never an automatic side-effect of commits.

Subplans: optional `**Parent plan:**` field; on subplan finalize, repoint
`current_plan.md` back to the parent.
