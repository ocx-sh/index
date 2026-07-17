---
title: Announce a Package
---

# Announce a Package

"Announce" is how a publisher tells the index bot "refresh this package
now" after pushing new tags to the physical registry. The payload is a
doorbell, not data: nothing in it is trusted for content, only used as a
lookup key. This page is the **fixed contract** a publisher's own CI
implements against today, by hand — and the one a future `ocx-mirror
pipeline announce` subcommand implements against once it exists (see the
plan's Out of Scope tracking). If that subcommand ships, prefer it; until
then, the raw dispatch below is the supported path.

## Prerequisite

A [namespace claimed](./claim-a-namespace) and populated in this index, and
a namespace-scoped announce PAT stored as a secret in your own publisher
CI — see [Rotate the Announce PAT](../ops/rotate-announce-pat). The PAT can
only fire the announce trigger; it cannot write to the index directly.

## The Dispatch Contract

Fire a GitHub
[`repository_dispatch`](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event)
event against `ocx-sh/index` with:

- `event_type`: `"announce"`
- `client_payload.package`: the logical `<namespace>/<package>` name, e.g.
  `"kitware/cmake"`

```sh
curl -sS -X POST \
  -H "Authorization: Bearer $ANNOUNCE_PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ocx-sh/index/dispatches \
  -d '{"event_type": "announce", "client_payload": {"package": "kitware/cmake"}}'
```

Or with the `gh` CLI:

```sh
gh api repos/ocx-sh/index/dispatches --input - <<'EOF'
{"event_type": "announce", "client_payload": {"package": "kitware/cmake"}}
EOF
```

`client_payload.package` MUST match the two-segment package-id grammar in
[Namespace Policy](../reference/namespace-policy) — an invalid or
oversized value is rejected before it reaches any validation logic
(length-cap-then-`fullmatch`), never used to build a filesystem path
directly.

## What the Bot Does

1. **Validate the payload** — package-id shape only; no trust placed in
   any other part of the payload (there is no other part).
2. **Observe registry truth** — list every tag on the physical repository,
   fetch manifests, hash platform sets into content-addressed observation
   objects.
3. **Regenerate** the target root state from that observation.
4. **Diff** against the currently committed root.
5. **No-op or commit** — an empty diff exits `0` with no PR; a non-empty
   diff opens (or updates) a PR with exactly the regenerated `desc` and
   `tags` changes.

| Outcome | Exit code | What happens |
|---|---|---|
| No-op — nothing changed | `0` | No PR; workflow reports `result=no-op` |
| Applied — diff computed | `0` | PR opened/updated; `result=applied` |
| Validation failure | `1` | Workflow fails; no PR |
| Anomaly — integrity violation | `65` | PR blocked or issue opened; **never auto-healed** |
| Transient — registry backoff exhausted | `75` | Workflow fails; nightly reconcile self-heals |

Because everything written is re-derived from the registry, the payload
cannot lie: a malicious or malformed `client_payload.package` naming a
package you do not control simply re-observes *that* package's real
registry state — it cannot inject arbitrary content.

## PR and Auto-Merge Semantics

The resulting PR is classified automatically:

- **Refresh** (only `desc`/`tags` changed, no
  [human-review-required key](../reference/governance-contracts#auto-merge-decision)
  touched) — auto-merges once both required status checks are green.
- **New package** or **human-review-required** (a first claim, or any
  change to `repository`, `owners`, `status`, `deprecated_message`, or an
  existing tag's `yanked` field) — always blocked for human review,
  regardless of how green the automated checks are.

Concurrent announces of the same package are serialised — the workflow runs
in a `announce-<namespace>-<package>` concurrency group with
cancel-in-progress, so a rapid double-announce collapses to one run rather
than racing two PRs.

## See Also

- [Claim a Namespace](./claim-a-namespace) — the one-time step before your
  first announce
- [Yank a Version](./yank-a-version) — marking a tag row yanked, a separate
  human-reviewed change announce never makes on its own
- [Governance Contracts](../reference/governance-contracts) — G-08
  (payload validation), G-11 (idempotency), G-17 (announce abuse bounds)
