# site/

[VitePress 2](https://vitepress.dev/) + [bun](https://bun.sh/) source for the
catalog + docs surface served at `index.ocx.sh`. Design authority:
[`adr_catalog_docs_colocation.md`](../.claude/artifacts/adr_catalog_docs_colocation.md)
(colocation decision) and
[`design_mock_site_redesign/`](../.claude/artifacts/design_mock_site_redesign/)
(visual/UX design — see that directory's `README.md` for provenance). Not the
wire contract — see
[`../.claude/rules/product-context.md`](../.claude/rules/product-context.md)
for what is.

## Layout

```
site/
├── package.json / bun.lock
├── .vitepress/
│   ├── config.mts          # site config: srcDir, dead-link scoping, Shiki
│   │                         #   theme, header extraction, own minimal
│   │                         #   themeConfig ({githubUrl, search})
│   └── theme/               # blank custom theme — see "Theme" below
├── src/
│   ├── index.md              # catalog home ("/") — frontmatter `layout: catalog`
│   ├── docs/                 # docs ("/docs/") — reference/, how-to/, ops/,
│   │                          #   explanation/, hand-authored + committed
│   ├── [ns]/[pkg].md         # detail-page template — frontmatter `layout: detail`
│   │                          #   only, no per-package content (see "Dynamic
│   │                          #   routes" below)
│   ├── [ns]/[pkg].paths.ts   # loader: discovers every `p/<ns>/<pkg>.json` at
│   │                          #   build time, one route per package
│   └── 404.md                 # near-empty; triggers 404.html emission
└── .gitignore
```

Catalog lives at the site root (`/`); docs live under `/docs/`. This is a
deliberate rescoping of ocx-sh/ocx's `website/` source theme, where docs own
the site root and the catalog is a nested route (`/catalog/`) — here the
catalog is the primary surface, so it gets the root.

## Commands

```sh
bun install          # from site/
bun run dev           # vitepress dev — local preview with HMR
bun run build          # vitepress build — emits .vitepress/dist/
bun run preview         # serve .vitepress/dist/ locally
```

From the repo root: `task site:build` (`cd site && bun install --frozen-lockfile
&& bun run build`) — this is the exact command `task verify` and `ci.yml`'s
`site-build` job run.

## Theme

`.vitepress/theme/` is a **blank custom theme** (`index.mts` exports
`{Layout, enhanceApp}`, no `extends: DefaultTheme`) — VitePress core still
supplies the pre-hydration `appearance` dark-class script, a writable
`isDark` ref, `page.headers`, free-form `themeConfig`, `<Content/>`, and
dynamic-route `params`; everything visual is this theme's own.

`Layout.vue` dispatches on frontmatter with a plain `v-if` chain (no global
component registration):

- `page.isNotFound` → `NotFound.vue`
- `frontmatter.layout === 'catalog'` → `CatalogPage.vue`
- `frontmatter.layout === 'detail'` → `DetailPage.vue`
- otherwise → `DocLayout.vue`

`SiteHeader.vue` and the global ⌘K `SearchModal.vue` render on every page,
outside the dispatch.

### Fetch layer (`theme/composables/`)

Runtime data comes from fetches inside the mounted components, never build-time
props — the same static pages serve empty-catalog and populated-catalog states:

- `useCatalog()` — fetches `/data/catalog/catalog.json` (see "Runtime catalog
  data" below); a 404 or any fetch failure degrades to
  `{generated: null, packages: []}`, never throws.
- `usePackageRoot(ns, pkg)` — fetches the wire root `/p/<ns>/<pkg>.json`; its
  TypeScript interface mirrors the wire field names 1:1 (snake_case, matching
  `schema/root.schema.json`); returns `{root, loading, error, notFound}`.
- `useObservation()` — lazy-fetches an observation object
  (`/p/<ns>/<pkg>/o/sha256/<hex>.json`) on demand, with a module-level cache
  keyed by digest and in-flight-request dedup.

CAS asset URLs (`casUrl()`, `utils/cas.ts`) always build from the bare
`<ns>/<pkg>` route params — never from `root.name`, which carries the
`ocx.sh/` prefix and 404s every CAS request built from it.

## Dynamic routes (per-package detail pages)

Per-package detail pages are a **dynamic route**, not bot-generated content.
`src/[ns]/[pkg].paths.ts` globs the committed `p/*/*.json` tree directly at
VitePress build time (`existsSync` guard, then one `{ns, pkg}` route per
`p/<ns>/<pkg>.json` file) and `src/[ns]/[pkg].md` carries only
`layout: detail` frontmatter — no per-package data lives in the source tree.
`DetailPage.vue` fetches everything it needs at runtime via the composables
above.

This replaces an earlier design (bot-emitted wrapper Markdown, one file per
package, gitignored compile input) — see
[`adr_catalog_docs_colocation.md`](../.claude/artifacts/adr_catalog_docs_colocation.md)
Amendment A1. The render pipeline (`core/render.py`) no longer emits any
`site/src/**` content; it writes only into the deployed dist tree (see
below).

## Runtime catalog data (`/data/catalog/catalog.json`)

**Not present in this source tree, ever.** `indexbot render` emits this file
directly into the *deployed* `.vitepress/dist/` tree, after the VitePress
build completes (`render-deploy.yml`, `task render:build` — build order is a
named footgun there: reversing the two steps silently deletes the wire JSON,
see `taskfile.yml`'s `render:build` task). No fixture data ships in `site/`
— it would deploy to production. Locally, `bun run dev`/`bun run build`
render the catalog and detail components against **no** data, and those
components degrade to a friendly empty/not-found state on a 404 fetch —
never a build failure — exactly as they do in production before the first
render pipeline run populates the tree.

This shape is **not** wire contract
([`adr_locked_observation_index_format.md`](../.claude/artifacts/adr_locked_observation_index_format.md)
D2) — it is free to evolve between deploys, unlike `/config.json` and
`/p/**`. Emitted by `core/render.py`'s `_catalog_index`/`_catalog_entry`;
verify against that module for the authoritative shape.

```jsonc
{
  "generated": "2026-07-17T00:00:00Z", // lexicographic max over every tag's
                                        // observed/yanked.at timestamp across
                                        // all packages; null if none ever observed
  "packages": [
    {
      "namespace": "kitware",
      "package": "cmake",
      "name": "ocx.sh/kitware/cmake",
      "status": "active",
      "deprecatedMessage": null,
      "supersededBy": null,
      "title": "CMake",
      "description": "Cross-platform build system generator.",
      "keywords": ["build", "cmake", "cpp"],
      "latestVersion": "3.28.1",
      "tagCount": 4,
      // union of "<os>/<architecture>" across every non-yanked tag's
      // observation object, deduped + sorted
      "platforms": ["linux/amd64", "linux/arm64"],
      // pre-resolved CAS paths (never a bare digest) — null when the
      // package has no desc.logo/desc.readme
      "logoUrl": "/p/kitware/cmake/o/sha256/<hex>.svg",
      "readmeUrl": "/p/kitware/cmake/o/sha256/<hex>.md"
    }
  ]
}
```

`keywords: []`, `logoUrl: null`, and `readmeUrl: null` are all valid (a
package with no `__ocx.desc` or no logo/readme layer) — the catalog UI
renders an empty/placeholder state for each.

Components reference `logoUrl`/`readmeUrl` as CAS URLs rather than duplicated
blob bytes (ADR's explicit divergence from `ocx-sh/ocx`'s website theme) —
this repo already has a reachability-filtered CAS copy at
`/p/<ns>/<pkg>/o/sha256/<hex>.<ext>`.

## Local design review

`task demo:serve` (repo root) chains `task demo:clean`, `task demo:seed`
(populates the gitignored `demo/p/` tree — never the real `p/` — with
throwaway packages from the bot's golden render fixtures plus
`scripts/demo-fixtures/`), and a render + serve pass over `demo/p/`
(`task render:build` with `RENDER_INDEX_DIR=demo/p`, then `bun run
preview`), serving the exact production-shaped dist tree — including
`/p/**`, `/c/index.json`, and `/data/catalog/catalog.json` — that Cloudflare
Pages would deploy. `src/[ns]/[pkg].paths.ts`'s route discovery prefers
`demo/p/` over the real `p/` whenever `demo/p/` exists on disk (a build-time
presence check, no flag/env var), so demo detail pages route the same way
real ones do. `demo/` is gitignored and `task
verify`'s pipeline never reads it, so no pre-verify cleanup is needed;
`task demo:clean` (`rm -rf demo/`) is only for discarding a stale local
preview.
