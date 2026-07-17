---
title: Entry Schema
---

# Entry Schema

Field-level reference for the two wire-format JSON shapes that carry package
data: the package root and the observation object. This page is a summary
table derived from the JSON Schemas below — the schemas are the source of
truth for exact types, patterns, and constraints; consult them directly for
anything this table simplifies.

- Root: [`https://index.ocx.sh/schema/root.schema.json`](https://index.ocx.sh/schema/root.schema.json)
- Observation object: [`https://index.ocx.sh/schema/observation-object.schema.json`](https://index.ocx.sh/schema/observation-object.schema.json)
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
| `repository` | string | yes | human (PR) | `oci://<host>/<repo path>`; host allowlisted at CI time |
| `owners` | array of [Owner](#owner) | yes, ≥1 item | human (PR) | |
| `status` | enum | yes | human (PR) | `active` \| `deprecated` \| `yanked` |
| `deprecated_message` | string \| null | yes | human (PR) | |
| `superseded_by` | string \| null | no | human (PR) | bare `<namespace>/<package>` naming a successor package, ≤140 chars; omitted or `null` when unset; self-reference invalid, no coupling to `status` |
| `created` | string, `YYYY-MM-DD` | yes | human (PR), set once | date first claimed |
| `upstream` | [Upstream](#upstream) object | no | human (PR) | mandatory by governance for third-party vendor namespaces; omitted for OCX first-party entries |
| `desc` | [Desc](#desc) object \| `null` | yes (nullable) | bot-regenerated | `null` if `__ocx.desc` never published |
| `tags` | map: tag name → [TagEntry](#tagentry) | yes | bot-regenerated, except `yanked` | every observed tag, no filtering |

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
| `content` | `sha256:<hex>` | yes | digest of the observation object in this package's own CAS |
| `observed` | date-time | yes | |
| `yanked` | [Yanked](#yanked) object | no | presence marks the row yanked; human-set only, bot never writes it |

### Yanked

| Field | Type | Required | Notes |
|---|---|---|---|
| `reason` | string | yes | |
| `at` | date-time | yes | |

## Observation Object — `/p/<namespace>/<package>/o/sha256/<hex>.json`

| Field | Type | Required | Notes |
|---|---|---|---|
| `platforms` | array of [PlatformEntry](#platformentry), ≥1 item | yes | no timestamps — identical platform sets dedup to one object |

### PlatformEntry

| Field | Type | Required | Notes |
|---|---|---|---|
| `platform` | [Platform](#platform) object | yes | |
| `digest` | `sha256:<hex>` | yes | OCI manifest digest on the physical registry |

### Platform

Inline subset of the [OCI image-spec `Platform` object](https://github.com/opencontainers/image-spec/blob/main/image-index.md).
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
  announce/reconcile): `desc` and the rest of every `tags[*]` row.
