---
title: Yank a Version
---

# Yank a Version

Yanking marks one tag row in a package's `tags` map as no longer
recommended for new resolution — "exists, but do not resolve by default" —
without deleting anything. It is a per-tag fact, not a package-level
status, and it is always a human-reviewed change.

## What Yanking Does and Does Not Do

- **Does**: adds a `yanked: {reason, at}` object to exactly one row in
  `tags`, per
  [`root.schema.json`](https://index.ocx.sh/schema/root.schema.json).
- **Does not**: delete the tag row, delete or mutate the observation
  object it points at, or affect any other tag — including tags that
  happen to share the same `content` digest (emergent aliases).

Observation objects are immutable CAS content. A yanked tag's `content`
digest stays exactly as fetchable as before — a consumer that already
pinned that exact digest (a lockfile, a reproducible build) is unaffected.
What changes is forward-looking: new resolutions SHOULD treat a yanked tag
as excluded from default selection. Render-time reachability pruning
(garbage collection of the deployment artifact) only drops an observation
object once **no** tag row anywhere references its digest — yanking one
alias of a shared digest never orphans the object while another
non-yanked tag still points at it.

## Procedure

1. Open a PR editing `p/<namespace>/<package>.json`.
2. Add `yanked` to the specific row under `tags` you want to yank:

   ```json
   "tags": {
     "3.28.0": {
       "content": "sha256:aaaa...",
       "observed": "2026-07-10T00:00:00Z",
       "yanked": { "reason": "build regression on arm64", "at": "2026-07-17T00:00:00Z" }
     }
   }
   ```

3. Leave every other field untouched — do not hand-edit `content` or
   `observed`; those stay bot-regenerated.

This PR always carries a human-review-required classification (see
[Governance Contracts](../reference/governance-contracts) G-05) — it never
auto-merges, even though it looks like a small, otherwise-refresh-shaped
change.

## Un-Yanking

Remove the `yanked` object from the row in the same way — also a
human-reviewed PR, same gate.

## See Also

- [Entry Schema](../reference/entry-schema#tagentry) — the `TagEntry`/
  `Yanked` object shapes
- [Wire Format](../reference/wire-format#yank-semantics) — yank semantics
  in the wire contract
