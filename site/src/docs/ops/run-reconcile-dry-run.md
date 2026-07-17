---
title: Run a Reconcile Dry Run
---

# Run a Reconcile Dry Run

Reconcile is the index's nightly self-heal: it regenerates every package
entry from live registry truth and diffs the result against the committed
root, independent of whether any announce ever fired. A dry run computes
that diff without committing or opening a PR — the way to verify the bot
agrees with reality before letting it write anything.

## What Reconcile Does

1. For every entry under `p/`, re-observe the physical registry (same
   `observe` → `regenerate` machinery an announce uses).
2. Diff the regenerated root against the currently committed one.
3. **Live mode**: open one PR containing every entry's drift as a
   clean-subset change; any integrity violation (an already-observed tag's
   digest changed unexpectedly) is excluded from that PR, reported instead
   via an anomaly issue, and the run exits `65`.
4. **Dry-run mode**: compute and report the same diff, but write nothing —
   no PR, no commit, no anomaly issue. Output is inspectable in the
   workflow run's logs/summary only.

## Triggering a Dry Run

Reconcile runs on a nightly cron and on `workflow_dispatch`. Mode is
controlled by the `RECONCILE_DRY_RUN` repository
[Actions variable](https://docs.github.com/en/actions/learn-github-actions/variables)
(not a workflow-file edit — see [M-1 Flip](./m1-flip) for the exact
command), read by `reconcile.yml` and passed through as
`indexbot reconcile --dry-run`.

To run one on demand without waiting for the nightly cron:

```sh
gh workflow run reconcile.yml --repo ocx-sh/index
```

This respects whatever `RECONCILE_DRY_RUN` is currently set to. Before the
[M-1 milestone](./m1-flip), that variable defaults to `true`, so every
run — scheduled or manual — is a dry run until explicitly flipped.

## Reading the Result

Check the run's job summary / logs for:

- Per-package diff output (which fields would change, if any).
- Any anomaly the pure diff logic would have flagged as `65` in live mode —
  a dry run reports these too, just without opening an issue for them.
- A clean run (empty diff across every entry) is the expected steady
  state; a dry run with no drift for several consecutive nights is the
  parity signal the M-1 flip decision depends on.

## See Also

- [M-1 Flip](./m1-flip) — flipping `RECONCILE_DRY_RUN` to `false` once
  parity is verified
- [Governance Contracts](../reference/governance-contracts) — G-12
  (nightly reconcile), G-18 (dry-run gate)
