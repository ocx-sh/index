# Classification Signals — /swarm-review

Signal-to-tier map for `/swarm-review` tier=`auto`.
Also defines overlay triggers stack on chosen tier.

**Primary signals: diff metrics.** Unlike `/swarm-plan` (classify
from prompt) and `/swarm-execute` (read plan header), review
classify from **actual diff vs configured baseline**.
`--base=<ref>` = biggest lever on auto tier — tight baseline
(recent commit, sibling branch) → small diff → `low`; wide
baseline (`main` on long-lived branch, old tag) → big diff →
`high` or `max`.

Signals split adjacent tiers, or overlay mix unusual?
Mark **low-confidence** — forces meta-plan gate in SKILL.md step 5.
Do **not** fire mid-flow `AskUserQuestion`.

## Primary: diff metrics

Compute once at classification start:

```
git diff <base>...HEAD --name-only    # → changed-file list
git diff <base>...HEAD --shortstat    # → lines added/removed
```

Derive:

- **file_count** — `wc -l` of name-only output
- **lines_changed** — `added + removed` from `--shortstat`
- **subsystems_touched** — match each path vs repo surfaces
  (`public/`, `p/`, JSON schemas, `.github/workflows/`, `scripts/`)
- **structural_markers** — see table below
- **pr_labels** — only when target resolves to PR

## Tier metric table

| Tier | file_count | lines_changed | subsystems | structural markers |
|------|-----------|---------------|------------|-------------------|
| **low** | ≤3 | ≤100 | 1 | None from adversarial list |
| **high** | ≤15 | ≤500 | 1–2 | No One-Way Door High signals |
| **max** | >15 or any One-Way Door High signal | any | ≥2 or cross-subsystem | Any One-Way Door High signal |

Diff may match multiple rows — pick **highest** tier with ≥1
clear signal firing. Small file count no demote diff
touching wire-contract surface.

## Structural marker signals

| Marker | Tier impact |
|---|---|
| `public/config.json` shape change | → **max** (wire contract — one-way door) |
| `p/**` URL or field semantics change | → **max** (wire contract — one-way door) |
| JSON schema changes | → **max** (wire contract; `format_version` consideration) |
| `.github/workflows/**` changes | → **high** minimum; adds `--breadth=full`; `--codex` auto-on at high (security-sensitive) |
| Announce/reconcile auth or payload-validation logic | Adds `--breadth=adversarial` at high+ |
| Auth, secrets, PAT-handling paths | Adds `--codex`; security review required |
| Removed/renamed published field or endpoint | → **max**, adds `--codex` |
| `README.md` / `public/index.html` cosmetic only | Hint toward **low** |

## PR label signals

Target resolves to PR? Read labels, apply:

| Label | Effect |
|---|---|
| `breaking-change` | → **max**; `--codex` on |
| `security` | Adds `--breadth=adversarial`; `--codex` on |
| `epic` | → **max** |
| `small` | Hint toward **low** (metrics can still escalate) |
| `docs` | Hint toward **low** if no code paths touched |
| `chore` | Hint toward **low** |

Labels never *demote* below metrics dictate — `small` label
on 30-file diff still high (size beat label).

## Confidence rules

- **Confident**: one tier has ≥2 matching signals (metrics OR
  markers OR labels), no competing signals from adjacent tier.
  Proceed without meta-plan gate.
- **Low-confidence**: signals split adjacent tiers (e.g.,
  metrics say `low`, one structural marker say `high`), or diff
  empty-but-metadata-only (e.g., rename-only), or target
  ambiguous. Flag; SKILL.md routes into meta-plan gate.

Never manufacture question when confident. *Announce and proceed*, or
*let meta-plan gate handle*.

## Overlay triggers

Overlays adjust single axis on top of chosen tier. Stack —
multiple triggers may fire. Axis defs live in `overlays.md`.

| Overlay | Triggered by |
|---|---|
| `--breadth=full` | tier=high (default); `.github/workflows/**` or JSON schema paths touched at tier=low (escalation) |
| `--breadth=adversarial` | tier=max (default); announce/reconcile auth or payload-validation logic touched at tier=high; `security` label; `--rca=on` together with ≥2 subsystems |
| `--reviewer=haiku` | tier=low AND NO structural markers from "Structural marker signals" table present in diff |
| `--reviewer=opus` | tier=max AND `--breadth=adversarial` |
| `--doc-reviewer=haiku` | Diff touches ≤2 doc files (`README.md` or `public/index.html`) |
| `--rca=on` | tier=high+ (default) — scope differs per tier (see overlays.md) |
| `--codex` | One-Way Door structural marker; `breaking-change` or `security` label; public API change; new crate; protocol change |

Defaults per tier (before overlays apply):

| Axis | low | high | max |
|---|---|---|---|
| breadth | minimal | full | adversarial |
| reviewer | haiku (→ sonnet on structural markers) | sonnet | sonnet (→ opus on adversarial breadth) |
| doc-reviewer | sonnet | sonnet (→ haiku on narrow doc scope) | sonnet (→ haiku on narrow doc scope) |
| rca | off | on (Block/High) | on (>Suggest) |
| codex | off | off (auto-on for One-Way Door signals) | on (mandatory) |

## Baseline interaction with auto-tier

`--base` change what classifier see:

| Invocation | Typical diff size | Typical auto tier |
|---|---|---|
| `/swarm-review` (no base → `main`, long-lived branch) | 50+ files | **high** or **max** |
| `/swarm-review --base=HEAD~1` | ≤3 files | **low** |
| `/swarm-review --base=<parent-branch>` | a few commits | **low** or **high** |
| `/swarm-review --base=<older-tag>` | entire release delta | **max** |
| `/swarm-review <PR>` (base auto-resolved to PR base) | PR-sized diff | tier matches PR scope |

Intended design: **baseline controls effort**. User want
quick re-check of last commit → pass `--base=HEAD~1`; user
reviewing release-cut → let default baseline expand scope.

## Examples

1. `/swarm-review` on 2-commit branch, 5 files in
   `.github/workflows/` → tier=**high**, `--breadth=full`,
   `--codex` auto-on (workflows security-sensitive), confident.
2. `/swarm-review --base=HEAD~1` on one-line `README.md` fix →
   tier=**low**, `--breadth=minimal`, `--rca=off`, `--codex=off`,
   confident.
3. `/swarm-review 143` where PR #143 has labels
   `breaking-change` + `enhancement`, touches `public/config.json`
   → tier=**max** (wire contract), `--breadth=adversarial`,
   `--codex=on`, confident.
4. `/swarm-review --base=<old-tag>` on branch 30 commits ahead
   → tier=**max** by metrics, meta-plan gate fires (max auto-fires
   gate).
5. `/swarm-review` with 4 files changed across `scripts/` and
   `.github/workflows/` → metrics say `low` (size) but workflows
   marker says `high`; low-confidence → meta-plan gate fires.