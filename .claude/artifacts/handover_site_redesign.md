# Handover: index.ocx.sh Site Redesign

**Audience:** a Claude Designer instance. **Goal:** propose a full visual +
UX design for the OCX package index website. The current site works but was
assembled from an inherited docs theme and looks like it — the owner wants a
ground-up design, which we will then re-implement against the data contracts
below. Design freely; the wire/data contracts are the only hard walls.

## What this product is

The **OCX public package index** at `https://index.ocx.sh` — the browsable
face of [OCX](https://github.com/ocx-sh/ocx), an OCI-backed package manager
for developer CLI tools (think: crates.io or brew.sh, but packages are OCI
artifacts). Users are developers deciding whether a tool exists in the index
and how to install it. The site is fully static (Cloudflare Pages, no
server, no API): the UI fetches JSON from the same origin at runtime.

A package is identified as `<namespace>/<package>` where the namespace is
the upstream vendor's identity (`kitware/cmake`, `astral-sh/uv`,
`oven-sh/bun`, `cli/gh`). Install command users copy:
`ocx install ocx.sh/<namespace>/<package>`.

## Owner's brief (requirements, verbatim intent)

1. **The root page (`/`) IS the catalog — nothing else.** No hero, no
   marketing panel, no docs chrome. Instant focus on available packages and
   finding them.
2. **Search is primary.** Plus filters: keywords at minimum; platforms,
   namespace, status are natural extensions ("and so forth").
3. **Docs stay** at `/docs/**` (13 Diátaxis pages: reference / how-to / ops /
   explanation). They may be re-skinned to match, but their content and
   structure stand.
4. Per-package **detail pages** exist at `/<namespace>/<package>` (one per
   package, statically generated shells that fetch their data at runtime).

## Data the design must display

### Catalog list — `GET /data/catalog/catalog.json`

One entry per package:

| Field | Type | Notes |
|---|---|---|
| `name` | `"kitware/cmake"` | namespace/package — the primary identifier |
| `title` | `"CMake"` | display name; may be null → fall back to name |
| `description` | string \| null | one-liner |
| `keywords` | string[] | may be `[]` — filter source |
| `logo` | CAS digest \| null | resolves to `/p/<ns>/<pkg>/o/sha256/<hex>.<svg|png>`; null → placeholder needed |
| `platforms` | string[] | e.g. `["linux","darwin","windows"]` — filter source |
| `latestVersion` / `latestTag` | string | headline version |
| `tagCount` | number | breadth signal |
| `hasReadme` | bool | detail page has a README |
| `repository` | `oci://ghcr.io/...` | physical registry (secondary info) |

### Package detail — `GET /data/catalog/packages/<ns>/<pkg>/info.json`

Everything above plus `tags: string[]` (all observed tags). The detail view
additionally draws from the package's wire root (`/p/<ns>/<pkg>.json`):

- `owners[]` (GitHub logins) — who governs the entry
- `upstream {org, repository_url?, disclaimer?}` — attribution for mirrored
  packages; **when `disclaimer` is present it must be visibly displayed**
  (governance obligation, e.g. "not affiliated with the upstream vendor")
- `status` / `deprecated_message` — deprecated packages need a clear badge
- per-tag yank state (`yanked {reason, at}`) — yanked versions shown
  struck/annotated, excluded from "latest"
- version tree: tags group naturally by semver precision
  (`3` → `3.28` → `3.28.1` share content digests; equal digest = alias)
- platform-per-version detail (from observation objects; each version knows
  its exact OCI platforms)
- README (markdown, CAS URL) and logo (SVG or PNG, CAS URL)

### States that must be designed

- **Empty catalog** (live today — seeds land later): friendly, not broken.
- **Loading** (runtime fetch on a static page).
- Package without logo / without keywords / without README (all valid).
- Deprecated package; yanked version rows.
- Scale: design for ~44 packages now, sensible at 500+ (search-first helps).

## Current implementation (context, not a constraint)

VitePress 2 + Vue 3 + bun in `site/`. Components ported from the sibling
ocx website theme: `PackageCatalog` (grid + client-side search),
`PackageDetail`, `VersionTree`, `TagBadge`, `PlatformIcons`, `CopySnippet`,
`HomeLayout`. The owner's verdict on the result: awful — an inherited docs
theme wearing a catalog costume. Treat existing components as a data-flow
reference only; do not preserve their look.

Live reference: <https://index.ocx.sh> (empty catalog + docs today).
Repo: `ocx-sh/index`, `site/` dir; data contract detail in `site/README.md`;
design-decision record in `.claude/artifacts/adr_catalog_docs_colocation.md`.

## Hard constraints

- **Static only.** No server, no external API. Runtime data = same-origin
  JSON fetches listed above.
- **Self-contained assets.** No external CDNs/fonts/trackers. Inline or
  bundle everything; logos come from same-origin CAS URLs.
- **Light + dark** theme.
- **Responsive** — developers on wide monitors and phones.
- The install command (`ocx install ocx.sh/<ns>/<pkg>`) deserves first-class
  copy affordance on detail pages (and possibly on catalog cards).
- Docs remain VitePress-rendered markdown; the docs skin should cohere with
  the new design but VitePress's markdown rendering stays.
- Tech for the catalog root is otherwise open: the re-implementation can
  replace the VitePress theme layer entirely (Vue components inside
  VitePress, or a standalone static page for `/` — implementer's choice
  driven by your design).

## Asks (deliverables from the Designer)

1. Visual direction: typography, color system (light/dark), density,
   iconography — a personality that says "fast developer tool index".
2. Root catalog layout: search placement + behavior, filter UI (keywords,
   platform, namespace, status), card/row anatomy, result counts, empty +
   loading states.
3. Package detail layout: identity block (logo/title/attribution/badges),
   install command, version tree with yank/alias states, platform display,
   README region, owners/upstream metadata.
4. Docs skin direction (VitePress-compatible: sidebar, prose styles).
5. Component inventory + responsive behavior notes, enough for a clean
   re-implementation without guessing.

## Out of scope for design

Wire JSON shapes (`/config.json`, `/p/**` — frozen contract), docs content,
build pipeline, URL structure (`/`, `/docs/**`, `/<ns>/<pkg>`).
