---
title: Architecture
---

# Architecture

Why the index locks what it locks, and what "locked" means in practice.
Design authority:
[`adr_locked_observation_index_format.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_locked_observation_index_format.md)
(root + CAS split, why this shape rather than one file per package) and, for
the `o/` object itself,
[`adr_oci_index_only_dispatch.md`](https://github.com/ocx-sh/ocx/blob/main/.claude/artifacts/adr_oci_index_only_dispatch.md)
(the superseding authority for what `o/` holds).

## The Problem: Tags Float, Indices Get Superseded

An index is a **catalog of OCI artifacts**. That is the whole of it. OCI
tags are floating pointers by definition — a tag is a name a registry may
repoint at any time — and this index's entire job is to **lock one**: to
record what a floating pointer resolved to at a specific point in time, so
a version choice made later resolves to the same artifact.

Publishing a multi-platform OCI image is a per-platform read-modify-write
cascade against an image index: each platform's manifest is pushed, then
the index is rewritten to include it. The index digest churns mid-publish,
and churns again on every subsequent platform addition — named directly in
[ocx-sh/ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076).
Once a later platform push supersedes an index, nothing on the registry
points at the *previous* one any more, and it becomes eligible for the
registry's own garbage collection — in the ordinary course of correct
publishing, not as an error case.

That churn is exactly the reason to snapshot the index, not a reason to
avoid it. A tag observed at time T resolved to one specific index; if that
index later disappears once superseded, a client resolving that tag
afterward has nothing left to fetch unless something recorded, at
observation time, a durable copy of what the tag pointed at.

## Why the Index Is Copied, Not the Platform Manifest

It follows from the Problem above that this index defines no object shapes
of its own — shape definition belongs to the OCI image spec, and an index
that invented its own shape would be taking on a responsibility that isn't
its. Measured against that, `o/` is plain content-addressable storage
holding the OCI image indices the observed tags referenced, byte-for-byte
as the registry served them. `tags[].content` is the digest of one of them.

Why the index and not the platform manifest underneath it: a manifest is
one package for one platform, and its content cannot change without
becoming a different package — a manifest digest is stable *by identity*,
so a later fetch by digest is hermetic. A manifest can still disappear, but
only once *nothing* references it, and keeping it referenced (any tag, any
index that still lists it) is the registry operator's and the publisher's
concern, not something this index owns or can observe.

An image index has neither property. It is a collection over platforms:
adding a platform produces a new index at a new digest, and the tag moves
to it — the previous index is then referenced by nothing and becomes
GC-eligible, in the ordinary course of correct publishing (exactly the
mechanism [ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076)
named). So the index snapshots exactly the thing that can disappear in the
ordinary course of publishing, and only that — making the public index,
`ocx index-lock`, and `ocx.lock` consistent in what each locks at its own
layer: image indices lock as indices here; platform manifests, once
resolved from one, lock as manifests one layer down. Neither layer inverts
the other's locking unit.

## Why Root + CAS, Not One File Per Package

An earlier sketch of this format used one small JSON file per package,
holding both mutable pointer state and every tag's observed history
together. That does not survive contact with per-tag data: a single file
would grow with every tag ever observed and rewrite its entire contents on
every commit, defeating CDN caching for content that rarely actually
changes.

Splitting the two apart — a tiny, forever-small mutable **root**
(`/p/<namespace>/<package>.json`) pointing at immutable, content-addressed
**OCI image indices** (`/p/<namespace>/<package>/o/sha256/<hex>.json`) —
mirrors OCI's own manifest/blob split rather than inventing a new pattern.
The root stays cheap to re-fetch regardless of how much history
accumulates; CAS objects are permanently cacheable and automatically
deduplicated whenever two tags resolve to the same image index — the
registry's own bytes are byte-identical, so they hash to the same digest
whether one announce observed them or many. This is the same pointer/payload
shape the sparse-index research surveyed elsewhere — crates.io's append-
only per-version JSON, the Bazel Central Registry's `metadata.json`/
`source.json` split — applied one layer deeper.

## The Verifiability Chain

```
root tag → content digest (this index's CAS, an image-index digest)
  → OCI image index (verbatim) → manifests[].digest (physical registry)
  → OCI manifest (verified by the registry's own content-addressing)
```

Two independently verifiable digest checks compose into one chain: this
index's own content-addressing (root → image index) and the physical
registry's own content-addressing (image index → manifest). Neither half is
new invention — each is a standard CAS guarantee, just chained, and the
image index carries a second anchor beyond its filename: the physical
registry SHOULD still serve byte-identical content for that same digest.
This chain is also the foundation a future signing ADR builds on: a
signature could target the image-index digest ("this tag resolved to
exactly this index") or the platform manifest digests directly, without
changing the graph this format already commits to.

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
  `content` digest and, transitively, every CAS object those image indices
  and `desc` entries reference, and emits only reachable objects into the
  deployment artifact. This prunes the deployed tree, not source-tree git
  history.
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
