# site/

[VitePress 2](https://vitepress.dev/) + [bun](https://bun.sh/) source for the
catalog + docs surface served at `index.ocx.sh`. Design authority:
[`adr_catalog_docs_colocation.md`](../.claude/artifacts/adr_catalog_docs_colocation.md).
Not the wire contract — see [`../.claude/rules/product-context.md`](../.claude/rules/product-context.md)
for what is.

## Layout

```
site/
├── package.json / bun.lock
├── .vitepress/
│   ├── config.mts          # nav, sidebar (scoped to /docs/ only), search, socialLinks
│   └── theme/               # WP2-O/WP2-P: ported + adapted catalog components
├── src/
│   ├── index.md             # catalog home ("/") — hero only today, gains
│   │                         #   embedded <PackageCatalog /> in WP2-P
│   ├── docs/                # docs ("/docs/") — reference/, how-to/, ops/,
│   │                         #   explanation/; stub index pages today, real
│   │                         #   content lands in WP2-Q
│   └── <namespace>/<pkg>.md # per-package wrapper pages — GENERATED, gitignored,
│                             #   see "Generated pages" below
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

## Generated pages (render-time contract)

Per-package wrapper pages (`src/<namespace>/<package>.md`) are **compile
input** to the VitePress build, not build output — they must exist on disk
*before* `bun run build` runs. They are emitted by the bot's render pipeline
(`core/render`, WP2-F) and are never committed: `.gitignore` ignores
everything directly under `src/` except the hand-authored `docs/` tree and
`index.md` (an explicit allowlist, since namespace directory names are
dynamic — see the `.gitignore` comment for why a glob doesn't work here).

Each wrapper page is expected to embed a `<PackageDetail />` component (see
`adr_catalog_docs_colocation.md`) that fetches its own runtime data — the
wrapper page itself carries no package data, only routing + any
hand-authored prose a publisher wants alongside the generated detail view
(see `src/catalog/cmake.md` in the source theme for the pattern being
adapted).

## Runtime catalog data (`/data/catalog/**`)

**Not present in this source tree, ever.** Per `adr_catalog_docs_colocation.md`
and the plan's frozen site contract, `/data/catalog/**` is emitted by the
render pipeline directly into the *deployed* `.vitepress/dist/` tree, after
the VitePress build completes (`render-deploy.yml`, WP3-A — build order is a
named footgun there: reversing the two steps silently deletes the wire
JSON). No fixture data ships in `site/public/` or `site/src/public/` — it
would deploy to production. Locally, `bun run dev`/`bun run build` render
the catalog and package-detail components against **no** data, and those
components (ported in WP2-O/WP2-P) MUST degrade to a friendly empty state on
a 404 fetch — never a build failure — exactly as they do in production
before the first render pipeline run populates the tree.

### Shape (today, in the source theme — what render will emit here)

This is what `ocx-sh/ocx`'s `website/.vitepress/theme/components/PackageCatalog.vue`
and `PackageDetail.vue` consume **today**, captured here as the target shape
`core/render` (WP2-F) implements. One deliberate divergence from the source
theme, per the ADR: **no blob duplication**. The source theme copies
logo/readme bytes into `/data/catalog/packages/<name>/logo.<ext>`; this repo
already has a reachability-filtered CAS copy at
`/p/<ns>/<pkg>/o/sha256/<hex>.<ext>` (see
[`adr_locked_observation_index_format.md`](../.claude/artifacts/adr_locked_observation_index_format.md)),
so components reference that CAS URL directly instead of a second copy.

`GET /data/catalog/catalog.json`:

```jsonc
{
  "generated": "2026-07-17T00:00:00Z",
  "registry": "ocx.sh",
  "packages": [
    {
      "name": "kitware/cmake",
      "registry": "ocx.sh",
      "repository": "oci://ghcr.io/ocx-contrib/cmake",
      "title": "CMake",
      "description": "Cross-platform build system generator.",
      "keywords": ["build", "cmake", "cpp"],
      // Divergence from the source theme's hasLogo/logoExt pair: a CAS
      // digest (or null) the component turns into
      // /p/<ns>/<pkg>/o/sha256/<hex>.<ext> directly — no separate ext field
      // needed once the URL is fully self-describing.
      "logo": "sha256:3c4d...",
      "hasReadme": true,
      "tagCount": 4,
      "platforms": ["linux", "darwin", "windows"],
      "latestTag": "3.28.1",
      "latestVersion": "3.28.1"
    }
  ]
}
```

`GET /data/catalog/packages/<ns>/<pkg>/info.json`:

```jsonc
{
  "name": "kitware/cmake",
  "registry": "ocx.sh",
  "repository": "oci://ghcr.io/ocx-contrib/cmake",
  "title": "CMake",
  "description": "Cross-platform build system generator.",
  "keywords": ["build", "cmake", "cpp"],
  "logo": "sha256:3c4d...",
  "hasReadme": true,
  "latestTag": "3.28.1",
  "latestVersion": "3.28.1",
  "tags": ["3.28.1", "3.28", "3", "latest"],
  "platforms": ["linux", "darwin", "windows"]
}
```

`keywords: []` and `logo: null` are valid (a package with no `__ocx.desc` or
no logo layer) — the catalog UI must render an empty/placeholder state for
both, per plan risk 6.

This shape is **not** wire contract (`adr_locked_observation_index_format.md`
D2) — it is free to evolve between deploys, unlike `/config.json` and
`/p/**`.
