# site/

Consumer-facing content for the catalog + docs surface served at
`index.ocx.sh`. The catalog theme itself (build engine, VitePress theme,
view-model emitter) has been extracted into
[`@ocx-sh/catalog`](https://github.com/ocx-sh/catalog) — see that package's
own README for the theme, config schema, and CLI. This directory now holds
only what a consumer of that package supplies: hand-authored docs and static
assets. Not the wire contract — see
[`../.claude/rules/product-context.md`](../.claude/rules/product-context.md)
for what is.

## Layout

```
site/
├── src/
│   ├── docs/     # docs ("/docs/") — reference/, how-to/, ops/,
│   │              #   explanation/, hand-authored + committed
│   └── public/   # static assets copied verbatim to the site root
│                  #   (favicon.svg -> /favicon.svg)
└── .gitignore    # .vitepress/dist/ (build output), node_modules/
```

Everything else the old in-repo theme owned — VitePress config, the blank
custom theme (`Layout.vue`, catalog/detail/docs components), per-package
dynamic routes — moved verbatim into `@ocx-sh/catalog`'s `src/theme/` and
`src/build/`. `site/.vitepress/` now holds nothing but the build **output**
directory (`dist/`) — `render-deploy.yml` and `indexbot render --out` still
target `site/.vitepress/dist` exactly as before, so neither needed to change.

## How this repo builds through the package

The repo root carries `catalog.config.json` (the package's config file —
`sources: [{path: ".", root: true}]`, so the package reads the committed
`p/**` tree as its own self-mirrored index) and `package.json`
(`@ocx-sh/catalog: ^0.1.0`, from npm). From the repo root:

```sh
task site:build   # `ocx-catalog build --config catalog.config.json --out site/.vitepress/dist`
task render:build # site:build, then `indexbot render --out` (adds config.json/c/index.json —
                   #   optional per source, absent from the raw committed p/** tree the package reads)
task site:dev      # `ocx-catalog dev` — live wire data from the same config, HMR
task cat:dev       # iterate on @ocx-sh/catalog: build ../ocx-catalog, render via its CLI, serve :4173
                   #   CATALOG_DEV=1 (any task's CLI, or a gitignored .env.local) switches to the sibling
```

`docs` and `publicDir` in `catalog.config.json` point at `./site/src/docs`
and `./site/src/public` respectively (relative to the config file, i.e. the
repo root) — that's the only place this directory's layout is wired in.

## Local design review

`task demo:serve` (repo root) chains `task demo:clean`, `task demo:seed`
(populates the gitignored `demo/p/` tree — never the real `p/` — with
throwaway packages from the bot's golden render fixtures plus
`scripts/demo-fixtures/`), and a render + serve pass over `demo/p/`
(`task render:build RENDER_INDEX_DIR=demo`, then `task site:preview`),
serving the exact production-shaped dist tree Cloudflare Pages would
deploy. `RENDER_INDEX_DIR=demo` swaps `catalog.config.json`'s configured
source from `.` to `demo` for that one build (see `taskfile.yml`'s
`site:build` task) and forwards the same override to `indexbot render
--index-dir`. `demo/` is gitignored and `task verify`'s pipeline never
reads it, so no pre-verify cleanup is needed; `task demo:clean` (`rm -rf
demo/`) is only for discarding a stale local preview.
