---
title: Entry Schema
---

# Entry Schema

Field-level reference for the two wire-format JSON shapes that carry package
data: the package root and the OCI image index. This page is a summary
table derived from the JSON Schemas below — the schemas are the source of
truth for exact types, patterns, and constraints; consult them directly for
anything this table simplifies.

- Root: [`https://index.ocx.sh/schema/root.schema.json`](https://index.ocx.sh/schema/root.schema.json)
- Image index: [`https://index.ocx.sh/schema/image-index.schema.json`](https://index.ocx.sh/schema/image-index.schema.json)
- Config: [`https://index.ocx.sh/schema/config.schema.json`](https://index.ocx.sh/schema/config.schema.json)
- Enumeration index: [`https://index.ocx.sh/schema/c-index.schema.json`](https://index.ocx.sh/schema/c-index.schema.json)

See [Wire Format](./wire-format) for URL shapes and freshness semantics, and
[Namespace Policy](./namespace-policy) for the `name`/`repository` charset.

## `config.json`

| Field | Type | Required | Notes |
|---|---|---|---|
| `format_version` | integer, ≥1 | yes | Monotonically increasing wire-format generation counter |

## Enumeration Index — `/c/index.json`

| Field | Type | Required | Notes |
|---|---|---|---|
| `format_version` | integer, ≥1 | yes | same counter as `config.json` |
| `packages` | map: bare `<namespace>/<package>` → `sha256:<hex>` | yes | sorted by key; value is the digest of the **exact bytes** served at that package's root (`/p/<key>.json`) — not a canonical-JSON CAS digest; empty map is a valid state |

See [Wire Format](./wire-format#c-index-json-—-enumeration-index) for the
sync protocol built on top of this shape.

## Package Root — `/p/<namespace>/<package>.json`

| Field | Type | Required | Governed by | Notes |
|---|---|---|---|---|
| `name` | string | yes | human (PR) | `ocx.sh/<namespace>/<package>`, ≤147 chars |
| `repository` | string | yes | human (PR) | `oci://<host>/<repo path>`; host checked at CI time against this index's [registry-host policy](./governance-contracts#registry-host-policy-g-03) (`ghcr.io` here) |
| `owners` | array of [Owner](#owner) | yes, ≥1 item | human (PR) | |
| `status` | enum | yes | human (PR) | `active` \| `deprecated` \| `yanked` |
| `deprecated_message` | string \| null | yes | human (PR) | |
| `superseded_by` | string \| null | no | human (PR) | bare `<namespace>/<package>` naming a successor package, ≤140 chars; omitted or `null` when unset; self-reference invalid, no coupling to `status` |
| `created` | string, `YYYY-MM-DD` | yes | human (PR), set once | date first claimed |
| `upstream` | [Upstream](#upstream) object | no | human (PR) | mandatory by governance for third-party vendor namespaces; omitted for OCX first-party entries |
| `source` | string, `https://…` | no | bot-regenerated | repository whose CI produced the published builds, from the `org.opencontainers.image.source` annotation on the latest version's manifest; omitted (or `null`) when that annotation is absent. Not `upstream.repository_url` — see below |
| `variants` | array of string | no | bot-regenerated | variant names observed across `tags` — sorted, deduplicated, ≥1 item. Omitted (never `[]`) when the package ships only the default variant. See [Variants](#variants) |
| `desc` | [Desc](#desc) object \| `null` | yes (nullable) | bot-regenerated | `null` if `__ocx.desc` never published |
| `tags` | map: tag name → [TagEntry](#tagentry) | yes | bot-regenerated, except `yanked` | every observed tag, no filtering |

### Variants

A **variant** is a build of the same version with different software-level
characteristics — an optimisation profile, a feature set, a libc. It is spelled
as a tag prefix: `slim-3.13.1` is the `slim` variant of `3.13.1`, and an
unprefixed `3.13.1` is the *default* variant.

`variants` is a **projection of `tags`**, not an independent declaration, and
the PR gate enforces exactly that: `check_variants_match_tags` re-derives the
set from the root's own tags and rejects any mismatch, in either direction.
Recompute it and you get the same answer: take every tag that parses as a
version, keep the ones carrying a prefix, sort and deduplicate the prefixes. It
is recorded so that reading "does this package ship variants" does not require
re-implementing the version grammar. `latest` is reserved and is never a
variant name.

Two consequences worth knowing:

- The default variant has no name. It is the *absence* of a prefix, so it never
  appears in this array — `variants: ["slim"]` on a package that also publishes
  `3.13.1` means two variants ship, the default and `slim`.
- A bare rolling tag (`slim`, no version) is not a version, so it contributes
  nothing on its own. It is legible as a variant pointer only alongside a
  versioned `slim-*` sibling — an inference the package page makes when it
  renders, and one this field does not make.

### Owner

| Field | Type | Required | Notes |
|---|---|---|---|
| `github` | string | yes | GitHub login — display only |
| `github_id` | integer, ≥1 | yes | numeric GitHub user id — the actual ownership key, survives username rename/recycling |

### Upstream

| Field | Type | Required | Notes |
|---|---|---|---|
| `org` | string | yes | the real vendor/project name |
| `repository_url` | string (URI) | no | upstream source repository |
| `disclaimer` | string \| null | no | e.g. a not-affiliated note |

#### Source versus upstream

Two different questions, deliberately two fields:

- `upstream.repository_url` — **who wrote the software.** Human-governed
  attribution of the third-party vendor the namespace names, set once in the
  claim PR.
- `source` — **who built these artifacts.** Bot-read from the published
  image's `org.opencontainers.image.source` annotation, so it names the
  repository whose CI ran the build.

For a mirror they are different repositories on purpose: `kitware/cmake` may
attribute `https://github.com/Kitware/CMake` upstream while its `source` is
the mirroring repository that produced the OCI artifacts.

### Desc

| Field | Type | Required | Notes |
|---|---|---|---|
| `digest` | `sha256:<hex>` | yes | digest of the currently-copied `__ocx.desc` tag |
| `title` | string | yes | |
| `description` | string | yes | |
| `keywords` | string[] | yes | from the `sh.ocx.keywords` annotation; `[]` if never published |
| `readme` | `sha256:<hex>` | no | CAS pointer, `o/sha256/<hex>.md` |
| `logo` | `sha256:<hex>` | no | CAS pointer, `o/sha256/<hex>.svg` or `.png` |

### TagEntry

| Field | Type | Required | Notes |
|---|---|---|---|
| `content` | `sha256:<hex>` | yes | digest of the OCI image index this tag resolved to, stored verbatim at `o/sha256/<hex>.json` |
| `observed` | date-time | yes | |
| `yanked` | [Yanked](#yanked) object | no | presence marks the row yanked; human-set only, bot never writes it |

### Yanked

| Field | Type | Required | Notes |
|---|---|---|---|
| `reason` | string | yes | |
| `at` | date-time | yes | |

## OCI Image Index — `/p/<namespace>/<package>/o/sha256/<hex>.json`

The bytes at this path are an
[OCI image index](https://github.com/opencontainers/image-spec/blob/v1.1.1/image-index.md),
stored verbatim as the physical registry served them — this index defines no
shape of its own here. The table below is a reading aid for the fields this
site and `ocx` actually consume; the
[OCI image-index schema](https://index.ocx.sh/schema/image-index.schema.json)
is deliberately **not** `additionalProperties: false` — a real index may
carry `subject`, `artifactType`, `annotations`, or future spec fields this
index does not author and must not reject.

| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | integer | yes | OCI image-index field, `2` |
| `mediaType` | string | yes | `application/vnd.oci.image.index.v1+json` |
| `manifests` | array of [ManifestDescriptor](#manifestdescriptor) | yes | one entry per platform build, plus zero or more non-platform artifacts (attestations, SBOMs, signatures) riding in the same index |

### ManifestDescriptor

| Field | Type | Required | Notes |
|---|---|---|---|
| `mediaType` | string | yes | |
| `digest` | `sha256:<hex>` | yes | OCI manifest digest on the physical registry |
| `size` | integer | yes | |
| `platform` | [Platform](#platform) object | no | **absent**, or present with `os`/`architecture` both `"unknown"`, on a non-platform descriptor (attestation, SBOM, signature). Consumers that enumerate platforms for display MUST exclude both cases |

### Platform

Inline subset of the [OCI image-spec `Platform` object](https://github.com/opencontainers/image-spec/blob/v1.1.1/image-index.md).
Field names with a literal dot (`os.version`, `os.features`) match the OCI
spec's own property names verbatim — not a nested `os` object.

| Field | Type | Required | Notes |
|---|---|---|---|
| `architecture` | string | yes | |
| `os` | string | yes | |
| `os.version` | string | no | |
| `os.features` | string[] | no | |
| `variant` | string | no | |
| `features` | string[] | no | |

## Field Provenance

Two disjoint sets, never cross-contaminated (see
[Governance Contracts](./governance-contracts) G-09):

- **Human-governed** (only changed by a merged PR): `name`, `repository`,
  `owners`, `status`, `deprecated_message`, `superseded_by`, `created`,
  `upstream`, and `tags[*].yanked`.
- **Bot-regenerated** (rewritten from registry truth on every
  announce/reconcile): `desc`, `source`, and the rest of every `tags[*]`
  row.
