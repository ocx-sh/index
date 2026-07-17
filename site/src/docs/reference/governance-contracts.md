---
title: Governance Contracts
---

# Governance Contracts

The index bot and its workflows enforce eighteen governance contracts,
originally defined in `design_spec_registry_indirection.md` against the
pointer-only index and carried forward — several reinterpreted — under the
locked-observation wire format. Design authority:
[`adr_index_bot_and_workflow_security.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_index_bot_and_workflow_security.md).

| ID | Contract | Status |
|---|---|---|
| G-01 | Schema-shape validation against the JSON Schemas | Kept, reinterpreted — three schema files now, run by `check-jsonschema` in the unprivileged `schema-validate` job, never imported into the bot |
| G-02 | `name` equals the path-derived logical name (`p/<ns>/<pkg>.json` → `<ns>/<pkg>`) | Kept — hand-rolled check, not schema-expressible |
| G-03 | `repository` host allowlist, checked before any network call | Kept — SSRF-ordering guard |
| G-04 | New entry file → `new-package` label, mandatory human review, never auto-merge | Kept — namespace-fit judgment is [Namespace Policy](./namespace-policy)'s contract; this gate is the mechanical enforcement |
| G-05 | Green refresh → auto-merge eligible; yank/deprecate/transfer/owners/pointer change → human review always | Kept, key set expanded — human-review-required keys are `repository`, `owners`, `status`, `deprecated_message`, and any mutation of an existing tag row's `yanked` field |
| G-06 | Render: source tree → deploy tree | Reinterpreted — no longer an identity copy; reachability-filtered CAS copy, `config.json` emission, `/data/catalog/**` emission, per-package wrapper-page emission |
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
| G-17 | Announce abuse bounds: namespace-scoped PAT, per-package concurrency groups, schema-validated payload | Kept — see [Rotate the Announce PAT](../ops/rotate-announce-pat) |
| G-18 | Reconcile disabled/dry-run until the seed republish batch is parity-verified | Reinterpreted — a repo Actions variable, `RECONCILE_DRY_RUN`, gates mutation; flip documented at [M-1 Flip](../ops/m1-flip) |

## Auto-Merge Decision

```
PR opened (announce or reconcile)
  ├─ schema-validate green?
  ├─ classified refresh (no G-05 key touched)?
  └─ governance/review-required green?
       all yes → gh pr merge --auto (branch protection completes the merge)
       any no  → blocked until a human approves
```

New-package PRs (G-04) and any PR touching a G-05 human-review-required key
are never auto-merge eligible, regardless of how green the automated checks
are.
