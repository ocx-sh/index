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
/p/<namespace>/<package>/o/sha256/<hex>.json  observation objects (immutable, CAS)
/p/<namespace>/<package>/o/sha256/<hex>.{md,svg,png}  desc blobs (immutable, CAS)
```

CAS paths encode a `sha256:<hex>` digest by substituting `:` for `/` — the
same convention OCI registries use for their own blob storage
(`sha256:<hex>` ↔ `sha256/<hex>`). Every `content` reference in a root and
every `digest` reference inside an observation object is an OCI-style
`sha256:<hex>` string; the corresponding CAS file path is the same digest
with `:` replaced by `/`.

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
from the `content` digests inside `tags` (D2/D4), which hash a canonical
observation object, never the served root bytes. An empty `packages` map is
a valid, live index state.

This surface carries names and digests only — never `desc`, `status`, or any
other root field. A client MUST NOT treat presence in `packages` as a
substitute for fetching and validating the referenced root.

**Sync protocol:** clients SHOULD send `If-None-Match` on repeat fetches,
exactly as for any other path in this format (see Freshness below). A `304
Not Modified` means the package set and every root's exact bytes are
unchanged since the last fetch. On a `200` response, a client diffs the
previous `packages` map against the new one by key and by digest to derive
added, updated, and deleted packages, then fetches only the roots whose
digest changed. Observation objects referenced by an unchanged root are
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
`status`, `deprecated_message`, `created`, `upstream`) alongside two
bot-regenerated fields:

- `desc` — nullable; title, description, keywords, and CAS pointers to a
  readme/logo, copied from the physical registry's `__ocx.desc` tag when its
  digest changes. `null` for a package that has never published one.
- `tags` — a map from **every** tag ever observed on the physical
  repository (no filtering) to `{content, observed, yanked?}`. `content` is
  a `sha256:<hex>` digest addressing an observation object in this
  package's own CAS — not an OCI manifest or image-index digest.

There is no declared `aliases` field. Two tags are aliases of each other
exactly when their `content` digests are equal — a read-time computation
over the `tags` map, never hand-maintained data.

### `/p/<namespace>/<package>/o/sha256/<hex>.json` — observation object

Schema: [`https://index.ocx.sh/schema/observation-object.schema.json`](https://index.ocx.sh/schema/observation-object.schema.json).

Immutable, package-local CAS. Records the set of `platform → OCI manifest
digest` pairs observed at one point in time:

```json
{
  "platforms": [
    { "platform": { "architecture": "amd64", "os": "linux" }, "digest": "sha256:1111..." },
    { "platform": { "architecture": "arm64", "os": "linux" }, "digest": "sha256:2222..." }
  ]
}
```

Each `platform` object is an inline subset of the
[OCI image-spec `Platform` object](https://github.com/opencontainers/image-spec/blob/main/image-index.md).
Observation objects carry **no timestamps** — deliberately, for maximum
dedup: two observations that see an identical platform set produce
byte-identical JSON, hence the same digest, hence automatic storage as one
object regardless of how many tags or packages observed it. Objects are
never edited in place; an observed change is a new object at a new digest,
with the affected root's `tags[tag].content` repointed to it.

The lock unit is the **platform manifest digest**, never the image-index
digest — image indexes float by nature (platforms added, rolling tags
advance), so locking their digest would bake registry-side churn into every
consumer. See
[Explanation: Architecture](../explanation/architecture) for why.

## Verifiability Chain

```
root: tags[tag].content (sha256:<hex>, this index's CAS)
  → GET /p/<namespace>/<package>/o/sha256/<hex>.json
  → verify received bytes hash to <hex>              (index-CAS integrity)
  → object.platforms[].digest (sha256:<hex>, OCI manifest, physical registry)
  → GET manifest from the physical repository at that digest
  → verify OCI CAS                                    (registry-CAS integrity)
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

`tags[tag].yanked` presence marks that row yanked — the observation object
it points at is never deleted or mutated (objects are immutable, see
above). See [How-To: Yank a Version](../how-to/yank-a-version) for the
publisher-facing procedure.

## See Also

- [Entry Schema](./entry-schema) — full field table for the root and
  observation object
- [Namespace Policy](./namespace-policy) — the `<namespace>/<package>`
  grammar and reserved segments
- [Changelog](./changelog) — `format_version`-keyed history
- [Explanation: Architecture](../explanation/architecture) — why this shape,
  narrative form
