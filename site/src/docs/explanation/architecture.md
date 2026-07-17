---
title: Architecture
---

# Architecture

Why the index locks what it locks, and what "locked observation" means in
practice. Design authority:
[`adr_locked_observation_index_format.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_locked_observation_index_format.md).

## The Problem: Non-Atomic Multi-Platform Pushes

Publishing a multi-platform OCI image is a per-platform read-modify-write
cascade against an image index: each platform's manifest is pushed, then
the index is rewritten to include it. The index digest churns mid-publish,
and churns again on every subsequent platform addition. This was named
directly in
[ocx-sh/ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076):
a lock that records an image-index digest bakes that churn into every
consumer that trusts it.

Meanwhile `ocx.lock` (the client's own dependency lock) and OCX's
index-lock already lock platform manifests, not image indexes, elsewhere in
the pipeline. A public index that locked image-index digests would be
inconsistent with the locking unit used one layer away.

## Why Manifests, Not Indexes

Platform manifests are pushed once, by digest, **before** any index
rewrite — they are the stable primitive in the whole push sequence. Image
indexes float by nature: platforms get added, rolling tags advance. Locking
a floating thing bakes registry-side churn into every reader; locking the
stable thing does not. The index therefore records, per observed tag, the
set of `platform → manifest digest` pairs it saw — never the image-index
digest — making the public index, `ocx index-lock`, and `ocx.lock` all
speak the same locking doctrine: "the content of the index at observation
time T," not "the index's own digest at time T." This directly resolves the
inconsistency [ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076)
named.

## Why Root + CAS, Not One File Per Package

An earlier sketch of this format used one small JSON file per package,
holding both mutable pointer state and observation history together. That
does not survive contact with per-tag observation data: a single file would
grow with every tag ever observed and rewrite its entire contents on every
commit, defeating CDN caching for content that rarely actually changes.

Splitting the two apart — a tiny, forever-small mutable **root**
(`/p/<namespace>/<package>.json`) pointing at immutable, content-addressed
**observation objects** (`/p/<namespace>/<package>/o/sha256/<hex>.json`) —
mirrors OCI's own manifest/blob split rather than inventing a new pattern.
The root stays cheap to re-fetch regardless of how much history
accumulates; CAS objects are permanently cacheable and automatically
deduplicated whenever two observations see an identical platform set (byte-
identical JSON hashes to the same digest). This is the same pointer/payload
shape the sparse-index research surveyed elsewhere — crates.io's append-
only per-version JSON, the Bazel Central Registry's `metadata.json`/
`source.json` split — applied one layer deeper.

## The Verifiability Chain

```
root tag → content digest (this index's CAS)
  → observation object → platform manifest digest (physical registry)
  → OCI manifest (verified by the registry's own content-addressing)
```

Two independently verifiable digest checks compose into one chain: this
index's own content-addressing (root → observation object) and the
physical registry's own content-addressing (observation object →
manifest). Neither half is new invention — each is a standard CAS
guarantee, just chained. This chain is also the foundation a future signing
ADR builds on: a signature could target the observation-object digest
("this tag observed exactly this platform set") or the platform manifest
digests directly, without changing the graph this format already commits
to.

## Emergent Aliasing

There is no declared `aliases` field. When OCX's own push cascade writes
`3.28.1`, `3.28`, `3`, and `latest` all pointing at the same content, that
fact is entirely derivable: any two tags whose `content` digest is equal
are aliases of each other, computed at read time, never hand-maintained. A
publisher that does not cascade tags at all has nothing spurious to
populate — the format stays a passive observation ledger, not an
editorialising layer describing *why* tags relate.

## Garbage Collection

Two independent, independently scoped mechanisms:

- **Index-side (in scope here)**: render-time reachability pruning. The
  render step walks every root's `tags` map, collects every reachable
  `content` digest and, transitively, every CAS object those observation
  objects and `desc` entries reference, and emits only reachable objects
  into the deployment artifact. This prunes the deployed tree, not
  source-tree git history.
- **Registry-side (out of scope, `ocx` client concern)**: default-on
  canonical tags (`ocx package push --[no-]canonical-tag`, opt-out via
  `--no-canonical-tag`), a digest-named tag pinning a manifest against
  registry-side garbage collection — a publisher choice, not an index
  requirement, tracked as an
  [ocx#215](https://github.com/ocx-sh/ocx/issues/215) follow-up. This
  index ignores canonical tags either way (ADR-1 D8).

## `__ocx.desc`: Floating by Design

A package's title, description, keywords, readme, and logo are
package-level, editable metadata — they should not require a new manifest
push to update, and should not be tied to any one platform manifest's
immutable content. The `__ocx.desc` internal tag on the physical registry
stays floating (mutable) for exactly this reason; the bot copies its
content into this package's own CAS only when its digest changes, and
leaves `desc` untouched otherwise — no gratuitous re-copy, no diff noise on
every announce.

## See Also

- [Wire Format](../reference/wire-format) — the resulting URL shapes,
  field-by-field
- [Governance Contracts](../reference/governance-contracts) — G-13
  (why there is no separate reconcile state file — the committed root
  itself is the observation ledger)
