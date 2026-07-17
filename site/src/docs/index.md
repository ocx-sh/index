---
title: Docs
---

# Docs

Wire-format reference, how-to guides, operational runbooks, and design
background for the OCX public index — for package publishers and index
operators. Organised by task type
([Diátaxis](https://diataxis.fr/)): reference for looking things up,
how-to for getting something done, ops for running the index itself,
explanation for the reasoning behind it.

## Reference

Look something up. Precise, exhaustive, no narrative.

- [Wire Format](/docs/reference/wire-format) — the three frozen URL shapes,
  field semantics, freshness, `format_version` gating
- [Entry Schema](/docs/reference/entry-schema) — full field table for the
  package root and observation object
- [Namespace Policy](/docs/reference/namespace-policy) — the
  `<namespace>/<package>` charset, reserved segments, dispute policy
- [Governance Contracts](/docs/reference/governance-contracts) — the
  G-01–G-18 automated/human review contracts
- [Changelog](/docs/reference/changelog) — `format_version`-keyed history

## How-To

Get a specific task done.

- [Announce a Package](/docs/how-to/announce-a-package) — trigger the bot
  to re-observe your registry and refresh your entry
- [Claim a Namespace](/docs/how-to/claim-a-namespace) — first-claim PR flow
- [Yank a Version](/docs/how-to/yank-a-version) — mark a tag row yanked

## Ops

Run the index itself.

- [Rotate the Announce PAT](/docs/ops/rotate-announce-pat)
- [Run a Reconcile Dry Run](/docs/ops/run-reconcile-dry-run)
- [M-1 Flip](/docs/ops/m1-flip) — enabling live reconcile writes

## Explanation

Understand why it works this way.

- [Architecture](/docs/explanation/architecture) — the locked-observation
  model, the verifiability chain, why manifests not indexes
