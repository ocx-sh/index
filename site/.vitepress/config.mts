import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
//
// Own minimal theme-config shape — this is a blank custom theme (see
// theme/index.mts), not `vitepress/theme`, so `themeConfig` carries none of
// DefaultTheme's `nav`/`sidebar`/`socialLinks` fields; SiteHeader.vue and
// (Wave 2) DocsSidebar.vue own that UI directly instead. `search` stays
// here because VitePress core reads `themeConfig.search.provider` itself
// (independent of which theme is active) to decide whether to build the
// `@localSearchIndex` virtual module at all.
interface ThemeConfig {
  githubUrl: string
  search: { provider: 'local' }
}

export default defineConfig<ThemeConfig>({
  srcDir: 'src',
  cleanUrls: true,

  title: 'OCX Index',
  description:
    'Package catalog and wire-format docs for the OCX public index (index.ocx.sh).',

  // `src/public/favicon.svg` — verbatim design-mock ocx-logo.svg (same
  // provenance as theme/components/layout/Logo.vue), served from the
  // `srcDir`-relative public dir VitePress copies as-is into dist root.
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }]],

  // Per-package detail pages are a dynamic route (`src/[ns]/[pkg].md` +
  // `[ns]/[pkg].paths.ts`, globbing `p/*/*.json` at build) — the wire
  // mirror `indexbot render --out` writes into THIS SAME dist tree, but
  // only in its second pass, after this build finishes (ADR
  // adr_catalog_docs_colocation.md "Build pipeline order" — the
  // emptyOutDir footgun). VitePress's own dead-link linter runs during
  // this build, before those files exist, so every /p/** CAS reference is
  // unconditionally "dead" from its perspective — expected, not a real
  // broken link. Scoped to /p/ only; doc-to-doc links still get checked.
  ignoreDeadLinks: [/^\/p\//],

  // Single dark Shiki theme — design mock 1f: "code blocks always dark
  // (both themes)", not the DefaultTheme convention of a light/dark pair
  // that follows site appearance.
  //
  // `headers` is OFF by default at the core-markdown level (verified
  // against alpha.18's `resolveConfig`/`createMarkdownRenderer` — it's
  // DefaultTheme's own config that normally turns this on, and this is a
  // blank theme, no `extends`). WP-E's OnThisPage.vue scroll-spy reads
  // `page.headers`, so it must be explicitly enabled here. `level: [2, 3]`
  // caps extraction to match OnThisPage.vue's two-tier (h2 + nested h3)
  // render — verified no `src/docs/**` page goes deeper than h3.
  markdown: {
    theme: 'github-dark',
    headers: { level: [2, 3] },
  },

  themeConfig: {
    githubUrl: 'https://github.com/ocx-sh/index',

    // Local search provider only — no third-party search vendor. UI is
    // hand-rolled (Wave 2 `components/search/SearchModal.vue`); this just
    // keeps the build-time local-search-index machinery on.
    search: {
      provider: 'local',
    },
  },
})
