# ADR: Locked-Observation Index Format

<!--
Wide, wire-format-authority ADR. Companion to the 2026-07-16 design discussion;
sibling artifacts (adr_namespace_policy.md, adr_catalog_docs_colocation.md,
adr_index_bot_and_workflow_security.md, decision_log_2026-07-16.md) cover the
non-wire-format slices of the same discussion.
-->

## Metadata

**Status:** Accepted
**Date:** 2026-07-17 (decision discussion: 2026-07-16)
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** infrastructure | data | integration
**Supersedes:** [D3](./adr_public_index_registry_indirection.md#d3--entry-content-pointer--governance-not-a-metadata-mirror) of `adr_public_index_registry_indirection.md`; §2e of `design_spec_registry_indirection.md`
**Superseded By:** N/A

## Context

The original index design (`adr_public_index_registry_indirection.md` D3, 2026-07-11)
made the public index a **pointer + governance** layer only: logical name, physical
repository, owners, status. It deliberately did **not** mirror tags, versions, or any
observed registry content — resolution was defined to always hit live `tags/list`, and
the one advisory nod toward digest data (`latest_digest_hint`) was explicitly
non-authoritative, deferred pending a future signing ADR.

The 2026-07-16 design discussion expanded that scope: the public index is now one of
three surfaces that must record **locked observation data** — "the content of the index
at observation time T" — alongside `ocx.lock` (the client's dependency lock file) and
the OCX index-lock. Once the public index carries observation data at all, it inherits
a question already live for the other two surfaces and raised directly in
[ocx-sh/ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076):
multi-platform [OCI](https://opencontainers.org/) pushes are **non-atomic** — publishing
a multi-platform image is a per-platform read-modify-write cascade against the image
index, so the index digest churns mid-publish and again on every subsequent platform
addition. A lock that records an image index digest bakes that churn into every
consumer. This ADR settles the resulting lock-unit question and the full wire format
around it, and — per the linked comment — resolves ocx#215.

This ADR is the wire-format design authority for the index root, the per-package CAS
layout, and the verifiability chain built on top of it. It does not cover bot
mechanics, governance gates, or namespace policy — see `adr_index_bot_and_workflow_security.md`
and `adr_namespace_policy.md` respectively.

## Decision Drivers

- **Non-atomic multi-platform pushes** (ocx#215): platform manifests are pushed once,
  by digest, before any index rewrite — the stable primitive. Image indexes float by
  nature (platforms added, rolling tags advance) — locking their digest bakes churn
  into the lock.
- **Uniform lock doctrine**: the public index, `ocx index-lock`, and `ocx.lock` must
  all record the same thing — platform→manifest-digest pairs observed at time T — so a
  future signing/verification layer has one shape to reason about, not three.
- **OCI-isomorphism**: the index should read as "just [OCI](https://opencontainers.org/)"
  one level down — a root/pointer layer over content-addressable, immutable storage —
  so the verifiability chain maps directly onto registry mechanics already trusted
  elsewhere, instead of an OCX-invented shape.
- **Cacheability**: splitting hot/mutable (root) from cold/immutable (per-observation
  CAS objects) keeps CDN caching (ETag) maximally effective as history accumulates —
  immutable objects never need re-fetching once a client has them.
- **No convention leakage**: OCX's own push-cascade behavior (`3.28.1` → `3.28` → `3`
  → `latest`) must not become a schema concept. The wire format is a passive
  observation ledger; anything OCX-specific stays derived, not declared.
- **Reachability-bounded growth**: garbage collection at the index layer must not
  require publisher cooperation — it operates on what the root actually references.

## Industry Context & Research

**Research artifact:** [`research_sparse_index_formats.md`](./research_sparse_index_formats.md)

That research validated the broad shape already chosen in the prior ADR (pointer-only
entries, static JSON over HTTPS, conditional GET) against
[crates.io](https://doc.rust-lang.org/cargo/reference/registry-index.html), the
[Bazel Central Registry](https://bazel.build/external/registry), Homebrew, and winget,
and flagged JSR's split of immutable per-version metadata from mutable package-level
status as the closest precedent to where this decision lands. It did not, however,
cover lock-unit granularity — that question only became live once the index took on
observation data, and is resolved here from the 2026-07-16 discussion rather than desk
research.

**Key insight carried forward:** the root+CAS split this ADR adopts (D2) is the same
pointer/payload pattern the research already validated (BCR `metadata.json`/
`source.json`; crates.io's append-only per-version JSON with a single mutable
`yanked` flag), applied one layer deeper — the package root is itself a mutable
pointer over immutable per-observation CAS objects, mirroring OCI's own manifest/blob
split rather than inventing a new one.

## Considered Options

### Fork 1 — Lock unit granularity

#### Option A (chosen): platform manifest digest

| Pros | Cons |
|---|---|
| Stable primitive — manifests are pushed once, by digest, before any index rewrite | The multi-platform bundle loses a single digest a client can point at as "the whole thing, atomically" |
| Resolves the ocx#215 inconsistency directly — `ocx.lock` and dependency locking already lock manifests elsewhere | Signing (deferred ADR) must target N manifests per version instead of one index digest |
| Uniform doctrine across public index / index-lock / `ocx.lock` | |

#### Option B (rejected): image index digest

| Pros | Cons |
|---|---|
| One digest per version — simple mental model | Image indexes float by nature: per-platform read-modify-write cascades on the index churn its digest mid-publish and on every subsequent platform addition |
| Matches naive "pull by digest" intuition | Already inconsistent with `ocx.lock`/dependency locking, which lock manifests, not indexes |

### Fork 2 — Alias representation

#### Option A (chosen): emergent (no declared field)

| Pros | Cons |
|---|---|
| Schema stays a passive ledger, not an editorializing layer | Consumers must group tags by equal `content` digest themselves rather than reading a ready list |
| No leakage of OCX's own cascade-tag convention into a generic wire format | No way to declare aliases between tags that point at *different* content but are conceptually related (not needed for OCX's own cascade model) |
| Zero bookkeeping — always correct because it is derived, never hand-maintained | |

#### Option B (rejected): declared `aliases` field

| Pros | Cons |
|---|---|
| Explicit — no client-side computation | Bakes OCX's push-cascade semantics into the wire schema |
| | Dual-write risk: must stay in sync with `tags`, the exact staleness problem the prior ADR's D3 already argued against |
| | A publisher not using cascade tags has nothing meaningful to put there |

### Fork 3 — Per-package storage shape

#### Option A (chosen): root (mutable) + package-local CAS (immutable) split

| Pros | Cons |
|---|---|
| Hot root stays tiny and cheap to re-fetch regardless of how much observation history accumulates | More files per package — CAS fan-out into `o/sha256/<hex>.json` |
| Immutable CAS objects are permanently cacheable, same shape as OCI's own manifest/blob split | More moving parts in the render pipeline (reachability-filtered copy step) |
| Dedup is automatic — two tags with identical platform sets share one CAS object | Requires explicit GC discipline (orphaned CAS objects need pruning) |

#### Option B (rejected): single monolithic per-package JSON

| Pros | Cons |
|---|---|
| One file per package, simplest possible render step | No immutable/cacheable split — every observation ever made lives in one ever-growing, ever-rewritten file |
| No CAS fan-out, no reachability pruning needed | Loses automatic content dedup — would need an internal aliasing scheme (re-introduces Fork 2's rejected problem, just scoped inside one file) |
| | Nothing to attach a future per-observation signature to except the whole file |

### Fork 4 — Canonical tags

#### Option A (chosen): ocx-side `--[no-]canonical-tag` push flag, default ON

| Pros | Cons |
|---|---|
| Every publish gets the GC-pinning guarantee without an opt-in step — the common case is the safe case | Adds a tag per pushed platform manifest even for publishers who never needed the guarantee, unless they pass `--no-canonical-tag` |
| The realistic failure modes (index push dropping an existing platform entry, build-tag overwrite, naive retention tooling) are publisher bugs or convention violations, not systemic risk — the flag is a cheap safety net, not a load-bearing contract | |
| Reconcile already detects dangling/mutated digests independently of canonical tags | |
| Opt-out (`--no-canonical-tag`) still exists for publishers who want to skip it | |

Revises the original opt-in default: `ocx#215`'s 2026-07-17 follow-up decision flipped the
ocx-side flag to default-on with an explicit `--no-canonical-tag` opt-out — a pure
registry-side deletion safety net that costs nothing for this index to remain agnostic
to (see D8).

#### Option B (rejected): canonical tags as an ecosystem-wide requirement

| Pros | Cons |
|---|---|
| Uniform protection against registry-side GC across all publishers | Shifts operational burden onto every publisher for a rare failure mode |
| No opt-in gap | Doubles the tag surface per pushed manifest |
| | Not enforceable by the index — a requirement the index cannot verify isn't a real contract |

## Decision Outcome

**Chosen:** platform-manifest-digest locking (Fork 1A), emergent aliasing (Fork 2A),
root+CAS storage split (Fork 3A), default-on canonical tags with opt-out (Fork 4A) —
elaborated as D1–D10 below.

**Rationale:** all four choices share one throughline — push complexity and
convention-specific behavior to the edges (ocx-side opt-in flags, derived/client-side
computation) and keep the wire format itself a minimal, generic, OCI-isomorphic
observation ledger. Every rejected option would have baked either registry churn
(Fork 1B), an OCX-specific convention (Fork 2B), a scaling liability (Fork 3B), or an
unenforceable requirement (Fork 4B) directly into the schema.

## Decisions

### D1 — Lock unit: platform manifest digest, never image index digest

A lock — the public index, `ocx index-lock`, and `ocx.lock` alike — records the
**content** of an image index at observation time: the set of `platform → manifest
digest` pairs, never the index digest itself. This is the uniform doctrine across all
three surfaces: each records "content of the index at observation time T." Platform
manifests are pushed once, by digest, before any index rewrite — the stable primitive.
Image indexes float by nature (platforms added, rolling tags advance) — locking their
digest would bake that churn into the lock. This resolves the inconsistency named in
[ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076): dependency
locking already locks manifests; index-digest locking migrates to the same unit.

### D2 — Layout: OCI-isomorphic root + CAS

```
/config.json                                  ← format_version only
/p/<ns>/<pkg>.json                            ← package root (hot, mutable)
/p/<ns>/<pkg>/o/sha256/<hex>.json             ← observation objects (immutable, package-local CAS)
/p/<ns>/<pkg>/o/sha256/<hex>.{md,svg,png}     ← desc blobs (immutable, package-local CAS)
```

`/data/catalog/**` and `/`, `/docs/**` are **not** wire contract — catalog data and the
VitePress site are covered by `adr_catalog_docs_colocation.md` and are free to evolve
independent of `format_version`.

CAS paths encode a digest by substituting `:` for `/` in its OCI-style string form —
the same convention OCI registries themselves use for blob storage (`sha256:<hex>` ↔
`sha256/<hex>`). Every `content` reference in the root (D2 below) and every
`digest` reference inside an observation object (D4) is an OCI-style `sha256:<hex>`
string; the corresponding CAS file is the same digest with `:` replaced by `/`.

**Root fields** (`/p/<ns>/<pkg>.json`):

| Field | Type | Governed by | Notes |
|---|---|---|---|
| `name` | string | human (PR) | logical name, e.g. `ocx.sh/kitware/cmake` |
| `repository` | string | human (PR) | `oci://<host>/<repo>`; host validated against an allowlist (mechanics: `adr_index_bot_and_workflow_security.md`) |
| `owners` | array of `{github, github_id}` | human (PR) | `github_id` **mandatory** (refines the design_spec §2e draft, where it was optional) — survives GitHub username rename/recycling |
| `status` | enum `active \| deprecated \| yanked` | human (PR) | |
| `deprecated_message` | string \| null | human (PR) | |
| `created` | string (date) | human (PR), set once | |
| `upstream` | `{org, repository_url?, disclaimer?}` | human (PR) | attribution of the upstream project the package mirrors, distinct from the namespace owner; feeds the catalog's upstream-disclaimer badge |
| `superseded_by` | string \| null | human (PR) | optional; bare `<namespace>/<package>` naming a successor package, ≤140 chars; omitted or `null` when unset — **added 2026-07-17** by [`adr_enumeration_index.md`](./adr_enumeration_index.md) D7, not part of this ADR's original decision |
| `desc` | `{digest, title, description, keywords[], readme?, logo?}` \| null | bot-regenerated | nullable — see D6 |
| `tags` | map: tag name → `{content, observed, yanked?}` | bot-regenerated, except `yanked` (human, PR) | **every** observed tag, no filtering — see below _(provenance amended 2026-07-18 → [`adr_fork_pr_announce.md`](./adr_fork_pr_announce.md) FP-2; note below)_ |

`tags` is a map from every tag ever observed on the physical repository to:

```json
{
  "content": "sha256:<hex of the observation object>",
  "observed": "2026-07-17T00:00:00Z",
  "yanked": { "reason": "string", "at": "2026-07-17T00:00:00Z" }
}
```

`content` addresses **this index's own package-local CAS** (an observation object,
D4) — it is not an OCI manifest or image-index digest. `yanked` is optional; its
presence marks the row yanked (D2 continues in D9's yank semantics below). No
`aliases` field exists anywhere in this schema — see D3.

> **Amendment (2026-07-18, [`adr_fork_pr_announce.md`](./adr_fork_pr_announce.md)
> FP-2):** the **wire shape above is unchanged** — the `tags` map, its row shape
> (`{content, observed, yanked?}`), the observation-object layout (D4), and the D5
> verifiability chain are all byte-identical. Only the *provenance* of the tag set
> changes: it is now the **owner-curated set** announced through a fork PR, no longer
> the full "every observed tag" enumeration. Each present row is still content-verified
> against registry truth; only set *membership* is owner-decided. Yank (a grace marker
> that survives, D9) and delete (owner drops the row) become distinct operations under
> curation. This is a provenance/transport change, not a `format_version` break, and is
> invisible to a resolving client.

Example root, `/p/kitware/cmake.json`:

```json
{
  "name": "ocx.sh/kitware/cmake",
  "repository": "oci://ghcr.io/ocx-contrib/cmake",
  "owners": [{ "github": "alice", "github_id": 123456 }],
  "status": "active",
  "deprecated_message": null,
  "created": "2026-07-17",
  "upstream": {
    "org": "Kitware",
    "repository_url": "https://github.com/Kitware/CMake",
    "disclaimer": null
  },
  "desc": {
    "digest": "sha256:9f2c...",
    "title": "CMake",
    "description": "Cross-platform build system generator.",
    "keywords": ["build", "cmake", "cpp"],
    "readme": "sha256:1a2b...",
    "logo": "sha256:3c4d..."
  },
  "tags": {
    "3.28.1": { "content": "sha256:aaaa...", "observed": "2026-07-17T00:00:00Z" },
    "3.28":   { "content": "sha256:aaaa...", "observed": "2026-07-17T00:00:00Z" },
    "3":      { "content": "sha256:aaaa...", "observed": "2026-07-17T00:00:00Z" },
    "latest": { "content": "sha256:aaaa...", "observed": "2026-07-17T00:00:00Z" }
  }
}
```

Here `3.28.1`, `3.28`, `3`, and `latest` all share `content: sha256:aaaa...` — they are
aliases of each other purely because a cascade push wrote identical platform sets under
every tag (D3).

### D3 — Aliasing is emergent

There is no declared `aliases` field. Two tags are aliases of each other exactly when
their `content` digests are equal — a read-time computation over the `tags` map, never
hand-maintained data. This keeps OCX's own push-cascade convention (`3.28.1` → `3.28`
→ `3` → `latest`, all pointing at the same content) entirely out of the schema: the
wire format is a generic passive ledger of what was observed, not an editorializing
layer describing why. A future non-cascading publisher has nothing spurious to
populate.

### D4 — Observation objects

`/p/<ns>/<pkg>/o/sha256/<hex>.json` — immutable, package-local CAS:

```json
{
  "platforms": [
    { "platform": { "architecture": "amd64", "os": "linux" },   "digest": "sha256:1111..." },
    { "platform": { "architecture": "arm64", "os": "linux" },   "digest": "sha256:2222..." },
    { "platform": { "architecture": "amd64", "os": "windows" }, "digest": "sha256:3333..." }
  ]
}
```

Each `platform` object is an inline subset of the [OCI image-spec `Platform`
object](https://github.com/opencontainers/image-spec/blob/main/image-index.md):
`architecture`, `os`, `os.version`, `os.features`, `variant`, `features`. The exact
JSON Schema for this subset lives in `schema/observation-object.schema.json` (Phase 1,
WP1-A) — this ADR fixes the field set, not the schema syntax. Each `platforms[].digest`
is the OCI manifest digest for that platform on the physical registry — a different
digest namespace from the root's `tags[].content`, which addresses this index's own
CAS (see D2, D5).

`schema/observation-object.schema.json`'s `platform` definition sets
`additionalProperties: false`, so this field set tracks the OCI image-spec's `Platform`
object in lockstep: if a future image-spec revision extends or un-reserves the field
set, this schema must bump in the same change, or newly-observed manifests carrying the
new field start failing schema validation.

Observation objects carry **no timestamps** — deliberately, for maximum dedup. Two
observations that see an identical platform→digest set produce byte-identical JSON,
hence the identical `sha256` digest, hence automatic storage as one object regardless
of how many tags, packages, or points in time observed it. Objects are immutable: an
observed platform-set change is never an edit to an existing object — it is a new
object at a new digest, and the affected root's `tags[tag].content` is repointed to it.
The `observed` timestamp lives at the mutable root layer (D2) precisely so this object
layer can stay timestamp-free and fully dedupable.

### D5 — Verifiability chain

```
root: tags[tag].content (sha256:<hex>, this index's CAS)
  → GET /p/<ns>/<pkg>/o/sha256/<hex>.json
  → verify received bytes hash to <hex>              (index-CAS integrity)
  → object.platforms[].digest (sha256:<hex>, OCI manifest, physical registry)
  → GET manifest from the physical repository at that digest
  → verify OCI CAS                                    (registry-CAS integrity, standard OCI guarantee)
```

Two independently verifiable digest checks compose into one chain: this index's own
content-addressing (root → observation object) and the physical registry's own
content-addressing (observation object → manifest). This chain is the foundation a
future signing ADR builds on — signing could target the observation-object digest
("this tag observed exactly this platform set") or each platform manifest digest
directly (ocx#215's signing note: "with manifest-unit locking, signing targets platform
manifests"). This ADR fixes the graph a signature would attach to; the signature scheme
itself stays deferred.

### D6 — `desc`: floating source, locked-on-change copy

The `__ocx.desc` internal tag on the physical registry stays **floating (mutable) by
design** — it is not retired, and it is not itself locked/observed the way package
tags are, because it carries metadata about the package, not a distributable artifact.
The bot compares the currently observed `__ocx.desc` digest against the last-copied
`desc.digest` in the committed root; on change, it copies title, description, the
`sh.ocx.keywords` annotation, and the readme/logo layers into this package's CAS
(`o/sha256/<hex>.md`, `.svg`, or `.png`) and updates `desc.digest` plus the `readme`/
`logo` CAS pointers. On no change, `desc` is left untouched — no gratuitous re-copy, no
bot diff noise on every announce. `desc` is nullable at the root: a package that has
never published `__ocx.desc` has `desc: null`; the catalog degrades gracefully
(`keywords` renders `[]`, per plan risk 6).

### D7 — `config.json` minimalism

```json
{ "format_version": 1 }
```

Nothing else. The root+CAS layout (D2) is a fixed path convention, not a
runtime-discoverable one — a client that understands `format_version: 1` already
knows the full path grammar without a URL template to parse, so there is no
`packages` prefix and no free-text `note` field (see D10 for the delta against the
current placeholder). The field is named `format_version`, not `version`: `version`
is domain-overloaded in a package index — every entry already has package versions —
so naming the schema-generation counter `version` invites exactly the ambiguity a
client parser would otherwise have to disambiguate by context. `format_version`
follows the [OCI Image Manifest's `schemaVersion`](https://github.com/opencontainers/image-spec/blob/main/manifest.md)
and [Terraform](https://developer.hashicorp.com/terraform)'s provider/state
`version`-vs-`terraform_version` split as precedent for keeping a format-generation
counter lexically distinct from any data-level version concept.

### D8 — Garbage collection: two independent, independently scoped mechanisms

**Index-side (this repo, in scope): render-time reachability pruning.** The render
step (`core/render`, WP2-F) walks every root's `tags` map, collects the reachable
`content` digests and, transitively, every CAS object those observation objects and
`desc` entries reference, and rehydrates the render output with only reachable CAS
objects. Objects orphaned by a repointed or yanked tag are pruning candidates at
render time. This prunes the **deployment artifact**, not source-tree git history —
orphaned CAS blobs accumulating in git history are a tracked, accepted risk (source-tree
GC is future work, README-noted only).

**Registry-side (`ghcr.io`, out of scope — ocx repo concern): canonical tags.** A
canonical tag is a digest-named tag (`sha256.<hex>`) pointing at exactly the manifest
its name encodes, pinning that manifest against registry-side GC (the realistic
failure case is naive untagged-child cleanup, not a scenario [GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
implements today per `research_ghcr_constraints.md`). This is **not** required by this
wire format or by this index's governance — this index ignores canonical tags either
way (it reads the physical registry's manifest digests directly, D5). It is a pure
registry-side deletion safety net implemented as an `ocx package push
--[no-]canonical-tag` flag, default ON with an explicit opt-out (revised 2026-07-17
from the original opt-in default), tracked as an ocx#215 follow-up in the plan's Out of
Scope section, not an index-repo deliverable.

### D9 — G-13 registry-state file eliminated

The prior design (`design_spec_registry_indirection.md`, G-13 amended) required
reconcile to maintain a separate bot-committed `state/observed-digests.json` — a
per-entry, per-tag last-seen-digest side channel used purely to detect anomalies
(digest change on an already-observed tag). Under the locked-observation format, the
committed root's `tags` map already records `content` (the observation-object digest)
per tag with an `observed` timestamp. Reconcile can diff the current root against the
previously committed root directly — no separate state artifact is needed anywhere in
this repository. **The committed root IS the observation ledger.** Anomaly-detection
mechanics that consume this diff (what counts as a hard-stop anomaly vs. first-sight)
are owned by `adr_index_bot_and_workflow_security.md`; this ADR only fixes the wire-format
consequence — no `/state/` artifact exists.

### D10 — Wire deltas vs. the current live placeholder

Two deltas relative to the deployed `public/config.json` placeholder and the
`design_spec_registry_indirection.md` §2e draft, both allowed pre-client-ship (no
`ocx` client has ever fetched against either):

- `config.json` drops the placeholder's `packages` (path prefix) and `note` fields —
  see D7.
- `/p/<ns>/<pkg>.json` changes from a flat single-file pointer (§2e's `IndexEntry`,
  which had no observation data at all) to the root+CAS split in D2.

The one-way-door constraint in `product-context.md` begins to bind at the first real
`ocx` client release against this endpoint — that has not happened yet, so this
transition costs nothing today. `format_version` remains the mechanism for any future
breaking change once it does.

Expanding into `/p/<ns>/<pkg>/o/...` also introduces new reserved path segments at the
namespace level (`p`, `o`, and the rest of the control-path/brand/generic reserved
list). The authoritative reserved-segment list, and the routing-collision rationale
behind it, is owned by [`adr_namespace_policy.md`](./adr_namespace_policy.md) — not
duplicated here.

## Consequences

**Positive:**
- Uniform lock doctrine across the public index, `ocx index-lock`, and `ocx.lock`
  resolves the ocx#215 inconsistency at its source, not just locally to this repo.
- The root+CAS split gives the index the same cacheability properties OCI itself
  relies on — CDN caching stays maximally effective as observation history grows,
  since immutable objects never need re-fetching by a client that already has them.
- The verifiability chain (D5) gives a concrete graph for a future signing ADR to
  attach to without committing to a signature scheme now.
- Emergent aliasing (D3) keeps the schema generic — no OCX-specific convention baked
  into a format other tooling might also want to read.

**Negative:**
- More files per package than the flat single-pointer design it replaces — CAS fan-out
  grows both the render pipeline's surface (reachability walk, orphan pruning) and the
  deployed file count.
- Requires ongoing GC discipline (D8) rather than "overwrite the one file."

**Risks:**
- Orphaned CAS blobs accumulating in source-tree git history over time — mitigated at
  the deployment artifact by render-time reachability pruning (D8); source-tree GC is
  deferred, tracked only as a README note.
- `desc.keywords` sourced from the `sh.ocx.keywords` annotation; packages that never
  publish it render `keywords: []` — the catalog's search/filter UI must degrade
  gracefully rather than treat an empty list as an error.

## Links

- [ocx-sh/ocx#215 (design-discussion comment, resolves this issue)](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076)
- [`research_sparse_index_formats.md`](./research_sparse_index_formats.md)
- [`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md) — D3 superseded by this ADR
- `design_spec_registry_indirection.md` §2e — superseded by this ADR
- [`adr_namespace_policy.md`](./adr_namespace_policy.md) — namespace charset, reserved-segment list, `github_id` mandatory rationale
- [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md) — how the catalog UI consumes CAS URLs (`/p/<ns>/<pkg>/o/sha256/<hex>.<ext>`) for readme/logo rendering
- [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md) — bot mechanics that produce this format (observe/regenerate/diff/anomaly), G-01…G-18 carry-forward
- [`decision_log_2026-07-16.md`](./decision_log_2026-07-16.md) — narrative of the 2026-07-16 discussion this ADR formalizes
- [`.claude/state/plans/plan_index_v1.md`](../state/plans/plan_index_v1.md) — Wire Format section, Phase 0/1 execution plan
- [OCI Image and Distribution Specs](https://opencontainers.org/) — image-index/manifest digest semantics, `Platform` object, `schemaVersion` precedent
- [GitHub Container Registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) — GC/retention behavior referenced in D8

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Michael Herwig + Claude design swarm | Initial record from the 2026-07-16 design discussion; supersedes D3 of `adr_public_index_registry_indirection.md` and §2e of `design_spec_registry_indirection.md` |
| 2026-07-17 | Michael Herwig + Claude design swarm | Amendment: D2's root-field table gains `superseded_by` (optional, human-governed), added by `adr_enumeration_index.md` D7 |
| 2026-07-17 | Michael Herwig + Claude design swarm | Amendment: Fork 4/D8 canonical-tag stance revised — ocx-side `--canonical-tag` push flag flips from opt-in to default-on with `--no-canonical-tag` opt-out (ocx#215 follow-up); no change to this index's own posture, which ignores canonical tags either way |
| 2026-07-17 | Michael Herwig + Claude design swarm | Amendment: D4 gains a sentence noting `schema/observation-object.schema.json`'s `platform` definition's `additionalProperties: false` tracks the OCI image-spec `Platform` field set in lockstep |
| 2026-07-18 | Michael Herwig + Claude design swarm | Amendment: D2's `tags` provenance flips "every observed tag" → "every announced tag" (owner-curated), per `adr_fork_pr_announce.md` (ADR-6) FP-2 — wire shape, row shape, D4 observation objects, and the D5 chain all unchanged; provenance/transport change only, not a `format_version` break |
