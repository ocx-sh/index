---
title: M-1 Flip
---

# M-1 Flip

M-1 is the milestone at which the seed package republish batch (the initial
namespace-under-vendor-identity import) is verified to have reconciled
cleanly, and reconcile is allowed to start writing for real. Until that
point, `reconcile.yml` runs in dry-run mode on every scheduled and manual
trigger — see [Run a Reconcile Dry Run](./run-reconcile-dry-run).

## Mechanism

Dry-run mode is controlled by a repository
[Actions variable](https://docs.github.com/en/actions/learn-github-actions/variables),
`RECONCILE_DRY_RUN`, read by `reconcile.yml` on every run. Flipping it is a
one-line `gh` command, not a workflow-file edit — no PR, no redeploy
required:

```sh
gh variable set RECONCILE_DRY_RUN --body false --repo ocx-sh/index
```

## Before Flipping

Confirm, from consecutive dry-run outputs (see
[Run a Reconcile Dry Run](./run-reconcile-dry-run)):

- [ ] Every seed entry's dry-run diff is empty (or, for entries mid-import,
      the diff exactly matches an expected, already-reviewed change).
- [ ] No anomaly (`65`-class) findings across any seed entry.
- [ ] Every seed root is schema-valid and every content digest verifies
      (the same chain a client walks — see
      [Wire Format](../reference/wire-format#verifiability-chain)).
- [ ] `schema-validate` and `governance-gate` are both green on `main`.

Flipping before this checklist is clean means the first live reconcile run
can open a PR (or an anomaly issue) against drift nobody has reviewed yet.

## After Flipping

Reconcile's nightly cron begins writing for real: clean drift becomes a
real PR (subject to the normal governance gate — G-05 keys still require
human review), and integrity violations open a real anomaly issue and exit
`65` instead of only being visible in dry-run logs.

## Rolling Back

If reconcile starts producing unexpected PRs or anomaly noise after the
flip, pause it the same way, no workflow edit needed:

```sh
gh variable set RECONCILE_DRY_RUN --body true --repo ocx-sh/index
```

This does not touch announce — `announce.yml` is unaffected by
`RECONCILE_DRY_RUN` and continues writing on every valid dispatch
regardless of reconcile's mode.
