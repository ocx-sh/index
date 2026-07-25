# ADR: Sparse Enumeration Index (`/c/index.json`)

## Metadata

**Status:** Accepted
**Date:** 2026-07-17
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** infrastructure | data | integration
**Resolves:** the `all.json` search-snapshot half of the deferred item in
[`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md#deferred--out-of-scope-each-needs-its-own-adr-or-spec-before-public-launch)
("`all.json` search snapshot + website search") and the corresponding Non-Goals
bullet in [`product-context.md`](../rules/product-context.md) ("Not a search service
(`all.json` snapshot deferred)")
**Supersedes:** N/A
**Superseded By:** [`adr_oci_index_only_dispatch.md`](https://github.com/ocx-sh/ocx/blob/main/.claude/artifacts/adr_oci_index_only_dispatch.md)
(`ocx-sh/ocx`, 2026-07-25) — partially: retires the "observation object" vocabulary
D4 and D8 use to describe the CAS dedup category and the site's render input (deleted,
replaced by a verbatim OCI image index); no D-decision of this ADR (the enumeration
snapshot, its digest semantics, the surface-role table's structure) is reversed. See
the amendment note appended below.

## Context

The wire tree (`/config.json`, `/p/<namespace>/<package>.json`,
`/p/<namespace>/<package>/o/sha256/<hex>.json`) is deliberately sparse: a client that
already knows a logical name can resolve it in one request, but nothing in the wire
contract lets a client, a future corporate mirror, or a marketplace discover the full
set of published packages. The only existing full listing,
`/data/catalog/packages.json`, is explicitly non-contract
([`product-context.md`](../rules/product-context.md): "`/data/catalog/**`... are not
wire contract") and metadata-heavy — title, description, keywords, tag count, CAS
URLs for logo/readme, one row per package. That is the right shape for a browse/search
UI and the wrong shape for a machine consumer that only wants "what exists, and has
anything changed."

This gap was named and deliberately deferred at the very first design pass
([`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md),
Deferred / Out of Scope: "`all.json` search snapshot + website search") and carried
forward into `product-context.md`'s Non-Goals ("Not a search service (`all.json`
snapshot deferred)"). The 2026-07-17 design discussion — narrated in
[`decision_log_2026-07-17.md`](./decision_log_2026-07-17.md) — resolved the
enumeration half of that deferred item as a new frozen wire surface, researched
against prior art in
[`research_index_enumeration_prior_art.md`](./research_index_enumeration_prior_art.md).
The other half, ranked/faceted **search**, remains genuinely deferred and out of
scope here: the surface this ADR adds carries no metadata to search over (D2), by
design.

The same discussion also surfaced a smaller, related gap: `status: deprecated` +
`deprecated_message` already let a human write "superseded by X," but nothing let a
package name its successor in a machine-readable form an `ocx` client could act on at
install time. This ADR settles both: the enumeration surface (D1–D6, D9) and the new
`superseded_by` root field (D7), plus the resulting surface-role boundary across the
index's growing set of top-level paths (D8).

## Decision Drivers

- **Never repeat the Helm `index.yaml` failure**: the enumeration surface carries
  names and content digests, never metadata — research finding 3 is the one lesson
  treated as non-negotiable.
- **Reuse the root+CAS philosophy this repo already committed to**, one layer up:
  [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)'s
  root/CAS split already gives a hot, cheap-to-refetch pointer over immutable,
  content-addressed payloads; the enumeration surface is the same shape applied to
  the whole catalog instead of one package.
- **Additive under the wire-contract one-way door**: a new frozen surface and a new
  optional root field, neither of which changes any existing published shape or
  requires a `format_version` bump.
- **Keep the surface-role boundary crisp**, not blurred: `product-context.md` and
  [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md) already draw a
  line between wire contract and site view-model; adding a fourth wire surface is the
  moment to write that boundary down explicitly rather than let it stay implicit.
- **Decide the digest question now, not later**: array-to-map is itself a breaking
  shape change on a frozen surface, and `/c/index.json` is brand new — there is no
  "ship the simple version, upgrade later for free" option here, unlike an
  already-shipped field.

## Industry Context & Research

**Research artifact:** [`research_index_enumeration_prior_art.md`](./research_index_enumeration_prior_art.md)

That research found flat, name-only enumeration files proven at ecosystem scale
([PyPI `/simple/`](https://peps.python.org/pep-0691/), ~800,000 projects), a stark
counter-example in inlined-metadata listings that stopped scaling and were abandoned
([Helm `index.yaml`](https://helm.sh/docs/topics/chart_repository/)), and — the
decision this ADR actually turns on — strong precedent for a **digest-manifest** root
file over content-addressed leaves in both
[TUF's snapshot role (PEP 458)](https://peps.python.org/pep-0458/) and
[RPM's `repomd.xml`](https://github.com/rpm-software-management/createrepo_c),
independently convergent designs in two unrelated ecosystems. It also found, across
every system surveyed, zero precedent for a listing whose shape switches
conditionally on scale (inline below a threshold, sharded/pointer above it) — every
system studied commits to one shape permanently.

**Key insight carried forward:** a digest map is not a bare list with extra bytes
attached — it gives the enumeration surface a second, independent property (Merkle
upward propagation: one conditional GET at the root answers "has anything changed
anywhere?") that a name-only list cannot provide without a client separately polling
every leaf resource.

## Considered Options

### Fork 1 — Enumeration entry shape

#### Option A (rejected, superseded by C): flat name-only array

| Pros | Cons |
|---|---|
| Simplest possible shape; directly proven at PyPI's ~800,000-project scale | Answers "what exists" but not "did anything change" — a consumer still has to poll every `/p/**` root individually to detect drift |
| Smallest possible payload per entry | No foundation for a future signing ADR beyond "sign the list of names" |

#### Option B (rejected outright): size-conditional discriminated union (inline list below a threshold, sharded pointer-list above it)

| Pros | Cons |
|---|---|
| Defers the sharding-shape decision until scale actually forces it | **No precedent anywhere in the research** — TUF and `repomd.xml` are always-pointer; PyPI and Homebrew are always-inline; no surveyed system straddles both |
| | A client parsing this wire surface must carry two code paths forever, each exercised only some of the time — the same dual-mechanism risk class that has caused real inconsistency bugs in other conditional-fallback designs (e.g. OCI's own Referrers API tag-fallback mechanism for registries without native support) |
| | Introduces a threshold value with no principled basis at this project's current scale |

#### Option C (chosen): digest map — `<namespace>/<package>` → `sha256:<hex>` of the exact bytes served at that package's root

| Pros | Cons |
|---|---|
| Merkle-style upward propagation: one conditional GET on `/c/index.json` answers "has anything changed anywhere," full stop | Slightly larger per-entry payload than a bare name (a full digest string per package) |
| Strong precedent in two independently-convergent ecosystems (TUF snapshot role, RPM `repomd.xml`) | The array-to-map question must be settled now — deferring it past this ADR would itself be a breaking shape change later |
| ETag + digest-diff sync protocol falls out for free: 304 means fully current; 200 means diff the map, fetch only changed roots | |
| Gives the deferred signing ADR a foundation at zero extra design cost: sign one root file, the whole tree becomes tamper-evident via the digest chain | |

### Fork 2 — Sharding strategy

#### Option A (chosen): reserve, do not build

| Pros | Cons |
|---|---|
| `p/` is empty today (Phase 4 seed data has not landed); building sharding machinery for a catalog with zero entries is pure speculation | None identified — this is the same "don't build ahead of the trigger" posture `research_sparse_index_formats.md` already recommended for `/p/`'s own git-tree sharding |
| Two precedented, additive paths stay open when the trigger does arrive: a recursive `indices` pointer map (child index digest referenced from the parent, same Merkle principle one level deeper) or crates.io-style prefix shards under `/c/` | |
| Gated cleanly by `format_version` or additive sibling paths — no compatibility cost paid today | |

#### Option B (rejected): build sharding now

| Pros | Cons |
|---|---|
| No future migration needed if scale ever demands it | Solves a problem this project does not have — research puts the scale where PyPI needed 16,384 hash bins several orders of magnitude past any package count this project currently plans for |
| | Adds render-pipeline and validation complexity for a `p/` tree that is, as of this ADR, empty |

### Fork 3 — `superseded_by` field representation

#### Option A (chosen): optional string field, omitted when unset

| Pros | Cons |
|---|---|
| Mirrors `upstream`'s existing, proven precedent for a non-universal additive field — the overwhelming majority of packages will never set this | Requires reusing the existing package-id parser rather than inventing new validation from scratch (a discipline cost, not a real con) |
| No noise added to the majority of fixtures/roots that are not superseded | |
| Machine-readable — an `ocx` client can act on it at install time, unlike free text | |

#### Option B (rejected): required-nullable field, matching the original D2 field cohort (e.g. `deprecated_message`)

| Pros | Cons |
|---|---|
| Uniform shape with the original required-nullable fields | Every existing and future root would carry an explicit `null` for a field that will almost never be set — pure noise for the common case |
| | No precedent needed — `upstream` already established the omit-when-absent pattern for exactly this kind of non-universal additive field |

#### Option C (rejected): free-text convention inside `deprecated_message`, no new field

| Pros | Cons |
|---|---|
| Zero wire-format change | Not machine-readable — an `ocx` client cannot hint at install time without parsing prose |
| | Couples the successor pointer to deprecation status, when the two are independent concepts (a package can name a successor while still `active`) |

## Decision Outcome

**Chosen:** digest-map enumeration shape (Fork 1C), sharding reserved not built
(Fork 2A), optional `superseded_by` field (Fork 3A) — elaborated as D1–D9 below.

**Rationale:** every rejected option either reintroduces a scaling failure this
project has direct precedent to avoid (Helm's inlined metadata, if `/c/index.json`
ever carried more than names and digests), invents a mechanism with no industry
precedent at all (the conditional discriminated union), or solves a problem this
project does not yet have (sharding for an empty `p/` tree). The throughline across
all decisions here is the same one `adr_locked_observation_index_format.md` already
established for the per-package root+CAS split: keep the hot, frequently-polled
surface tiny and digest-verifiable, push everything speculative to a reserved,
gated, later evolution.

## Decisions

### D1 — `/c/index.json`: the fourth frozen wire shape

`/c/index.json` joins `/config.json`, `/p/<namespace>/<package>.json`, and
`/p/<namespace>/<package>/o/sha256/<hex>.json` as the fourth frozen wire shape — a
full-catalog enumeration surface. This resolves the `all.json` search-snapshot item
deferred at the original design pass
([`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md),
Deferred / Out of Scope) and the corresponding Non-Goals bullet in
[`product-context.md`](../rules/product-context.md). The surface is deliberately
narrower than the original `all.json` idea: it enumerates and fingerprints, it does
not search — `ocx search`, ranked lookup, and any faceted/keyword search stay
unchanged as a non-goal, since the surface this ADR adds carries no metadata to
search over (D2).

### D2 — Shape

```json
{
  "format_version": 1,
  "packages": {
    "astral-sh/uv": "sha256:<hex>",
    "kitware/cmake": "sha256:<hex>"
  }
}
```

A top-level object, not a bare array — the same additive-headroom reasoning
`config.json` already applies by being an object rather than a bare integer: a future
sibling key (for example, Fork 2's reserved `indices` pointer map) can land
additively without a shape change. `packages` is a map, sorted by key — the render
pipeline already produces packages in sorted order for every other output tree, so
this falls out of existing iteration order rather than requiring a new sort step.
Names only, digests only, **never metadata** — the one rule the research draws
hardest from the Helm failure mode. Serialization matches `config.json`'s existing
style (`json.dumps(..., indent=2)` plus a trailing newline) — the exact served bytes,
not the compact canonical form `bot/CONTRACTS.md` §1 mandates for CAS digest inputs
(see D4 for why these are deliberately different serializations for different
purposes).

### D3 — Map key: bare `<namespace>/<package>`, never the `ocx.sh/` prefix

The `packages` map's keys are the bare `<namespace>/<package>` id — no `ocx.sh/`
prefix. A client derives the corresponding root path by concatenation:
`/p/<key>.json`. This mirrors the pointer-form convention
[`adr_namespace_policy.md`](./adr_namespace_policy.md) already established for
cross-references between entries (ND-2/ND-3's package-id shape, and `superseded_by`'s
own value form, D7 below): the `ocx.sh/` prefix belongs only to a root's own `name`
field — the entry's self-identifying form — never to path or pointer material
anywhere else in the wire format.

### D4 — Digest semantics: a new digest category, distinct from CAS digests

Each `packages[key]` value is `sha256:` followed by lowercase hex, computed over the
**exact bytes served** at `/p/<namespace>/<package>.json` — the render pipeline's
already-assembled root bytes, not a re-serialization of the parsed content. This is a
new digest category, deliberately distinct from the CAS digests a package root's
`o/` objects carry: post-D1, every `o/` object — a tag's dispatch object (the
registry's own OCI image index, stored verbatim) and a desc blob (readme/logo,
copied verbatim from the registry's `__ocx.desc` artifact layers) alike — is
digested over its exact bytes as served, no re-serialization
(`bot/CONTRACTS.md` §6 `check_desc_change`, §5.6 desc-blob rule); the
canonical-JSON re-serialization dedup category (`bot/CONTRACTS.md` §1) applied
only to the bot-synthesized observation object and died with it
(`adr_oci_index_only_dispatch.md`) — CAS dedup across `o/` now narrows uniformly to
"same bytes." This enumeration digest is a distinct category not because CAS
re-serializes and this doesn't, but because a package root is not a CAS object at
all: it exists to answer a narrower question — "are the bytes a client already has
still current?" — and a root file is written exactly once, in the render pipeline's own
fixed `indent=2` style, so the digest must match precisely what a plain HTTP `GET`
returns, or the entire verification chain built on top of it is worthless.

Four properties follow directly:

1. **Merkle-style upward propagation** — one conditional GET on `/c/index.json`
   answers "did anything change anywhere?" without touching any `/p/**` root
   individually.
2. **An ETag + digest-diff sync protocol, for free** — `304` means fully current;
   `200` means diff the returned map against a locally cached copy, fetch only the
   roots whose digest changed, then their already-immutable, cache-forever CAS
   objects. No separate change-feed machinery, no per-root polling.
3. **Byte-verifiable snapshots** — a client, or a future offline/air-gapped mirror,
   can assert a locally cached root is authentic without re-fetching it.
4. **A foundation for the deferred signing ADR** — signing one root file
   (`/c/index.json` itself) makes the entire tree tamper-evident via the digest
   chain, the same TUF-shaped property [PEP 458](https://peps.python.org/pep-0458/)
   gives PyPI, without adopting TUF itself.

### D5 — Sharding: reserved, explicitly not built

No sharding mechanism exists in this ADR's scope. Two additive evolutions remain
available whenever growth actually demands one — both gated by `format_version` or
additive sibling paths under `/c/`, neither built now:

- A recursive `indices` pointer map — `{"indices": {"/c/aa/index.json":
  "sha256:<hex>", ...}}` — the same digest-manifest principle applied one level
  deeper, precedented directly by [PEP 458](https://peps.python.org/pep-0458/)'s
  hash-bin delegation.
- crates.io-style prefix shards, splitting `/c/index.json` by name prefix the same
  way `/p/**`'s own git-tree sharding trigger is already documented (per
  [`research_sparse_index_formats.md`](./research_sparse_index_formats.md)).

Explicitly rejected: a size-conditional discriminated union switching between an
inline list and a pointer list based on package count (Fork 1, Option B) — no
industry precedent exists for this shape anywhere in the research, and it commits
every future client to carrying two parsing code paths for one wire surface
indefinitely.

### D6 — `c` joins the reserved top-level path segments

`c` joins the reserved top-level path segments a namespace or package claim may never
occupy ([`adr_namespace_policy.md`](./adr_namespace_policy.md) ND-4's Control-path
row). A namespace or package literally named `c` would make `/c/index.json` ambiguous
to any client doing prefix-based path matching instead of this format's fixed-depth
grammar — the same routing-collision class `p` and `o` already guard against.

### D7 — `superseded_by`: optional, human-governed successor pointer

A new root field, `superseded_by`, names a package's successor for deprecation UX
("superseded by `mozilla/sccache`") in a form an `ocx` client can act on, not just
display:

- **Optional, omitted when unset** — mirrors `upstream`'s existing precedent for a
  non-universal additive field, deliberately *not* required-nullable like the
  original D2 cohort (`deprecated_message`, `created`, …). The overwhelming majority
  of packages will never set this; they should carry nothing, not an explicit
  `null`.
- **Value is the bare `<namespace>/<package>` id** — pointer form, per D3 and
  [`adr_namespace_policy.md`](./adr_namespace_policy.md) ND-2/ND-3; the `ocx.sh/`
  prefix is `name`'s self-identifying form only, never a pointer's.
- **Human-governed** — set via the same PR review gate as every other governance
  field ([`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
  G-05's human-review key set), and partitioned from bot-regenerated fields the same
  way (G-09's provenance partition).
- **Validated by shape reuse, not a second regex** — the field's shape is validated
  by parsing it through the same `<namespace>/<package>` id parser
  [`adr_namespace_policy.md`](./adr_namespace_policy.md) already defines for the
  package-id grammar (ADR-4's BD-4: length-cap-then-fullmatch, never a second
  hand-rolled pattern). Self-reference — a package naming itself as its own
  successor — is a hard validation error.
- **Deliberately unchecked for two things, by design, not oversight**:
  - **No status coupling.** `superseded_by` is independent of `status` — a package
    may name a successor while still `active`, or be `deprecated`/`yanked` with no
    successor at all. Superseded and deprecated are different concepts and this field
    keeps them that way.
  - **No existence check.** The named successor is not required to already exist as
    a committed root — a dangling or not-yet-claimed successor is allowed, exactly
    the same free-text-pointer treatment `deprecated_message` already receives. A
    client resolving this pointer must handle a missing target gracefully, not treat
    it as a hard error.
- **Additive evolution, safe under the forward-compatibility clause** the wire
  contract already commits to: `site/src/docs/reference/wire-format.md` states
  "Clients MUST ignore unknown JSON object members anywhere else in the wire format —
  additive evolution is the only kind this contract permits within one
  `format_version`." A client that predates this field simply never sees it; nothing
  breaks.

### D8 — Surface-role table

| Path | Role |
|---|---|
| `/config.json`, `/p/<namespace>/<package>.json`, `/p/<namespace>/<package>/o/sha256/<hex>.json` | **Resolution** — name known, resolve to physical content ([`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)) |
| `/c/index.json` (and any future `/c/**` sibling, D5) | **Enumeration** — full catalog by digest, no per-package detail (this ADR) |
| `/data/catalog/**` | **Site view-model** — non-contract, free to evolve, render-time aggregation for browse/search UX ([`product-context.md`](../rules/product-context.md), [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md)) |
| Site pages (`/`, `/<namespace>/<package>`, `/docs/**`) | **UI** — human-facing, consumes the three rows above |

The one enforceable principle this table exists to state: **site detail pages must
render from wire shapes only** (`/p/<namespace>/<package>.json` + OCI image indices
+ CAS blobs), never a site-private per-package shape — this is what keeps "what a
client's snapshot contains" and "what fully describes a package on the site" the same
thing by construction, and makes the site the first real consumer of exactly the
contract a future `ocx` client resolves against. This ADR records the principle only;
implementing it (retiring any site-private per-package data shape) is out of scope
here and belongs to the separate site-redesign effort —
[`handover_site_redesign.md`](./handover_site_redesign.md) is a non-normative
pointer, not a dependency of this ADR. [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md)'s
VitePress choice stands unchanged; no site framework decision is reopened here.

### D9 — Deployment & operations

`/c/index.json` inherits the Cache Rule verbatim
([`product-context.md`](../rules/product-context.md);
[`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md)
D13's conditional-GET freshness contract): Cloudflare caching must never be enabled
for `*.json` on the index zone, this file included — its entire value proposition (a
client can trust a fresh conditional GET) depends on the origin, not a CDN edge,
staying authoritative. Atomicity is free, not engineered: `/c/index.json` and every
`/p/**` root it fingerprints ship in the same Cloudflare Pages deploy
([`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md)
D15), so a client can never observe a torn state where the enumeration digest map
disagrees with the roots it points at. An empty `packages` map (`{"packages": {}}`)
is a valid state — and, as of this ADR, the actual live state: `p/` is still empty
pending Phase 4 seed data (`CLAUDE.md` Current State), so the first real deploy of
this surface serves an empty catalog, not an error.

## Consequences

**Positive:**
- Closes the enumeration half of the deferred `all.json` gap without building a
  search service — resolves the deferred item while keeping the Non-Goal (no search)
  genuinely intact, since this surface carries no metadata to search over.
- The digest-map shape gives the whole tree a TUF-shaped verifiability and future
  signing foundation at near-zero added cost — the same "decide the one-way door
  early while it is free" logic `adr_locked_observation_index_format.md` D10 already
  applied to the root+CAS split.
- `superseded_by` turns an ad hoc "link inside `deprecated_message`" convention into
  a structured, machine-readable pointer, without coupling succession to deprecation
  status.
- The surface-role table (D8) gives every future doc surface and every future PR a
  single place to check "which bucket does this path belong to" instead of
  re-deriving the answer each time.

**Negative:**
- A fourth frozen wire shape is a fourth thing every future `format_version` bump
  must consider staying backward compatible with.
- The digest map duplicates information already independently recoverable by
  fetching every root — real, deliberate duplication, justified by the
  upward-propagation win (D4), not an accidental DRY violation.

**Risks:**
- Because the digest is computed over the exact served bytes rather than a
  re-derived canonical form, any future change to the render pipeline's
  serialization style (a different indent, a different newline convention) is itself
  a breaking change to every entry in the map simultaneously — the same
  "decide-serialization-now" caution `adr_locked_observation_index_format.md` D2
  already exercises for CAS paths, extended one layer up.
- `superseded_by` allows a dangling or not-yet-claimed successor by design (D7) — the
  same accepted trade-off `deprecated_message` already carries. A client that
  resolves the pointer eagerly must treat a missing target as an expected outcome,
  not a hard failure.

## Amendment A1 — `o/` Holds a Verbatim OCI Image Index, Not an Invented Object (2026-07-25)

**Status:** Accepted — documentation correction following
[`adr_oci_index_only_dispatch.md`](https://github.com/ocx-sh/ocx/blob/main/.claude/artifacts/adr_oci_index_only_dispatch.md)
(`ocx-sh/ocx`, owner-ratified 2026-07-25).

**Problem.** D4's digest-category comparison and D8's surface-role table both
described the bot-synthesized "observation object" — the `{"platforms":[...]}`
projection `adr_locked_observation_index_format.md` originally invented for
`o/sha256/<hex>.json` — as a live artifact shape. That shape is deleted: a tag's `o/`
object is now the registry's own OCI image index, stored byte-for-byte. Neither of
this ADR's own decisions (the `/c/index.json` enumeration snapshot, D4's digest
semantics, D8's surface-role table structure) is reversed — only the terminology used
to describe the *other* CAS category D4 compares against.

**Resolution.** D4's dedup comparison now states the uniform post-D1 rule: every
`o/` object — desc blob and tag dispatch object alike — is byte-equality dedup
over exact served/registry bytes, no re-serialization; the canonical-JSON dedup
category (`bot/CONTRACTS.md` §1) applied only to the deleted observation object
and narrowed away with it, per `adr_oci_index_only_dispatch.md`'s "CAS dedup
narrows" consequence. D8's render-input parenthetical now reads "OCI
image indices" in place of "observation objects".

**Consequences:** None to this ADR's own decisions. `adr_locked_observation_index_format.md`
carries its own `Superseded By` marker for the clauses this affects (WP-B6); this
amendment only brings this ADR's *own* prose in line with that.

## Links

- [`research_index_enumeration_prior_art.md`](./research_index_enumeration_prior_art.md) — prior-art research backing this ADR
- [`decision_log_2026-07-17.md`](./decision_log_2026-07-17.md) — narrative of the 2026-07-17 discussion this ADR formalizes
- [`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md) — Deferred/Out of Scope item resolved (D1); D13 conditional-GET freshness, D15 single-deploy atomicity (D9)
- [`product-context.md`](../rules/product-context.md) — "Three frozen URL shapes" grows to four; Non-Goals bullet resolved (search itself remains a non-goal)
- [`adr_namespace_policy.md`](./adr_namespace_policy.md) — ND-4 reserved segments (`c` joins, D6); ND-2/ND-3 package-id shape reused for map keys (D3) and `superseded_by`'s value (D7); ADR-4's BD-4 length-cap-then-fullmatch reuse (D7)
- [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md) — root+CAS split this ADR applies one layer up (D2, D4); D2's root field table gains `superseded_by` (D7); `bot/CONTRACTS.md` §1 canonical-JSON CAS digest, distinct from this ADR's D4 digest
- [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md) — G-05 human-review key set and G-09 field-provenance partition, both extended to `superseded_by` (D7)
- [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md) — VitePress and colocation model, unchanged (D8)
- [`handover_site_redesign.md`](./handover_site_redesign.md) — non-normative pointer for D8's site-detail-renders-from-wire-only principle
- [PEP 458 — Secure PyPI downloads with signed repository metadata](https://peps.python.org/pep-0458/) — TUF snapshot-role precedent for D2/D4
- [The Update Framework (TUF)](https://theupdateframework.io/) — snapshot-role concept
- [createrepo_c](https://github.com/rpm-software-management/createrepo_c) — `repomd.xml` pointer+checksum root precedent for D2/D4

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Michael Herwig + Claude design swarm | Initial record from the 2026-07-17 design discussion: fourth frozen wire shape (`/c/index.json`), digest-map shape, reserved sharding, `superseded_by` root field, surface-role table |
| 2026-07-25 | Claude (sonnet, WP-B8) | Added `Superseded By` (partial) and Amendment A1: corrected D4's dedup-category comparison and D8's render-input reference from "observation object(s)" to the verbatim-OCI-image-index shape, per `adr_oci_index_only_dispatch.md`. No D-decision of this ADR reversed. |
| 2026-07-25 | Claude (sonnet, WP-B8 review-fix) | Review caught Amendment A1's own rewrite of D4: it had desc blobs hashed under `bot/CONTRACTS.md` §1's canonical-JSON form, but `bot/CONTRACTS.md` §6 (`check_desc_change`) and §5.6 state desc blobs are copied verbatim and hashed over their exact bytes, never re-serialized. Corrected D4 and A1's Resolution: post-D1 every `o/` object (dispatch object and desc blob alike) dedups on byte-equality; the canonical-JSON dedup category died with the observation object. |
