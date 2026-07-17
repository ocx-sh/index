# ADR: Catalog + Docs Colocated on index.ocx.sh, VitePress Reuse

## Metadata

**Status:** Accepted
**Date:** 2026-07-17 (decision discussion: 2026-07-16)
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** frontend | infrastructure | devops
**Supersedes:** N/A — reverses the tooling recommendation of
[`research_docs_site.md`](./research_docs_site.md) (see Industry Context & Research)

## Context

The index needs a human-facing surface: a browsable catalog (package list, version
trees, platform badges, per-package detail pages) and versioned docs (wire-format
reference, entry-schema field table, namespace policy, `announce-a-package` how-to,
`format_version` changelog). None of this may touch the frozen wire contract —
[`product-context.md`](../rules/product-context.md) locks `/config.json` and
`/p/<namespace>/<package>.json` shapes as a one-way door once ocx clients bake the
endpoint.

[`research_docs_site.md`](./research_docs_site.md) (2026-07-16) researched this in
isolation from the catalog and recommended [mdBook](https://rust-lang.github.io/mdBook/)
on a second Cloudflare Pages project (`ocx-docs`, `docs.ocx.sh`). That research did not
have the catalog requirement in scope. Once the catalog need — interactive version
trees, tag badges, platform icons, copy-snippets, per-package detail pages — entered
the picture, and once it became clear a sibling repo (`ocx-sh/ocx`'s `website/`
directory) already ships a working Vue-based catalog theme against the same package
data shape, the docs-only recommendation stopped being the cheapest path. This ADR
records the reversal and the resulting design.

## Decision Drivers

- The catalog is not static prose: version trees, tag badges, platform icons, and
  copy-snippets are interactive components, not rendered Markdown.
- A working theme with exactly these components already exists and is already paid
  for one repo over (`ocx-sh/ocx`'s `website/`) — reuse beats a second build.
- Docs content (entry-schema field tables, wire-format reference, `format_version`
  changelog) must version with this repo's own schema and render-pipeline commits,
  not a separate repo's release cadence.
- One canonical identity for `index.ocx.sh`: wire JSON, catalog, and docs under one
  deploy artifact, one DNS record, one Cloudflare Pages project — not two surfaces
  users have to know about.
- The Cache Rule invariant (never cache `*.json` on the index zone) must survive
  colocation without collaterally blocking normal CDN caching of the new HTML/CSS/JS
  and catalog-data assets.

## Industry Context & Research

**Research artifact:** [`research_docs_site.md`](./research_docs_site.md)

That research surveyed [mdBook](https://rust-lang.github.io/mdBook/), MkDocs Material
(entered maintenance mode 2025-11-11), [Zensical](https://github.com/zensical/zensical)
(too new), [Astro Starlight](https://github.com/withastro/starlight) (extra toolchain
token, no need), and [Read the Docs](https://about.readthedocs.com/) (third-party
vendor, no added capability) — purely for prose documentation. It correctly picked the
boring option for that narrower scope. It did not evaluate the catalog requirement,
because the catalog wasn't yet framed as living on this domain at all.

**Key insight driving the reversal:** the deciding cost is not "which docs generator,"
it is "how many toolchains does this repo carry for its human-facing surface." mdBook
is a second, unrelated toolchain (a Rust binary, in a repo that has no Rust anywhere
else — see `.claude/rules.md` "Not ported") that still leaves the catalog needing a
third, separate build step for its Vue components. [VitePress](https://vitepress.dev/)
is one toolchain that satisfies both docs and catalog, and the catalog half of it is
not new work — it is a port.

## Considered Options

### Option A: VitePress 2 colocated on index.ocx.sh (chosen)

**Description:** [VitePress 2](https://vitepress.dev/) + [bun](https://bun.sh/) in a
new `site/` directory. Catalog at `/`, docs at `/docs`. Single Cloudflare Pages project
(`ocx-index`), single canonical domain (`index.ocx.sh`). Reuses the `ocx-sh/ocx`
website catalog theme verbatim/adapted.

| Pros | Cons |
|---|---|
| Reuses a proven, already-built theme (7 components + `utils/version.ts`) instead of building catalog UI from zero | Adds a JS/bun/VitePress toolchain to a repo that otherwise ships only Python (bot) + GitHub Actions |
| One Pages project, one deploy, one canonical domain for wire JSON + catalog + docs | Render pipeline gains a second output-tree write phase after the VitePress build — a new footgun class (see Technical Details) |
| Docs content versions with this repo's own schema/render commits, same PR | Cache Rule must be re-scoped from an (accidentally-correct) zone-wide `*.json` match to a path-scoped one |
| Catalog gets real interactivity (version trees, tag badges, platform icons) that static Markdown cannot express | |

### Option B: mdBook (research recommendation)

**Description:** [mdBook](https://rust-lang.github.io/mdBook/), Diátaxis-structured
`docs/src/`, second Cloudflare Pages project.

| Pros | Cons |
|---|---|
| Single statically-linked binary, zero language toolchain committed to the repo | No component/Vue system — the catalog's version trees, tag badges, and platform icons would need hand-rolled JS bolted onto rendered HTML, rebuilding what the sibling theme already solved |
| Thematically aligned with the crates.io/Cargo lineage this index's format borrows from | Introduces a second, unrelated toolchain (a Rust binary) for a repo with no Rust anywhere else |
| Native search, `mdbook-mermaid` covers diagrams | Solves only the docs half of the problem — the catalog still needs an entirely separate build tool |

### Option C: mdBook docs on a separate `docs.ocx.sh` Pages project

**Description:** The research's paired hosting recommendation — new `ocx-docs` Pages
project, new `docs-deploy.yml` cloning the domain-activation pattern from
`deploy.yml`.

| Pros | Cons |
|---|---|
| Clean separation: docs deploy never touches the wire-JSON deploy pipeline | Two deploys to keep in sync (`render-deploy.yml` + `docs-deploy.yml`) |
| Docs caching policy can differ from the index zone with zero scoping concern | Split identity — users bounce between `index.ocx.sh` (machine + catalog) and `docs.ocx.sh` (docs) |
| | Still doesn't answer where the catalog UI lives — a third surface would be needed |

### Option D: Docs inside the ocx.sh website repo

**Description:** Land docs content in `ocx-sh/ocx`'s `website/` (or a future
marketing-site repo), next to the catalog theme it already owns.

| Pros | Cons |
|---|---|
| One home for all human-facing OCX content already exists; zero porting of the theme into this repo | Index docs (entry-schema tables, wire-format reference, `format_version` changelog) would version against the marketing website's release cadence, not this repo's own schema commits — the two are not the same clock |
| | Every schema change becomes a cross-repo PR |
| | Couples this repo's frozen wire contract to a different repo's deploy cycle |

## Decision Outcome

**Chosen Option:** A — VitePress 2 + bun in `site/`, colocated on `index.ocx.sh`,
single Cloudflare Pages project (`ocx-index`), catalog at `/`, docs at `/docs`.

**Rationale:** The research recommendation was sound for the question it was asked,
but the question changed once the catalog's component requirement was in scope. Once
a Vue-based static-site generator is needed for the catalog regardless of which tool
renders the docs, keeping docs on a *different* tool (mdBook) or a *different* repo
buys no simplicity — it only adds a second toolchain or a second deploy. The theme
this decision reuses is not hypothetical: it already exists, already renders this
exact data shape, one repo over. Reuse is the boring choice here, not the novel one.

### Consequences

**Positive:**
- One Pages project, one deploy pipeline, one canonical domain serving wire JSON,
  catalog, and docs.
- Catalog reuses tested components — `VersionTree`, `TagBadge`, `PlatformIcons`,
  `CopySnippet` ported verbatim; `PackageCatalog`, `PackageDetail`, `HomeLayout`
  adapted; `utils/version.ts` and `custom.css` ported verbatim. Seven components,
  not reinvented.
- Docs content versions with this repo's own schema and render-pipeline commits —
  no cross-repo PR required for a schema change.
- Components reference logos/READMEs via their CAS URL
  (`/p/<ns>/<pkg>/o/sha256/<hex>.<ext>`) instead of duplicating blob content into
  `/data/catalog/**` — a deliberate divergence from `ocx-sh/ocx`'s website, where the
  index's own reachability-filtered CAS copy already makes the blob available at a
  stable path.

**Negative:**
- The repo now carries two runtime toolchains for its two human-facing/machine
  surfaces (Python for `bot/`, bun/VitePress for `site/`) instead of one.
- The render pipeline gains a second output-tree write phase that must run strictly
  after the VitePress build (see Technical Details) — absent under the current
  verbatim-`public/`-copy deploy.
- The Cache Rule needs re-scoping work: it was accidentally correct when the whole
  zone was JSON-only (`public/config.json` + `public/index.html`); colocation makes
  a blanket `*.json` match wrong.

**Risks:**
- **`emptyOutDir` ordering.** [VitePress](https://vitepress.dev/)'s build defaults to
  `emptyOutDir: true`. If a future edit to `render-deploy.yml` reorders the wire-JSON
  emission step ahead of the VitePress build step, the wire JSON is silently deleted
  on the next deploy. Mitigation: a loud inline comment in `render-deploy.yml`
  (Phase 3, WP3-A) plus a `smoke-test.sh` guard that asserts `config.json` returns 200
  post-deploy (Phase 2, WP2-V).
- **Cache Rule scope drift.** If the Cloudflare Cache Rule is later edited back to a
  zone-wide `*.json` match (dashboard or future IaC), catalog-data caching regresses
  silently (a performance issue) while wire-JSON caching regression would violate the
  freshness contract in `product-context.md` (a correctness issue). Mitigation:
  `smoke-test.sh` asserts no long `max-age` specifically on wire-JSON paths.

## Technical Details

### Wire-path map (canonical — reproduced from `plan_index_v1.md`)

```
/config.json                          {"format_version": 1}          ← generated, frozen contract
/p/<ns>/<pkg>.json                    package root (hot, mutable)    ← frozen contract
/p/<ns>/<pkg>/o/sha256/<hex>.json     observation objects (CAS)      ← frozen contract
/p/<ns>/<pkg>/o/sha256/<hex>.{md,svg,png}  desc blobs (CAS)
/data/catalog/**                      catalog UI data — NOT wire contract, free to evolve
/, /docs/**                           VitePress catalog + docs — NOT wire contract
```

`/data/catalog/**` and `/, /docs/**` are explicitly not part of the wire contract —
they may change shape freely between deploys, unlike the frozen paths above. This is
why `docs` and `data` are on the reserved-namespace-segment list in
[`adr_namespace_policy.md`](./adr_namespace_policy.md) (control paths, alongside `p`,
`o`, `assets`, `config`, `schema`, `api`, `static`): a package namespace can never
collide with these routes.

### `site/` layout

```
site/                                # VitePress 2 + bun source (committed)
├── package.json / bun.lock
├── .vitepress/
│   ├── config.mts                   # nav, sidebar rescoped "/" (docs) → "/docs/",
│   │                                #   socialLinks kept, groupIcon customIcons dropped,
│   │                                #   local search (no third-party search vendor)
│   └── theme/
│       ├── components/
│       │   ├── VersionTree.vue          # verbatim port
│       │   ├── TagBadge.vue             # verbatim port
│       │   ├── PlatformIcons.vue        # verbatim port
│       │   ├── CopySnippet.vue          # verbatim port
│       │   ├── PackageCatalog.vue       # adapted: route prefix /catalog/ → /
│       │   ├── PackageDetail.vue        # adapted: CAS img/readme refs, upstream-disclaimer badge
│       │   └── HomeLayout.vue           # adapted: hero + embedded catalog, DevBanner stripped
│       ├── utils/version.ts             # verbatim port
│       ├── custom.css                   # verbatim port
│       └── index.mts                    # trimmed to this catalog component set
├── src/
│   ├── index.md                     # catalog home, VitePress "/"
│   ├── docs/                        # ~13 committed pages: reference/, how-to/, ops/, explanation/
│   └── <ns>/<pkg>.md                # per-package wrapper pages, generated at render time — gitignored, never committed
└── .gitignore                       # site/src/<ns>/**, .vitepress/dist, .vitepress/cache
```

Per-package wrapper pages are compile *input* to the VitePress build, not output —
they must exist before the build runs, which is why `render`'s wrapper-page emission
target is `site/src/**`, distinct from its wire-JSON emission target (below).

### Build pipeline order (the footgun to record)

`render-deploy.yml` (Phase 3, WP3-A) must sequence exactly:

1. `indexbot render` — reachability-filtered copy of the `p/` source tree; emits
   per-package wrapper Markdown into `site/src/**` (gitignored, VitePress compile
   input).
2. `bun run docs:build` in `site/` — VitePress compiles `site/src` →
   `site/.vitepress/dist`. Default `emptyOutDir: true` wipes `dist` clean first.
3. `indexbot render`'s second emission target — `config.json`, `/p/**`,
   `/data/catalog/**` (with CAS refs, not duplicated blobs) — writes directly into
   `site/.vitepress/dist`, **only after** step 2 completes.
4. `wrangler pages deploy site/.vitepress/dist --project-name=ocx-index`.

Reversing steps 2 and 3 silently deletes the wire JSON on the next deploy
(`emptyOutDir` has no knowledge of files written by an earlier, unrelated process).
WP3-A records this as a loud inline comment in the workflow, not tribal knowledge.

### Cache Rule scoping requirement

`product-context.md`'s invariant — "never enable Cloudflare caching for `*.json` on
the index zone" — was accidentally correct under the bootstrap deploy, because the
entire `public/` tree was `config.json` + `index.html`; a bare `*.json` match and a
path-scoped match were equivalent. Colocation breaks that equivalence: `/data/catalog/
**/*.json` is catalog UI data, not wire contract, and should be allowed to
participate in normal Cloudflare Pages asset caching like any other build output.

The Cache Rule (dashboard-configured today; candidate for future IaC) must therefore
match on **path**, not file extension:

- Never-cache scope: `/config.json`, `/p/*` (prefix match covering `/p/<ns>/<pkg>.json`
  and the CAS objects under it).
- Everything else on the zone — `/`, `/docs/**`, `/data/catalog/**`,
  `/.vitepress/**` assets — is free to use Cloudflare Pages' normal asset-caching
  behavior.

A zone-wide `*.json` rule would still satisfy the letter of the wire-contract
invariant but would needlessly defeat CDN caching for catalog data that has no
freshness requirement.

## Implementation Plan

Tracked in [`plan_index_v1.md`](../state/plans/plan_index_v1.md); not re-decomposed
here.

1. [ ] WP2-N: `site/` scaffold — `package.json`, `bun.lock`, `.vitepress/config.mts`.
2. [ ] WP2-O: verbatim component ports — `VersionTree`, `TagBadge`, `PlatformIcons`,
   `CopySnippet`, `utils/version.ts`, `custom.css`.
3. [ ] WP2-P: adapted components — `PackageCatalog`, `PackageDetail`, `HomeLayout`,
   trimmed `theme/index.mts`.
4. [ ] WP2-Q: ~13 docs pages (reference/, how-to/, ops/, explanation/).
5. [ ] WP2-R: inline CC0/hand-drawn CTA icon SVGs.
6. [ ] WP2-F (bot side): `core/render` — reachability-filtered copy, `config.json`
   emission, `/data/catalog` emission with CAS refs, wrapper-page emission.
7. [ ] WP3-A: `render-deploy.yml` replacing `deploy.yml` — build order fixed per
   Technical Details, SHA-pinned actions, schema-validate on rendered output,
   domain self-activation block ported verbatim, smoke job.
8. [ ] WP3-B: retire tracked `public/` in the same PR as WP3-A — no half-state.
9. [ ] Cloudflare Cache Rule re-scoped to path-scoped match (dashboard action,
   tracked as an ops item; not a code change in this repo).

## Validation

- [ ] `bun run docs:build` succeeds standalone against `site/` fixture content.
- [ ] `render-deploy.yml` dry run confirms build order: VitePress build completes
      before `indexbot render`'s dist-targeted emission runs.
- [ ] `schema:validate:rendered` (taskfile) passes against the deployed output tree.
- [ ] `scripts/smoke-test.sh` (WP2-V) green: `config.json` 200 + ETag + no long
      `max-age`, sample package root resolves, `/` (catalog) 200, `/docs` 200.
- [ ] Cache Rule match expression manually reviewed against the path-scoped
      requirement above before first colocated production deploy.

## Amendments

### Amendment A1 (2026-07-17): Dynamic Routes Replace Bot-Generated Wrapper Pages

**Status:** Accepted — landed in `plan_site_redesign` Waves 1–2 (PRs #21–#26,
merged), recorded here in Wave 3 (WP-docs).

**Problem.** This ADR's original design (Technical Details, `site/` layout
above) had `core/render.py` emit one bot-generated wrapper Markdown file per
package (`site/src/<ns>/<pkg>.md`, gitignored, VitePress compile *input*)
ahead of the VitePress build, embedding a `<PackageDetail />` component that
fetched its own runtime data. `plan_site_redesign`'s Designer-handover
redesign (`handover_site_redesign.md`, brief; PR #18 return) re-implemented
`site/` against a new visual design and, in doing so, exposed that the
wrapper-page step existed only to give VitePress a route to build against —
it carried no package data of its own, only routing. VitePress 2's own
dynamic-route mechanism (`defineRoutes`/`.paths.ts` loaders, confirmed
against the installed `vitepress@2.0.0-alpha.18` resolver) can derive that
same routing directly from the committed `p/` source tree, at build time,
with no bot-emitted intermediate file.

**Resolution.** `site/src/[ns]/[pkg].paths.ts` globs `p/*/*.json` at
VitePress build time and produces one `{ns, pkg}` route per package root
found; `site/src/[ns]/[pkg].md` carries only `layout: detail` frontmatter,
no per-package content. `DetailPage.vue` fetches everything at runtime via
the same composable fetch layer the catalog already uses (`usePackageRoot`,
`useObservation`) — see `site/README.md`. `core/render.py`'s
`build_render_plan` now returns a single flat `tuple[FileWrite, ...]`
(`config.json`, `/p/**`, `/c/index.json`,
`/data/catalog/catalog.json`) rather than the two-tree `RenderPlan`
(`wrapper_pages` + `dist_files`) this ADR originally specified;
`core/catalog_md.py` (the wrapper-page-Markdown renderer) is deleted, and
`cli/render.py` drops its `--site-dist` flag along with the second
render invocation the Technical Details build-order section described.
`site/` is therefore self-contained at build time over the committed `p/`
tree — no bot pre-pass required before `bun run build` — with the wire
mirror + catalog view-model still written into the same dist tree strictly
*after* the VitePress build (the `emptyOutDir` footgun this ADR already
documented survives unchanged, now as a two-step rather than three-step
pipeline; see `taskfile.yml`'s `render:build` task).

**Consequences:**
- **Positive:** one render-pipeline output tree instead of two — a smaller
  footgun surface (one build-order seam, not two); `site/` builds
  standalone against the committed `p/` tree with no generated-file
  dependency; `core/render.py` loses an entire code path
  (`core/catalog_md.py`, its tests, its golden-fixture `wrapper_pages/`
  subtree).
- **Negative:** per-package detail pages can no longer carry hand-authored
  publisher prose alongside the generated view (the original design's
  stated purpose for embedding `<PackageDetail />` inside an otherwise-free
  Markdown file) — out of scope for `plan_site_redesign`, not reintroduced
  elsewhere.
- **Unchanged:** the `emptyOutDir`-ordering risk this ADR already flagged;
  the Cache Rule scoping requirement; `/data/catalog/**` and `/`, `/docs/**`
  remaining outside the wire contract.

**Cross-references updated:** the "`site/` layout" and "Build pipeline
order" Technical Details subsections above describe the original
three-step, two-output-tree design and are **not** rewritten in place — this
amendment is the current-state correction; see `site/README.md` and
`bot/CONTRACTS.md` §8/§12 for the landed shapes.

## Links

- [`plan_index_v1.md`](../state/plans/plan_index_v1.md) — canonical phase/work-package
  decomposition (Phase 0 origin, Phase 2 WP2-N..R, Phase 3 WP3-A/B)
- [`research_docs_site.md`](./research_docs_site.md) — superseded recommendation
  (mdBook + separate Pages project), reversed by this ADR
- [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md) —
  CAS layout (`/p/<ns>/<pkg>/o/sha256/<hex>.<ext>`) that catalog components reference
- [`adr_namespace_policy.md`](./adr_namespace_policy.md) — reserved namespace segments
  including `docs` and `data`
- [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md) —
  render pipeline security posture, workflow SHA-pinning
- [`decision_log_2026-07-16.md`](./decision_log_2026-07-16.md) — narrative of the
  2026-07-16 design discussion this ADR formalizes
- [`../rules/product-context.md`](../rules/product-context.md) — Cache Rule invariant,
  wire-contract one-way door
- [`../rules/quality-vite.md`](../rules/quality-vite.md) — Vite/VitePress build-tool
  quality rules applying to `site/`
- [VitePress](https://vitepress.dev/) — site generator
- [bun](https://bun.sh/) — package manager/runtime for `site/`
- [Cloudflare Pages](https://developers.cloudflare.com/pages/) — hosting

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Michael Herwig + Claude design swarm | Initial record: colocation decision, VitePress reversal of mdBook research recommendation |
| 2026-07-17 | Claude (docs) | Added Amendment A1 (Accepted): dynamic routes (`site/src/[ns]/[pkg].paths.ts`) replace bot-generated wrapper pages, per `plan_site_redesign` WP-docs (Waves 1-2 landed as PRs #21-#26). |
