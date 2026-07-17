---
title: Namespace Policy
---

# Namespace Policy

Every package name in the index is always two-level:
`<namespace>/<package>`. This page documents what a namespace identifies,
its charset, the reserved segments, and how claims and disputes are
handled. Design authority:
[`adr_namespace_policy.md`](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_namespace_policy.md).

## What a Namespace Identifies

A namespace names an **identity** — an organisation, business, or
open-source project — never a hosting location, registry, or physical
repository path. It is host-irrelevant: `kitware/cmake` stays
`kitware/cmake` even if the physical mirror moves to a different registry
entirely.

A namespace should preferably match a GitHub org the vendor controls, or
another online identity the vendor demonstrably holds, but this is a
preference a reviewer weighs at claim time, not a hard rule enforced by CI —
there is no automatable check for "this real-world entity approves of this
namespace".

There is no privileged root namespace (no Docker Hub `library`-style bare
tier). Every package always has a two-segment name, so no namespace ever
gets opaque, un-auditable admission.

## Charset and Shape

Two distinct regexes exist and are never interchangeable:

**OCX package-id regex** (governs the logical `<namespace>/<package>`
name — the entry's `name` field and its `p/<namespace>/<package>.json`
source path): exactly two lowercase segments, one `/` separator, total
string length ≤ 140 characters. Validation is length-cap-then-`fullmatch`.

- **namespace segment**: lowercase-folded GitHub-login pattern,
  `^[a-z0-9](?:-?[a-z0-9])*$`, 1–39 characters.
- **package segment**: the OCI distribution-spec repository-component
  grammar, `[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*`, ≤ 100 characters.
- 39 + 1 (`/`) + 100 = 140 — the combined cap is the sum of the two segment
  caps, not an arbitrary number.

**OCI repository regex** (governs the *physical* `repository` field, e.g.
`ghcr.io/ocx-contrib/cmake`): the full
[distribution-spec grammar](https://github.com/opencontainers/distribution-spec/blob/main/spec.md),
`[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*`,
which permits N segments, not two.

Both grammars are ASCII-only in v1 — there is no identity provider here to
justify the homograph-attack surface Unicode namespaces would open.

## Reserved Segments

The following values are rejected at claim time, checked against **both**
the namespace and the package position:

| Category | Segments | Why reserved |
|---|---|---|
| Control paths | `p`, `o`, `c`, `docs`, `assets`, `config`, `schema`, `api`, `static`, `data` | Top-level directories in the index git tree and/or top-level URL paths on the colocated `index.ocx.sh` deployment. `o` specifically is the CAS-objects marker inside every package's own subtree — a namespace or package segment equal to `o` would make that path ambiguous to a tool doing prefix matching. `c` is the top-level enumeration-index segment (`/c/index.json`) — reserved for the same routing-collision reason. |
| Brand | `ocx`, `ocx-sh`, `ocx-contrib`, `ocx-rs` | OCX's own project and org identities. |
| Generic/ambiguous | `admin`, `root`, `system`, `std`, `core`, `official`, `public`, `test`, `example`, `internal` | Words whose plain-English meaning implies a privileged or non-existent-vendor status the two-level model refuses to grant. |

This list is deliberately small and collision-driven, not an exhaustive
trademark denylist — it blocks what actually collides with the wire
contract or the site; everything else is adjudicated case by case (see
Dispute Policy below).

## First-Claim Governance

A new namespace is claimed by opening a PR that adds the first
`p/<namespace>/<package>.json` entry under it. This is a mandatory human
review, blocking auto-merge (see
[Governance Contracts](./governance-contracts) G-04). No new CI check
exists beyond the schema/semantic validation every entry gets — the
reviewer's job is to judge whether the claimed namespace plausibly fits the
identity it names.

Registry-write ownership (does the physical registry content match what the
entry claims) is a separate, fully automated check — it proves physical
control, not real-world vendor identity, which is why the human step stays
load-bearing. See [Claim a Namespace](../how-to/claim-a-namespace) for the
step-by-step procedure.

## Dispute Policy

Adopted from the crates.io/npm precedent, verbatim, no new workflow:

- **First-come, first-claim.** No reservation system, no pre-claim
  application process.
- **Squatting test**: a claim with no genuine function (dead entry, name
  held with no package behind it) is treated as squatting on request — the
  current owner is contacted first; a maintainer adjudicates if that fails.
- **No proactive squatting police.** Reviewers do not preemptively hunt for
  or block plausible future namespace claims; disputes are handled
  reactively, on complaint.
- **Transfer** goes through the always-human-reviewed `owners[]` field
  path — the same review gate as any other ownership-affecting change.
- **No rename primitive.** A namespace is immutable once claimed. Migrating
  a package to a different namespace means claiming the new
  `<namespace>/<package>` entry fresh (subject to the same first-claim
  review) and deprecating the old one (`status: deprecated` +
  `deprecated_message` pointing at the new name). The old namespace is not
  reclaimable by moving it.

## `owners[].github_id`

Mandatory, not optional, on every entry. The numeric id survives GitHub
username renames and account takeovers of a since-freed login; the login
string alone does not. `github` still exists for human-readable display; the
id is what any ownership check keys on.

## Upstream Attribution

The `upstream` object (`org`, optional `repository_url`, optional
`disclaimer`) is mandatory on every entry whose namespace names a real
vendor identity mirrored by a third party — in practice, every one of
OCX's own seed entries. A claim PR namespacing a package under a real
vendor without a populated `upstream` object fails review. The object is
omitted only for OCX's own first-party namespaces (`ocx/*`), where there is
no third-party identity to attribute. See [Entry Schema](./entry-schema)
for the exact object shape.
