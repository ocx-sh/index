---
title: Wire Format
---

# Wire Format

The normative reference for the four frozen URL shapes served by the OCX
public index. This page documents semantics; the JSON Schemas are the source
of truth for exact field types and are linked, never duplicated, below.

## Requirement Language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they
appear in all capitals, as shown here.

## Scope

This is a **wire contract**: once an `ocx` client ships against these four
shapes, changes to them are additive-only, gated by `format_version`. See
[product-context.md](https://github.com/ocx-sh/index/blob/main/.claude/rules/product-context.md)
for the one-way-door rule. The following are explicitly **not** wire
contract, and MAY change shape between deploys without a `format_version`
bump: `/data/catalog/**` (catalog UI data) and `/`, `/docs/**` (this site).

## The Four Frozen URL Shapes

```
/config.json                                  format-version discovery document
/c/index.json                                 enumeration index (hot, mutable)
/p/<namespace>/<package>.json                 package root (hot, mutable)
/p/<namespace>/<package>/o/sha256/<hex>.json  OCI image indices (immutable, CAS)
/p/<namespace>/<package>/o/sha256/<hex>.{md,svg,png}  desc blobs (immutable, CAS)
```

CAS paths encode a `sha256:<hex>` digest by substituting `:` for `/` — the
same convention OCI registries use for their own blob storage
(`sha256:<hex>` ↔ `sha256/<hex>`). Every `content` reference in a root is an
OCI-style `sha256:<hex>` string — the digest of an OCI image index, exactly
as the physical registry serves it — and the corresponding CAS file path is
the same digest with `:` replaced by `/`.

### `/config.json`

```json
{ "format_version": 1 }
```

Schema: [`https://index.ocx.sh/schema/config.schema.json`](https://index.ocx.sh/schema/config.schema.json).

A fixed path convention, not a runtime-discoverable one: a client that
understands `format_version: 1` already knows the full `/p/` path grammar
without a URL template. There is no `packages` path prefix and no free-text
`note` field. See [Changelog](./changelog) for `format_version` history.

Clients MUST treat an unrecognised (higher) `format_version` as a hard
error requiring a client upgrade. Clients MUST ignore unknown JSON object
members anywhere else in the wire format — additive evolution is the only
kind this contract permits within one `format_version`.

### `/c/index.json` — enumeration index

Schema: [`https://index.ocx.sh/schema/c-index.schema.json`](https://index.ocx.sh/schema/c-index.schema.json).

```json
{
  "format_version": 1,
  "packages": {
    "kitware/cmake": "sha256:9f2c...",
    "ocx/cli": "sha256:1a2b..."
  }
}
```

`packages` is a map, sorted by key, from every published bare
`<namespace>/<package>` name to a digest. The key is not a URL fragment on
its own; a client derives the package root path by concatenation,
`/p/<key>.json`. The value is `sha256:` followed by the lowercase hex digest
of the **exact bytes** served at that root — a distinct digest namespace
from the `content` digests inside `tags` (D2/D4), which name the registry's
own image-index digest, never a digest this index computes itself. An empty
`packages` map is a valid, live index state.

This surface carries names and digests only — never `desc`, `status`, or any
other root field. A client MUST NOT treat presence in `packages` as a
substitute for fetching and validating the referenced root.

**Sync protocol:** clients SHOULD send `If-None-Match` on repeat fetches,
exactly as for any other path in this format (see Freshness below). A `304
Not Modified` means the package set and every root's exact bytes are
unchanged since the last fetch. On a `200` response, a client diffs the
previous `packages` map against the new one by key and by digest to derive
added, updated, and deleted packages, then fetches only the roots whose
digest changed. Image indices referenced by an unchanged root are
themselves immutable and MUST NOT be re-fetched.

`c` is a reserved top-level path segment (see [Namespace
Policy](./namespace-policy)): no namespace or package name MAY claim it.
Sharding this surface (a crates.io-style path-prefix split) is reserved as
future additive evolution under `/c/`, gated by `format_version` — not
needed at current scale.

### `/p/<namespace>/<package>.json` — package root

Schema: [`https://index.ocx.sh/schema/root.schema.json`](https://index.ocx.sh/schema/root.schema.json).
Full field table: [Entry Schema](./entry-schema).

The root is the **hot, mutable** part of an entry. It carries
governance fields set by a human via PR (`name`, `repository`, `owners`,
`status`, `deprecated_message`, `created`, `upstream`) alongside three
bot-regenerated fields:

- `desc` — nullable; title, description, keywords, and CAS pointers to a
  readme/logo, copied from the physical registry's `__ocx.desc` tag when its
  digest changes. `null` for a package that has never published one.
- `source` — optional; the `https://` repository whose CI produced the
  builds, read from the latest version's `org.opencontainers.image.source`
  annotation. Omitted when the published image carries no such annotation.
  Not the same thing as `upstream.repository_url` (see
  [Entry Schema](./entry-schema#source-versus-upstream)).
- `tags` — a map from **every** tag ever observed on the physical
  repository (no filtering) to `{content, observed, yanked?}`. `content` is
  a `sha256:<hex>` digest — the digest of the OCI image index that tag
  resolved to. Those exact bytes, as the physical registry served them, are
  stored at `o/sha256/<hex>.json` in this package's own CAS.

There is no declared `aliases` field. Two tags are aliases of each other
exactly when their `content` digests are equal — a read-time computation
over the `tags` map, never hand-maintained data.

### `/p/<namespace>/<package>/o/sha256/<hex>.json` — OCI image index

Schema: [`https://index.ocx.sh/schema/image-index.schema.json`](https://index.ocx.sh/schema/image-index.schema.json).

Immutable, package-local CAS. Holds the exact bytes a registry served for an
[OCI image index](https://github.com/opencontainers/image-spec/blob/v1.1.1/image-index.md)
— unmodified, byte-for-byte, at the moment a tag was observed to resolve to
it. `<hex>` is the sha256 of those bytes, which is also the registry's own
manifest digest for that index:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    { "mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:1111...", "size": 1234, "platform": { "architecture": "amd64", "os": "linux" } },
    { "mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:2222...", "size": 1234, "platform": { "architecture": "arm64", "os": "linux" } }
  ]
}
```

An index is a catalog of OCI artifacts. Tags are floating pointers by
definition — a tag is a name a registry may repoint at any time — and the
index's whole job is to **lock one**: to record exactly what a tag resolved
to at the moment it was observed, so a version choice made later resolves
to the same artifact, byte-for-byte, even after the registry has moved on.
The index therefore defines no object shape of its own here. Shape
definition is the OCI image spec's job; adherence to it is a
separation-of-concerns property, not a convenience.

The lock unit is the **image-index digest**, not any one platform's
manifest digest inside it — the per-platform manifest digests live inside
the locked bytes, in `manifests[]`, reachable without a second round trip.
Every field validation accepts is exactly what
[schema `additionalProperties`](https://index.ocx.sh/schema/image-index.schema.json)
allows: this index does not author these bytes, so an index carrying
`subject`, `artifactType`, `annotations`, or a spec field this page doesn't
enumerate validates fine — only structural shape (a real OCI image index)
is enforced.

**Two independent verification anchors**, not one: the object's own CAS
filename (`sha256(bytes) == <hex>`), and the physical registry, which SHOULD
serve byte-identical content for the same digest under
`GET /v2/<repository>/manifests/sha256:<hex>`. See
[Verifiability Chain](#verifiability-chain) below and
[Explanation: Architecture](../explanation/architecture) for why an index —
and not a platform manifest — is the thing this index snapshots.

`manifests[]` entries are not guaranteed to carry a `platform` object: an
attestation, SBOM, or signature descriptor riding in the same index has
`platform` **absent**, or set to the sentinel
`{"os":"unknown","architecture":"unknown"}`. Neither can satisfy a platform
selection, and both MUST be excluded from anything that *enumerates*
platforms for display (`ocx index list --platforms`, this site's platform
matrix) — they are not errors, they are ordinary OCI artifacts riding
alongside the platform builds in the same index.

## Verifiability Chain

```
root: tags[tag].content (sha256:<hex>, an image-index digest)
  → GET /p/<namespace>/<package>/o/sha256/<hex>.json
  → verify received bytes hash to <hex>               (index-CAS integrity)
  → OCI image index (verbatim) → manifests[].digest (sha256:<hex>, physical registry)
  → GET manifest from the physical repository at that digest
  → verify OCI CAS                                     (registry-CAS integrity)
```

A client resolving a package SHOULD verify both links in this chain rather
than trusting either digest opaquely — each is independently checkable
content-addressing, the index's own and the physical OCI registry's.

## Freshness

All wire-format paths are served over plain HTTPS with conditional-GET
support (`ETag` / `If-None-Match`). Clients SHOULD send `If-None-Match` on
repeat fetches and treat a `304 Not Modified` response as "no change since
last fetch" rather than re-parsing a body.

`/config.json`, `/c/index.json`, and every path under `/p/` MUST NOT be
served with a long CDN `max-age` — freshness depends on origin `ETag`s
reaching the client on every request (the repo-wide Cache Rule invariant).
Catalog data under `/data/catalog/**` and this documentation site carry no
such restriction — they are not wire contract and are free to use normal CDN
asset caching.

## Yank Semantics

`tags[tag].yanked` presence marks that row yanked — the OCI image index it
points at is never deleted or mutated (objects are immutable, see above). See [How-To: Yank a Version](../how-to/yank-a-version) for the
publisher-facing procedure.

## See Also

- [Entry Schema](./entry-schema) — full field table for the root and the
  OCI image index shape
- [Namespace Policy](./namespace-policy) — the `<namespace>/<package>`
  grammar and reserved segments
- [Changelog](./changelog) — `format_version`-keyed history
- [Explanation: Architecture](../explanation/architecture) — why this shape,
  narrative form
