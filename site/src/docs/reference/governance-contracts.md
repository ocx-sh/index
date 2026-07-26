---
title: Governance Contracts
---

# Governance Contracts

The index bot and its workflows enforce twenty governance contracts,
originally defined in `design_spec_registry_indirection.md` against the
pointer-only index and carried forward — several reinterpreted — under the
locked wire format. Design authority:
[`adr_index_bot_and_workflow_security.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_index_bot_and_workflow_security.md)
and its Amendment A1, [`adr_fork_pr_announce.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_fork_pr_announce.md).

| ID | Contract | Status |
|---|---|---|
| G-01 | Schema-shape validation against the JSON Schemas | Kept, reinterpreted — three schema files now, run by `check-jsonschema` in the unprivileged `schema-validate` job, never imported into the bot |
| G-02 | `name` equals the path-derived logical name (`p/<ns>/<pkg>.json` → `<ns>/<pkg>`) | Kept — hand-rolled check, not schema-expressible |
| G-03 | `repository` host allowlist, checked before any network call | Kept — SSRF-ordering guard; the allowlist itself is per-deployment policy, committed at `.github/index-policy.json` (see [below](#registry-host-policy-g-03)) |
| G-04 | New entry file → `new-package` label, mandatory human review, never auto-merge | Kept — namespace-fit judgment is [Namespace Policy](./namespace-policy)'s contract; this gate is the mechanical enforcement |
| G-05 | Green refresh → auto-merge eligible; yank/deprecate/transfer/owners/pointer change → human review always | Kept, key set expanded — human-review-required keys are `repository`, `owners`, `status`, `deprecated_message`, `superseded_by`, and any mutation of an existing tag row's `yanked` field |
| G-06 | Render: source tree → deploy tree | Reinterpreted — no longer an identity copy; reachability-filtered CAS copy, `config.json` emission, `/c/index.json` emission, `/data/catalog/**` emission. Per-package detail pages are VitePress dynamic routes that glob the committed `p/*/*.json` tree directly at build time — not a bot-emitted wrapper-page tree |
| G-07 | Deploy is idempotent; no-op on an unchanged tree | Kept |
| G-08 | `repository_dispatch` payload validated via env-var indirection, regex-checked before use | Kept, regex reinterpreted — exact 2-segment package-id form (see [Namespace Policy](./namespace-policy)) |
| G-09 | Field provenance partition: registry-derived vs human-governed fields never cross-contaminate | Kept, field set updated — see [Entry Schema](./entry-schema#field-provenance) |
| G-10 | Bounded backoff retry on manifest fetch before giving up | Kept — exhaustion exits `75` |
| G-11 | Idempotent, cascade-safe convergence; diff routes to G-04/G-05 merge policy | Kept — idempotency is now an explicit required test ("run twice, second diff empty") |
| G-12 | Nightly reconcile regenerates every entry, diffs, opens one PR with all drift | Kept — see [Run a Reconcile Dry Run](../ops/run-reconcile-dry-run) |
| G-13 | Separate reconcile-maintained state file for anomaly detection | Eliminated as a separate file — the committed root **is** the observation ledger; the anomaly check reads it directly |
| G-14 | Sibling-repo CI hardening: `permissions:` default-deny + SHA-pinned actions everywhere | Kept |
| G-15 | Ownership proof: fetch the physical manifest, verify the embedded canonical identifier equals the entry's logical `name` | Reinterpreted as a pluggable loud-skip seam — the identifier-embedding convention is unconfirmed against actual publishing behaviour, so the probe returns `confirmed`, `mismatch` (blocking), or `unconfirmed` (warns, surfaced on the PR, never a silent pass) |
| G-16 | Privileged/unprivileged workflow split | Kept in full — `schema-validate` runs unprivileged against PR-head content; `governance-gate` is the privileged, API-only job that never checks out PR-head code |
| G-17 | Announce abuse bounds: namespace-scoped PAT, per-package concurrency groups, schema-validated payload | Retired — no namespace-scoped PAT under the fork-PR lane; abuse bounds are the fork-PR spam posture (label failed-check PRs, stale-close) |
| G-18 | Reconcile disabled/dry-run until the seed republish batch is parity-verified | Reinterpreted — a repo Actions variable, `RECONCILE_DRY_RUN`, gates mutation; flip documented at [M-1 Flip](../ops/m1-flip) |
| G-19 | Owners-membership gate for the machine lane | New — a fork PR qualifies for auto-merge only if BOTH hold: its author's `github_id` is in the target root's committed `owners[]`, AND every changed path stays inside those roots' refresh scope (the roots themselves plus their own packages' `p/<ns>/<pkg>/o/sha256/<64-hex>.{json,md,svg,png}` CAS objects). Both are evaluated by the privileged governance job from PR metadata + base-branch root, never PR-head content. The path condition fails closed: any path outside that scope — a workflow file, `bot/**` source, another package's files, an unrelated deletion — routes the PR to the human lane, so an owner of one package cannot attach arbitrary repository content to a refresh-classified PR (ADR-6 FP-5) |
| G-20 | Maintainers-YAML reviewer assignment | New — human-lane PRs get reviewers assigned from a committed `maintainers.yml` (list of `{github, github_id}`) by the privileged governance job, plus an idempotent bot review-request comment |

## Registry-Host Policy (G-03)

`repository` is the pointer every ocx client follows to fetch bytes, so the
set of registry hosts an index will accept is a supply-chain trust decision.
That set is **per deployment**, not compiled into the bot: OCX's index format
is designed as one format, many copies, and an organization running its own
index points at its own registry, not at `ghcr.io`.

Each index repo commits its own policy at `.github/index-policy.json`:

```json
{
  "registry_hosts": ["ghcr.io"]
}
```

For **this** index the effective policy is exactly `ghcr.io` — a root naming
any other host is rejected before the bot makes a single network call, and a
PR that widens the shipped file fails a named test in the bot's security
suite.

Two properties are deliberate:

- **A committed file, never a repository or Actions variable.** "Extend only
  via reviewed PR" is the control. A settings-page variable could widen the
  set of trusted registries with no diff and no reviewer; a file cannot.
- **A host with no registry adapter is refused up front.** The bot implements
  one registry client (`ghcr.io`). Allowlisting a host it cannot fetch from
  would produce entries that pass every validation check and then fail every
  download, so the bot refuses that policy at startup instead — with an error
  naming what is missing. Running an index on another registry needs an
  adapter for it, not just an allowlist entry.

## Auto-Merge Decision

```
PR opened (announce or reconcile)
  ├─ schema-validate green?
  ├─ classified refresh (no G-05 key touched)?
  ├─ every changed path inside the touched roots' refresh scope?
  └─ governance/review-required green?
       all yes → gh pr merge --auto (branch protection completes the merge)
       any no  → blocked until a human approves
```

New-package PRs (G-04) and any PR touching a G-05 human-review-required key
are never auto-merge eligible, regardless of how green the automated checks
are. Nor is a PR that changes anything outside the refresh scope of the roots
it touches — the classifier selects which files are *classified*, never which
files are *allowed*.
