# ADR: Namespace Policy — Vendor-Identity Namespaces with Reviewer-Validated First Claim

## Metadata

**Status:** Accepted
**Date:** 2026-07-17 (decision discussion: 2026-07-16)
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** governance | naming | security
**Amends:** D6 (ownership proof) and D7 (naming model) of [adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md) — see [Relationship to the Original ADR](#relationship-to-the-original-adr)
**Supersedes:** N/A

## Context

Every package name in the index is always two-level: `<namespace>/<package>`. The
original ADR ([D7](./adr_public_index_registry_indirection.md#d7--naming-model-docker-hub-style-flat-claimed-namespaces))
picked flat, Docker-Hub-style claimed namespaces and tied ownership entirely to
physical-registry write access (D6: "index entry name must equal the identifier
embedded in the manifest at the claimed physical repo"). That model is literally true
for the 44 seed packages today — they are all physically mirrored under
`ghcr.io/ocx-contrib/*` by the OCX project itself — but it says nothing about what a
namespace *means* to a human reading the catalog, and it does not by itself decide
whether the seeds should read `ocx.sh/kitware/cmake` (implying Kitware's identity)
or `ocx.sh/ocx-contrib/cmake` (implying the OCX mirror's identity).

[research_namespace_policy.md](./research_namespace_policy.md) surveyed namespace
governance across [Bazel Central Registry](https://github.com/bazelbuild/bazel-central-registry),
[OpenTofu's module registry](https://opentofu.org/docs/internals/module-registry-protocol/),
[npm scopes](https://docs.npmjs.com/about-scopes/), Go vanity imports, and
[Homebrew taps](https://docs.brew.sh/Taps), and found that every one of them gates the
*first claim* of a namespace with human review, not automation. This ADR settles the
questions the research left open: what a namespace identifies, its exact charset and
reserved list, the dispute/rename policy, and — the one real owner decision — whether
the 44 seeds namespace under the upstream vendor or under the OCX publisher.

## Decision Drivers

- Catalog credibility: a namespace that visually reads as a real vendor's identity
  (`kitware/cmake`) must not imply control that vendor never exercised, without an
  explicit, visible disclaimer.
- No new CI machinery beyond what [ADR-4](./adr_index_bot_and_workflow_security.md)
  already designs (G-04 human review at first claim, G-15 registry-ownership probe).
- The wire contract's `/p/<namespace>/<package>...` path shape must never collide with
  sibling top-level routes on the same domain, now that the catalog and docs site are
  colocated on `index.ocx.sh`
  ([adr_catalog_docs_colocation.md](./adr_catalog_docs_colocation.md)).
- Boring precedent over novel governance: reuse the [crates.io](https://crates.io/policies)/[npm](https://docs.npmjs.com/about-scopes/)
  dispute model verbatim rather than inventing a reservation or trademark-adjudication
  system.

## Industry Context & Research

**Research artifact:** [research_namespace_policy.md](./research_namespace_policy.md)

**Key insight:** two different concerns get conflated if not kept apart. *Claim-time
identity fit* (does this namespace plausibly belong to the party filing the PR?) is a
human-review problem every surveyed system solves the same way — a reviewer looking at
a PR, not a CI check. *Ongoing ownership proof* (does the physical registry content
still match what the namespace claims?) is the one thing OCX's own design already
automates (D6/G-15) that no surveyed system automates for identity —
[GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
write access proves registry control, not real-world vendor identity, and this ADR
treats those as two separate, complementary checks rather than one.

| System | Namespace meaning | First-claim gate |
|---|---|---|
| [BCR](https://github.com/bazelbuild/bazel-central-registry) | Flat module name, no namespace | Human PR review |
| [OpenTofu registry](https://opentofu.org/docs/internals/module-registry-protocol/) | GitHub org/user owning the source repo | Public org-membership + manual verification |
| [npm scopes](https://docs.npmjs.com/about-scopes/) | npm account/org identity | Self-contained (npm's own account) |
| [Homebrew taps](https://docs.brew.sh/Taps) | GitHub username/org owning the repo | GitHub repo ownership itself |
| [Docker Hub Official Images](https://docs.docker.com/docker-hub/image-library/trusted-content/) | Privileged `library/` root tier, curated by Docker | Docker-internal review, opaque admission |
| **OCX (this ADR)** | Vendor/publisher identity (org, business, project) | Human PR review (G-04) + upstream-attribution field |

## Considered Options

### Option 1: Vendor-identity namespace + reviewer validation + attribution (chosen)

**Description:** Namespace names the real vendor/publisher — the organization,
business, or project that authored the package — regardless of which host currently
mirrors the bytes. A PR reviewer checks plausible identity fit at first claim (G-04);
an `upstream` object on the entry records attribution and, where mirrored by a third
party, an explicit not-affiliated disclaimer.

| Pros | Cons |
|------|------|
| Highest discoverability — users recognize the real maker (`kitware/cmake`) | D6/G-15 alone no longer proves namespace *identity*, only physical-registry control — closes the gap with human review + attribution instead |
| Matches the [winget](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest) `Publisher.Package` precedent users already expect from package managers | Real trademark/impersonation surface if a reviewer approves a claim that turns out to be unconsented — same residual risk research §5 flagged for Option A |
| Future direct-publish path is clean: the real vendor inherits the name it already reads as | Requires the `upstream` attribution object to exist in the schema before seeds land (schema dependency, tracked in Phase 1) |

### Option 2: Publisher namespace (research recommendation)

**Description:** Namespace names the entity that actually pushed the bytes —
`ocx.sh/ocx-contrib/<pkg>` for every OCX-mirrored seed. D6's "registry write access =
ownership proof" is then literally true of the namespace as well as the package.

| Pros | Cons |
|------|------|
| Zero new claim ceremony — D6/G-15 alone is a complete, accurate ownership proof | Lower discoverability — users must trust the curator, not recognize the vendor |
| No unconsented trademark exposure — `ocx-contrib` is OCX's own namespace | Namespace collision if the real vendor later wants direct-publish under their own name (the mirror already sits on it) |
| Matches [DefinitelyTyped](https://github.com/DefinitelyTyped/DefinitelyTyped)'s `@types` curator-scope precedent | Undersells vendor identity the catalog exists to surface |

### Option 3: [Docker Hub](https://hub.docker.com/) [`library/`](https://docs.docker.com/docker-hub/image-library/trusted-content/) privileged root tier

**Description:** A single reserved root namespace ([Docker Hub](https://hub.docker.com/)'s
`library`) holds curator-blessed packages and is displayed *without* a namespace prefix
at all (`docker pull ubuntu` really means `docker pull library/ubuntu`); every other
publisher gets a normal namespaced name.

| Pros | Cons |
|------|------|
| Shortest possible names for the packages judged "most important" | Opaque two-tier admission — draws a line between packages treated as canonical and everyone else, with no documented, repeatable test for which side a given package lands on |
| Precedented at [Docker Hub](https://hub.docker.com/)'s scale | Breaks the "always two-level" invariant this repo already committed to; a bare-name fast path is a second code path through every consumer (validation, rendering, resolution) for the CLI to special-case forever |
| — | No governance benefit over Option 1: still needs the same human review at claim time, plus an extra admission process to decide who gets the privileged tier |

## Decision Outcome

**Chosen Option:** Option 1 — vendor-identity namespaces, reviewer-validated at first
claim, carrying an upstream-attribution object. Option 3 ([Docker Hub](https://hub.docker.com/)'s
`library` root tier) is rejected outright: it is a privileged root namespace, and this
repo commits to having none.

**Rationale:** The research recommendation (Option 2) is the more conservative,
zero-new-ceremony choice and remains a completely valid model if a namespace claim is
ever revoked or disputed. The owner chose Option 1 because the catalog's primary value
is discoverability of the real ecosystem tools it indexes (`kitware/cmake`,
`astral-sh/uv`, `oven-sh/bun`) — a curator-namespaced catalog (`ocx-contrib/cmake`
everywhere) undersells that. The gap Option 2 avoids (D6 no longer alone proving
namespace identity) is closed by promoting G-04's existing human review from a
generic new-package gate to an explicit identity-fit check, and by carrying the
`upstream` attribution object on every entry so no page ever implies unearned vendor
endorsement — the [Chainguard trademark-use precedent](https://www.chainguard.dev/legal/chainguard-trademark-use-policy)
research §5 flagged applies here directly.

### Consequences

**Positive:**
- Catalog pages read as the real ecosystem, not an OCX-curated relabeling of it.
- `upstream.disclaimer` gives a documented, low-cost way to mark "not affiliated"
  where relevant, without inventing a new legal review process.
- The dispute/rename mechanics (below) are unchanged from Option 2's — this decision
  only changes what a namespace *names*, not how claims are adjudicated or revoked.

**Negative:**
- Every claim PR now carries identity-fit risk the reviewer must actually exercise
  judgment on (G-04) — Option 2 would have made this check nearly mechanical.
- If a vendor namespace is later disputed or the vendor asks to take over publishing
  directly, migration goes through the no-rename mechanic below (new claim + deprecate
  old), same cost as any other rename — not a special case, but a real one that will
  happen at least once given 44 seeds carry vendor identities they were not asked for.

**Risks:**
- Unconsented use of a real org's identity is the residual risk research §1/§5 already
  named: no surveyed system (including this one) automates real-world identity
  verification. Mitigation: reviewer discretion at G-04 + `upstream.disclaimer` +
  the same [crates.io](https://crates.io/policies)/[npm](https://github.com/npm/policies/blob/master/archived/disputes.md)
  complaint-driven dispute path every other registry relies on (see ND-6 below).

## Decisions

### ND-1 — Namespace identifies the vendor/publisher, not a host

A namespace names an **identity** — an organization, business, or open-source project
— never a hosting location, registry, or physical repository path. It is
host-irrelevant: `kitware/cmake` stays `kitware/cmake` even if the physical mirror
moves from `ghcr.io/ocx-contrib/cmake` to a different registry entirely (this is the
whole point of the index's indirection — see
[D8](./adr_public_index_registry_indirection.md#d8--client-architecture-early-identifier-rewrite)
in the original ADR).

A namespace should preferably match a GitHub org the vendor controls, or another
online identity the vendor demonstrably holds (a reserved domain, an official project
name), but this is a preference the reviewer weighs, not a hard requirement enforced by
CI — there is no automatable check for "this real-world entity approves of this
namespace" (research §1). Fit is judged once, by a human, at first claim (ND-5).

### ND-2 — Always two-level, no privileged root namespace

Every package name is `<namespace>/<package>` — no bare package names, no shortcut
tier. The Docker Hub `library` model (Option 3) is explicitly rejected: a privileged
root namespace is an opaque two-tier admission process that draws an undocumented line
between packages treated as canonical and everyone else, with no repeatable test for
which side a package lands on. It also reintroduces a bare-name code path every
consumer (CLI resolver, CI validation, render pipeline) would have to special-case
forever, breaking the invariant the wire format and the OCX package-id regex (ND-3)
both already assume.

### ND-3 — Charset and shape: two distinct regexes that must never be conflated

Two regexes exist and are never interchangeable:

1. **OCX package-id regex** (governs the logical `<namespace>/<package>` name — the
   entry's `name` field and its `p/<namespace>/<package>.json` source path): exactly
   two lowercase segments, one `/` separator, **total string length ≤ 140 characters**.
   Validation order is **length-cap-then-fullmatch**: reject on length *before* running
   the regex's `fullmatch()`, bounding worst-case regex work against a pathological
   long input (ties into the ReDoS wall-clock test on `core/validate_payload`, plan
   Phase 2 WP2-A). Each segment individually follows:
   - **namespace segment:** lowercase-folded GitHub-login pattern,
     `^[a-z0-9](?:-?[a-z0-9])*$`, 1–39 characters (case-folding is lossless — GitHub
     logins are already case-insensitive).
   - **package segment:** the OCI distribution-spec repository-component grammar
     verbatim, `[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*`, ≤ 100 characters.
   - 39 + 1 (`/`) + 100 = 140 — the combined length cap is not an arbitrary round
     number, it is the sum of the two segment caps.
2. **OCI repository regex** (governs the *physical* `repository` field, e.g.
   `ghcr.io/ocx-contrib/cmake`): the full distribution-spec grammar,
   `[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*`
   ([spec.md](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)),
   which permits **N segments**, not two.

These must never be conflated. Known failure mode in adjacent OCI tooling
([regclient](https://github.com/regclient/regclient),
[regsync](https://github.com/regclient/regclient/tree/main/cmd/regsync)): validating a
fixed-arity identifier against the general N-segment OCI repository grammar silently
admits or rejects values the fixed-arity field was never meant to accept — a namespace
value containing an extra `/`, or a physical-repository path wrongly capped at two
segments. [ADR-4](./adr_index_bot_and_workflow_security.md) owns the CI-side validation
mechanics (regex placement, env-var indirection for untrusted input) that keep the two
regexes structurally separate in code; this ADR fixes only the shape and rationale.

ASCII-only in v1 — both source grammars (GitHub login, OCI component) are ASCII-only,
and there is no identity provider here to justify the homograph-attack surface Unicode
namespaces would open.

### ND-4 — Reserved namespace segments (routing-collision rationale)

The following segment values are reserved and rejected at claim time, checked against
**both** the namespace and package positions (the two-segment package-id shape does not
otherwise distinguish which position collides):

| Category | Segments | Why reserved |
|---|---|---|
| Control paths | `p`, `o`, `docs`, `assets`, `config`, `schema`, `api`, `static`, `data` | Every one of these is a top-level directory in the index git tree and/or a top-level URL path on the colocated `index.ocx.sh` deployment (`/p/` wire prefix, `/docs/` VitePress site, `/config.json`, `/schema/`, `/data/catalog/`, plus `static`/`api` reserved for future site expansion). `o` specifically is the literal CAS-objects marker inside every package's own subtree (`/p/<ns>/<pkg>/o/sha256/<hex>.json`) — a namespace or package segment equal to `o` would make that path ambiguous to any tool that does prefix matching instead of fixed-depth parsing. |
| Brand | `ocx`, `ocx-sh`, `ocx-contrib`, `ocx-rs` | OCX's own project and org identities; claiming one of these as a third-party vendor namespace would be indistinguishable from an OCX-first-party entry. |
| Generic/ambiguous | `admin`, `root`, `system`, `std`, `core`, `official`, `public`, `test`, `example`, `internal` | Words whose plain-English meaning implies a privileged or non-existent-vendor status the two-level model explicitly refuses to grant (ND-2) — reserving them removes the temptation to reintroduce a `library`-style tier by convention rather than by design. |

The Brand row is reserved from third-party claims without exception; it does not by
itself decide whether OCX's own first-party packages may use it — see
[Amendment A1](#amendment-a1-2026-07-17-first-party-use-of-brand-segments) below
(Accepted 2026-07-17) for that carve-out.

This list is deliberately small and collision-driven, not an exhaustive trademark
denylist — GitHub itself does not formally reserve usernames as policy (research §3,
citing the
[GitHub username policy](https://docs.github.com/en/site-policy/other-site-policies/github-username-policy)),
and this repo follows the same posture: block what actually collides with the wire
contract or the site, adjudicate everything else case by case (ND-6).

### ND-5 — First-claim governance: reviewer validates fit, no new CI machinery

A new namespace is claimed by opening a PR that adds the first `p/<namespace>/<pkg>.json`
entry under it. G-04 ([design_spec_registry_indirection.md](./design_spec_registry_indirection.md),
carried forward and reinterpreted by
[ADR-4](./adr_index_bot_and_workflow_security.md)) already requires
the `new-package` label and a mandatory human review, blocking auto-merge. This ADR
adds no new CI check — it specifies what the reviewer is checking: does the claimed
namespace plausibly fit the identity it names (ND-1)? Registry-write ownership (D6,
executed by G-15) is a separate, complementary, fully automated check that proves the
physical bytes match the entry — it does not and cannot prove real-world vendor
identity, which is why the human step stays load-bearing.

### ND-6 — Dispute, squatting, and transfer: crates.io/npm precedent, unchanged

Adopted verbatim, no new workflow:

- **First-come, first-claim.** No reservation system, no pre-claim application process.
- **Squatting test:** a claim with no genuine function (dead entry, name held with no
  package behind it) is treated as squatting on request, exactly as
  [npm's dispute policy](https://github.com/npm/policies/blob/master/archived/disputes.md)
  and [crates.io's policies](https://crates.io/policies) define it — contact the
  current owner first, human adjudication by a maintainer if that fails.
- **No proactive squatting police.** Reviewers do not preemptively hunt for or block
  plausible future namespace claims; disputes are handled reactively, on complaint.
- **Transfer** goes through the always-human-reviewed `owners[]` field path — the same
  review gate as any other ownership-affecting change (G-05's human-review key set).

### ND-7 — No rename primitive; namespace is immutable once claimed

There is no rename operation for a namespace, matching Go vanity imports and Homebrew
taps, neither of which has one either. Once claimed, a namespace is immutable.
Migrating a package to a different namespace is: claim the new `<namespace>/<package>`
entry fresh (subject to ND-5 review as any new claim), then deprecate the old entry
(`status: deprecated` + `deprecated_message` pointing at the new name). The old entry's
namespace is not reclaimable by moving it — it simply stops resolving to current
content.

### ND-8 — `owners[].github_id` is mandatory

Every entry's `owners[]` array carries the numeric `github_id`, not just the `github`
login string, and it is **mandatory**, not optional. Rationale, taken directly from BCR
precedent (research §4, citing
[metadata.schema.json](https://github.com/bazelbuild/bazel-central-registry/blob/main/metadata.schema.json)):
the numeric id survives GitHub username renames and account takeovers of a since-freed
login; the login string alone does not. The `github` login field still exists for
human-readable display; the id is the field any ownership check keys on.

### ND-9 — Upstream attribution object

The `upstream` object is **mandatory** on every entry whose namespace names a real
vendor identity mirrored by a third party — in practice, every one of OCX's own seed
entries (ND-10). It is a governance requirement, not an incidental nicety: this ADR
chose vendor-identity namespaces over D6-honest publisher namespaces (Decision Outcome)
specifically *because* attribution closes the trademark/impersonation gap that choice
opens, so a claim PR namespacing a package under a real vendor without a populated
`upstream` object fails review (G-04). The object is omitted only for OCX's own
first-party namespaces (ND-10), where there is no third-party identity to attribute.

```json
"upstream": {
  "org": "kitware",
  "repository_url": "https://github.com/Kitware/CMake",
  "disclaimer": "Mirrored by the OCX project; not affiliated with or endorsed by Kitware."
}
```

`org` is required whenever `upstream` is present; `repository_url` and `disclaimer` are
optional. `disclaimer` exists specifically to carry a not-affiliated note where
appropriate, mirroring the
[Chainguard trademark-use precedent](https://www.chainguard.dev/legal/chainguard-trademark-use-policy)
research §5 identified: a mirror is free to publish under a vendor's identity only if
it never implies unearned endorsement. The exact schema shape (required/optional
markers, field types) is finalized in `schema/root.schema.json` (Phase 1, WP1-A) —
`upstream` is a root field ([D2](./adr_locked_observation_index_format.md#d2--layout-oci-isomorphic-root--cas)
of `adr_locked_observation_index_format.md`); this ADR fixes the object's existence and
purpose, not its JSON Schema encoding.

### ND-10 — Seed namespaces: vendor identity, not publisher (owner decision)

The 44 seed packages are namespaced under the real upstream vendor or project, not
under `ocx-contrib` (the physical mirror publisher). This is Option 1 applied to the
concrete seed set, and it directly overrides the research recommendation (Option 2),
which was chosen for its D6-honesty property — see [Decision Outcome](#decision-outcome)
for the full rationale. Representative entries from the seed table (plan Phase 4,
case-folded per ND-3):

| Namespace/package | Physical mirror | Upstream org |
|---|---|---|
| `kitware/cmake` | `ghcr.io/ocx-contrib/cmake` | Kitware |
| `astral-sh/uv` | `ghcr.io/ocx-contrib/uv` | Astral |
| `oven-sh/bun` | `ghcr.io/ocx-contrib/bun` | Oven |
| `gitlab-org/glab` | `ghcr.io/ocx-contrib/glab` | GitLab |
| `ocx/cli` | `ghcr.io/ocx-contrib/cli` | OCX itself — first-party, `upstream` omitted |

Every non-first-party seed entry carries the `upstream` object (ND-9). First-party OCX
packages (`ocx/cli`, `ocx/mirror`) omit `upstream` entirely — there is no third-party
identity to attribute.

`ocx` is a reserved Brand segment under ND-4. As written, ND-4 and this worked example
contradict each other — `ocx/cli` cannot pass `check_namespace_not_reserved` without a
carve-out. [Amendment A1](#amendment-a1-2026-07-17-first-party-use-of-brand-segments)
below resolves this; until it is accepted, `ocx/cli` and `ocx/mirror` cannot actually be
claimed.

## Relationship to the Original ADR

This ADR amends, not supersedes, the original
[adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md):

- **D6 (ownership proof)** stands as an automated, complementary check — it proves
  physical-registry control, and continues to gate refresh/regeneration (G-15, owned by
  ADR-4). This ADR adds that D6 alone no longer stands in for namespace *identity*
  verification; ND-5's human review at first claim carries that weight now.
- **D7 (naming model)** is replaced in substance: flat, publisher-bound namespaces
  become two-level, vendor-identity namespaces (ND-1, ND-2). The "index maps logical →
  physical, N:1 allowed" property D7 established is unchanged — only what the namespace
  segment *names* changes.

## Amendments

### Amendment A1 (2026-07-17): First-Party Use of Brand Segments

**Status:** Accepted — owner sign-off 2026-07-17 (Michael Herwig, session decision
record). The enforcement mechanism (`--allow-reserved-namespace`, brand segments only)
remains default-off; first-party brand-segment claims pass through the same G-04
human-review PR gate as any other first claim.

> Disambiguation: this is ADR-2's own Amendment A1, distinct from the unrelated
> "ADR Amendment A1" cited in
> [adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md)
> and `handover_from_ocx.md` (2026-07-12, the `ocx.sh`-canonical/`ocx.rs`-parked
> decision). The two share a label by coincidence of numbering, not by relation —
> always qualify as "ADR-2 Amendment A1" when the ADR is ambiguous from context.

**Problem.** ND-4 reserves the Brand segments (`ocx`, `ocx-sh`, `ocx-contrib`,
`ocx-rs`) unconditionally, in either the namespace or package position —
`core/validate_entry.py`'s `check_namespace_not_reserved` rejects any of them found in
`RESERVED_NAMESPACE_SEGMENTS`, with no carve-out in the code or in ND-4's text. ND-10's
own worked example, in this same ADR, lists `ocx/cli` as a legitimate seed entry —
"OCX itself — first-party, `upstream` omitted." As written, ND-4 and ND-10 contradict
each other: `ocx/cli` cannot pass `check_namespace_not_reserved` (`ocx` is in
`RESERVED_NAMESPACE_SEGMENTS`), yet ND-10 presents it as an already-settled seed.
Surfaced during the Phase 4 seeding pilot (2026-07-17), when a first-party seed-import
of `ocx/cli` failed namespace validation.

**Resolution.** Brand segments are reserved *from third parties*, *for first-party
use* — the three rows in ND-4's table are not, on reflection, the same kind of
reservation, and this amendment only changes one of them:

- **Control-path segments** (`p`, `o`, `docs`, `assets`, `config`, `schema`, `api`,
  `static`, `data`) stay reserved unconditionally, no exceptions, first-party included.
  These guard routing collisions with the wire contract and the colocated site, not
  identity — there is no first-party/third-party distinction that applies to a path
  collision.
- **Generic/ambiguous segments** (`admin`, `root`, `system`, `std`, `core`, `official`,
  `public`, `test`, `example`, `internal`) stay reserved unconditionally, unchanged from
  ND-4's original rationale — a word whose plain-English meaning implies privileged or
  non-existent-vendor status is exactly as misleading coming from OCX itself as from a
  third party.
- **Brand segments** (`ocx`, `ocx-sh`, `ocx-contrib`, `ocx-rs`) remain reserved from
  third-party claims without exception — unchanged, a third party may never claim one of
  these — but become available for genuine first-party OCX entries, subject to **both**:
  1. The same G-04 human-review PR gate every namespace first-claim already goes
     through (ND-5) — a brand claim gets no weaker review than any other first claim.
  2. An explicit tooling override at the enforcement layer: `--allow-reserved-namespace`
     (brand-segment-only — the flag refuses to lift the check for control-path or
     generic segments; only the four Brand values above are eligible). A reviewer
     approving the PR is not sufficient by itself; the tool must also be told,
     explicitly, that this specific claim is a deliberate first-party exception, not an
     oversight that slipped past review.

**Enforcement.** `seed-import` and `validate` gain the `--allow-reserved-namespace`
flag in this PR, shipped default-off — nothing currently invokes it. ND-10's `ocx/cli`
and `ocx/mirror` seed entries cannot land until (a) the owner accepts this amendment and
(b) the flag is passed explicitly for that `seed-import` run. Until both are true,
`check_namespace_not_reserved` continues to enforce ND-4's unconditional reservation in
practice — this amendment describes intended future behavior, not current behavior.

**Cross-references updated:** ND-4's Brand row and ND-10's first-party-omission
paragraph (above) both now point here.

## Links

- [adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md) — D6, D7, amended above
- [adr_locked_observation_index_format.md](./adr_locked_observation_index_format.md) — wire format this namespace shape is embedded in
- [adr_catalog_docs_colocation.md](./adr_catalog_docs_colocation.md) — colocated site whose top-level routes motivate ND-4
- [adr_index_bot_and_workflow_security.md](./adr_index_bot_and_workflow_security.md) — owns G-01..G-18 mechanics, including G-04/G-05/G-15 referenced here
- [design_spec_registry_indirection.md](./design_spec_registry_indirection.md) — source definitions of G-04, G-05, G-15
- [decision_log_2026-07-16.md](./decision_log_2026-07-16.md) — narrative of the discussion this ADR formalizes
- [research_namespace_policy.md](./research_namespace_policy.md) — source research
- [Bazel Central Registry](https://github.com/bazelbuild/bazel-central-registry), [OpenTofu module registry protocol](https://opentofu.org/docs/internals/module-registry-protocol/), [npm scopes](https://docs.npmjs.com/about-scopes/), [Homebrew Taps](https://docs.brew.sh/Taps), [Docker Hub Official Images](https://docs.docker.com/docker-hub/image-library/trusted-content/), [OCI distribution-spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md) — external precedents

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Michael Herwig + Claude design swarm | Initial ADR from the 2026-07-16 design discussion |
| 2026-07-17 | Claude (docs) | Added Amendment A1 (PROPOSED, pending owner sign-off): first-party carve-out for Brand namespace segments, resolving the ND-4/ND-10 contradiction found during the Phase 4 seeding pilot. Updated ND-4/ND-10 cross-references. |
| 2026-07-17 | Michael Herwig (owner sign-off) | Amendment A1 status flipped from PROPOSED to Accepted — owner sign-off recorded as a session decision (Michael Herwig); enforcement mechanism (`--allow-reserved-namespace`, brand segments only) confirmed default-off. |
