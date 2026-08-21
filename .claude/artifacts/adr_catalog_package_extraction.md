# ADR — Catalog Renderer Extraction into `@ocx-sh/catalog`

Date: 2026-08-21 · Status: accepted (owner-settled in discussion, formalized by hex-plan)
Deciders: owner · Inputs: hex-plan Discover/Research artifacts
(`research_catalog_sanitizer_stack.md`, `research_vitepress_programmatic_api.md`,
`research_npm_publish_hygiene.md`), [ocx-sh/index#716](https://github.com/ocx-sh/index/issues/716),
grimoire-indexer as precedent ("little brother": align on proven ideas, exceed on renderer quality).

## Context

The index site (`site/`, VitePress 2 blank theme) and its view-model emitter
(`bot/.../core/render.py` `_catalog_*`) are welded to this repository. The goal
is a decentralized story: anyone — corporate mirrors included — runs their own
index + catalog with minimal setup. Index and catalog are distinct concerns
(governance/data plane vs presentation) that must be able to colocate in one
repo or live apart, and one catalog must be able to display multiple indexes.

## Decision drivers (weighted)

1. **Wire-contract purity** (high) — catalog consumes exactly what ocx consumes.
2. **Move-not-rewrite safety** (high) — extraction must not change rendered output.
3. **Existing audited assets preserved** (high) — bot's G-01..G-20 security suite.
4. **Consumer setup cost** (medium) — docs-driven manual setup, no scaffolder v1.
5. **Maintenance surface** (medium) — boring tech, minimal new dependencies.

## Options

| # | Option | Assessment |
|---|---|---|
| 1 | **Status quo** — keep site + bot in-repo | Zero cost now; fails the decentralization goal outright; every corporate deployment forks the repo. Rejected. |
| 2 | **Single combined package** (grim model: one npm package = bot + renderer) | One install; but forces a TS rewrite of the ~6.3k-line Python bot, discarding the 100%-branch G-01..G-20 audit suite (driver 3), and welds index to catalog against the separation requirement (a catalog-only viewer would drag governance code in). Rejected. |
| 3 | **Two-package split: npm `@ocx-sh/catalog` (TS/VitePress) + PyPI `ocx-indexbot` (Python)** — **chosen** | Preserves the audited bot; catalog becomes an ordinary wire-contract client; catalog-only and index-only deployments both possible; consumers' CI runs each tool as one command per job. Cost: two toolchains in a colocated repo — accepted, CI-mediated. **Scope caveat: only the npm half is delivered by the current plan; the PyPI bot extraction is a later track (gated on the GitLab governance ADR).** |
| 4 | **Astro rewrite** (align with grim's renderer) | Different axis (framework, not packaging) but recorded for completeness: discards landed Waves 1–2 (design-mock theme, PRs #21–#26) and re-litigates a working stack for zero user-visible gain. Rejected. |
| 5 | **Library-only** — publish theme + view-model emitter as importables; every consumer hand-writes its own VitePress config/srcDir; no CLI, no build engine | Avoids the plan's riskiest novel artifact (the staged-scratch-root engine has no confirmed OSS precedent). But it fails the owner's product requirements directly: no `ci` render/drift check, no uniform `/index/<label>/` mirror implementation, no docs mount, no one-command-per-CI-job setup — every consumer re-derives the build wiring this extraction exists to distribute. Rejected; the engine risk is carried consciously instead. |

## Decision detail (settled surface — plan treats as fixed)

**Data acquisition — wire contract only.** Sources: `path` | `url` | `git`
(shallow, `ref`, `dir`), discriminated by key in `catalog.config.json`
(JSON + published `$schema`; optional `configVersion` defaulting 1 as the
forward-compat discriminator — config and tool are lockfile-version-locked so
unknown keys stay fail-loud, but the version field covers cross-version
copy-paste of examples). Remote = walker: conditional GET `/c/index.json`
(ETag; 304 ⇒ unchanged), digest-diff, fetch changed roots + missing CAS blobs,
per-file digest verification. **No snapshot tarball** (an optional fast path
plus mandatory fallback is two fetchers; `ocx-package-index-sync` defines valid
indexes without one). **No ocx CLI dependency** — the locked-observation format
already carries every render input (roots, desc blobs, platforms via CAS image
indices). CI cache = CAS blob dir, optimization never correctness.

**Serving/mirroring.** Every source's wire tree is byte-verbatim copied under
`/index/<label>/`, uniformly, self included — unconditional, because the
browser never crosses origins, so displaying a source requires its data under
the catalog's own origin (re-validation removed the earlier `serve` opt-in
flag as incoherent: off ⇒ dead detail links; owner sign-off flagged in plan).
`root: true` (max one source, config-error otherwise) additionally copies to
deploy root — legacy-compat flag, index.ocx.sh only. Labels derive from the roots' name
prefix (logical index identity), override allowed. Consequence: **`index`** becomes a
reserved namespace segment (amendment to `adr_namespace_policy.md`, separate
small change). `docs`/`data`/`assets` are already reserved (ND-4 control-path
row) and `c` already via `adr_enumeration_index.md` D6 — no change needed
there (correction from panel review; re-reserving would be a no-op).

**Rendering model.** Identity phase preserves the CURRENT model exactly:
build-time route discovery + OG tags; theme fetches `catalog.json`, roots, and
CAS at runtime, origin-relative (Discover corrected the earlier SSG
assumption). Content-SSG/SEO upgrades are post-extraction, deliberate,
re-baselined changes. N-depth names ([#716](https://github.com/ocx-sh/index/issues/716)):
new code treats name = prefix + opaque 1..N-segment path; VitePress has no
rest-param routes (verified in installed source), so the package uses
**build-time page synthesis** into its staged scratch root — in v1.

**Engine invocation** (research-backed): mkdtemp scratch root per run; write
synthesized pages + `.vitepress/theme/index.ts` shim re-exporting the package
theme + generated config; `build(root, {outDir, cacheDir})` explicit; dev
server in child process, never in-process under vitest; pin the exact
vitepress alpha and re-verify its undocumented node API on every bump.

**Layout contract.** Fixed skeleton: brand, search, theme toggle always; docs
link / install buttons auto-appear when their config data exists; `nav` adds
links; styling via CSS custom-property tokens + one appended `custom.css`;
NO component/slot API v1. Config surface: `brand`, `nav`, `docs` (single dir,
nested), `css`, `install`, `sources`, `ci`. Mechanism docs stay canonical at
index.ocx.sh/docs; package ships an empty docs mount only.

**CI rendering** (per package, own files only): rendered reference workflows +
drift check; normalize-compare (strip `@ref`+comment from `uses:`) + repo-wide
pin carry-forward from generated-header files; ambiguous pin ⇒ template default
+ warning; `verifyCi: false` opt-out. **The generated header is itself a
versioned contract** (`ocx-catalog ci v1` marker): later releases must parse
every prior header version, or pin carry-forward breaks as unexplained drift
in consumers' committed workflows. GitLab root `.gitlab-ci.yml` = hand-written
includes. No ci-lint (owner-rejected).

**Untrusted content.** DOMPurify ≥3.3.2 (HTML + SVG profiles) with an
environment split: the theme's README path renders **client-side at runtime**
(ReadmePane), so the shipped theme uses **browser DOMPurify against the real
DOM**; jsdom is test/Node-side only, never in the client bundle. Baseline
honesty: the current theme already renders no raw HTML (`markdown-it
{html:false}` + escaping highlighter) — DOMPurify is defense-in-depth plus the
enabler for GFM checkboxes/Shiki styling, not the sole control. SVG via
`<img>` only; CSP `_headers` on CAS paths of every deploy (verbatim wire bytes
cannot be sanitized — the serving layer owns that control). See
`research_catalog_sanitizer_stack.md`.

**Quality gates.** 100% branch coverage on all package TS (vitest v8);
theme SFCs excluded from the percentage, gated instead by the golden-diff
fixtures + smoke (owner-decided denominator). Pack verification fully local:
`npm pack` → `publint` → `attw --pack` → tarball tempdir install smoke.
Golden-diff identity gate: package-built dist ≡ current-site dist on the
committed seed fixtures (8 golden render cases incl. `nested_namespace`),
hashed asset filenames normalized. Normalization scope is provisional until
WP-02's empirical double-build check (vite#13071 hash drift and possible
embedded timestamps are unverified on the VitePress 2 alpha — the research
flags both open; WP-02 settles them before any diff is trusted).

**View-model emitter moves language.** `_catalog_platforms`/`_latest_activity`/
`_catalog_entry`/`_generated_timestamp`/`_catalog_index`
(`core/render.py:152-320`) are reimplemented in TS — a rewrite, not a move,
byte-gated by the 8 golden `catalog.json` fixtures which transfer to the
package as its contract fixtures. **Known compounded risk (panel finding):
the port surface includes `core/version_order.py` (`variant_names`,
`find_latest_version`), making a 4th independent implementation of the
version-grammar family (Rust `ocx_lib` → 2 Python ports → theme `version.ts`,
which itself documents unchecked drift). The emitter port must NOT reuse the
theme's `version.ts` (different grammar — full prerelease/build parsing vs
`_VERSION_RE`'s narrower shape); it ports `version_order.py` as its own
module, pinned by the golden cases plus a new prerelease/build-tag fixture.**
Bot keeps `config.json`, `p/**`, `c/index.json` emission and all of
`cli/render.py`.

**Release.** Org `@ocx-sh` created immediately (anti-squat); manual 0.1.0 →
trusted publishing (OIDC) + `--provenance` once the (public) repo exists;
grim's `--dry-run | grep auto-corrected` guard ported. Apache-2.0. Manual
`npm version` + tag; no changesets.

## Migration / rollout

1. **Baseline** — build current site against seed fixtures; freeze normalized
   `dist-baseline`.
2. **Package construction** in sibling dir `~/dev/ocx-catalog` (no GitHub repo;
   local-only), theme lifted verbatim, emitter ported byte-gated.
3. **Dogfood switchover** — this repo consumes via `file:../ocx-catalog`;
   `task site:build` becomes the package's build; golden diff must hold at
   every step. Fixed build order (VitePress first, `indexbot render --out`
   second, same tree) is preserved by the package's entry point.
4. **Deletion** — moved code leaves `site/` and `core/render.py`; goldens
   split (catalog.json cases → package, wire cases stay).
5. **Later, separate**: GitHub repo + npm publish + OIDC; repo migration of
   package sources; GitLab governance ADR (deferred, bot track).

Rollback at any step = revert the consumer to in-repo `site/` (kept intact in
git history); the wire contract never changes, so deployed output is
switch-independent.

## Constitution / invariants check

No constitution file; checked against repo invariant docs instead:
wire-contract one-way door untouched (catalog is a client); CI security
invariants (default-deny, SHA pins, no PR-head exec) preserved in the edited
`render-deploy.yml`; Cache Rule extended to `/index/**` mirrors in docs;
`bot/**` coverage gate untouched. No deviations.

## Consequences

+ Decentralized catalogs with minimal setup; corporate multi-index display.
+ Wire contract validated by a second independent client.
− Two toolchains in colocated repos; TS/Python duplication of the ~30-line CI
  normalize/carry-forward logic (deliberate DAMP).
− The emitter port is a rewrite slice inside a "move" — mitigated by byte
  golden gates.
○ Bot-side G-02 prefix bug + N-segment generalization intentionally NOT here —
  bot track, tracked in [#716](https://github.com/ocx-sh/index/issues/716).
