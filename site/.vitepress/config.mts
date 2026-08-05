import { defineConfig } from 'vitepress'
import { createReadStream, readFileSync, statSync } from 'node:fs'
import { extname, join, normalize, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const SITE_URL = 'https://index.ocx.sh'

/** Package root's desc for OG tags — same tree + env knob as
 * `src/[ns]/[pkg].paths.ts` (see its cwd-invariant docblock). Any read
 * failure degrades to null: OG tags then fall back to generic site copy,
 * never fail the build. */
function packageDesc(ns: string, pkg: string): { title: string, description: string } | null {
  try {
    const indexDir = (process.env.OCX_RENDER_INDEX_DIR ?? '').replace(/\/+$/, '')
    const rootPath = resolve(process.cwd(), '..', ...(indexDir ? [indexDir] : []), 'p', ns, `${pkg}.json`)
    const root = JSON.parse(readFileSync(rootPath, 'utf8'))
    return root.desc ? { title: root.desc.title, description: root.desc.description } : null
  } catch {
    return null
  }
}

// Semantic code theme from the site palette (owner spec: an OSS
// highlighter supplies the parsing; WE supply only colors for its semantic
// token classes). Hexes duplicate styles/tokens/palette.css verbatim —
// Shiki themes are build-time JSON, they can't read CSS vars. Same
// semantic mapping as ReadmePane's hljs theme: comments text-3 italic,
// keywords kw, strings ok, numbers warn, function/heading names text-1
// bold, variables text-2.
function ocxCodeTheme(mode: 'light' | 'dark') {
  const c = mode === 'light'
    ? { bg: '#f6f8fa', fg: '#4b5665', comment: '#8a94a3', kw: '#6f5bd0', str: '#0e9f6e', num: '#9a6b13', fn: '#1b2129', vars: '#4b5665', accent: '#ff6047' }
    : { bg: '#14181f', fg: '#9aa5b3', comment: '#606c7c', kw: '#c0b3ff', str: '#3edea6', num: '#fab833', fn: '#e7ebf1', vars: '#9aa5b3', accent: '#ff6047' }
  return {
    name: `ocx-${mode}`,
    type: mode,
    colors: { 'editor.background': c.bg, 'editor.foreground': c.fg },
    tokenColors: [
      { scope: ['comment', 'punctuation.definition.comment'], settings: { foreground: c.comment, fontStyle: 'italic' } },
      { scope: ['string', 'string.quoted', 'constant.other.symbol'], settings: { foreground: c.str } },
      { scope: ['keyword', 'storage.type', 'storage.modifier', 'support.type', 'entity.name.tag'], settings: { foreground: c.kw } },
      { scope: ['constant.numeric', 'constant.language', 'constant.character', 'keyword.other.unit'], settings: { foreground: c.num } },
      { scope: ['entity.name.function', 'support.function', 'entity.name.section', 'markup.heading'], settings: { foreground: c.fn, fontStyle: 'bold' } },
      { scope: ['variable', 'variable.parameter', 'entity.other.attribute-name'], settings: { foreground: c.vars } },
      { scope: ['markup.deleted'], settings: { foreground: c.accent } },
    ],
  }
}

// Dev-only wire mirror: `vitepress dev` has no `indexbot render` step, so
// the runtime-fetched wire files (/config.json, /p/**, /c/index.json,
// /data/catalog/**) don't exist on the dev server — catalog and detail
// pages would render permanently empty. `task site:dev` renders them once
// into this gitignored dir; this middleware serves them, everything else
// falls through to Vite (so /favicon.svg still comes from src/public).
// Snapshot semantics: re-run `task site:dev` after changing p/ data.
const devWireDir = fileURLToPath(new URL('./dev-wire', import.meta.url))
const WIRE_MIME: Record<string, string> = {
  '.json': 'application/json',
  '.md': 'text/markdown',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
}

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

  vite: {
    plugins: [
      {
        name: 'ocx-dev-wire',
        apply: 'serve',
        configureServer(server) {
          server.middlewares.use((req, res, next) => {
            try {
              const urlPath = decodeURIComponent((req.url ?? '').split('?')[0])
              const mime = WIRE_MIME[extname(urlPath)]
              if (!mime) return next()
              const file = normalize(join(devWireDir, urlPath))
              if (!file.startsWith(devWireDir)) return next()
              if (!statSync(file, { throwIfNoEntry: false })?.isFile()) return next()
              res.setHeader('Content-Type', mime)
              createReadStream(file).pipe(res)
            } catch {
              next()
            }
          })
        },
      },
    ],
  },

  title: 'OCX Index',
  description:
    'Package catalog and wire-format docs for the OCX public index (index.ocx.sh).',

  // `src/public/favicon.svg` — verbatim design-mock ocx-logo.svg (same
  // provenance as theme/components/layout/Logo.vue), served from the
  // `srcDir`-relative public dir VitePress copies as-is into dist root.
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['meta', { property: 'og:site_name', content: 'OCX Index' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { name: 'twitter:card', content: 'summary' }],
  ],

  // Share metadata: sitemap covers every rendered page (dynamic package
  // routes included); per-package OG title/description come from the
  // committed root's desc so a shared package link previews meaningfully.
  sitemap: { hostname: SITE_URL },

  transformHead({ pageData }) {
    // Catalog page: start the catalog.json fetch at HTML-parse time —
    // CatalogPage's onMounted fetch otherwise waterfalls behind JS download
    // + hydration (the whole perceived initial lag). `crossorigin` (i.e.
    // anonymous) matches fetch()'s default mode/credentials; without it the
    // preload and the fetch don't key-match and the browser fetches twice.
    if (pageData.relativePath === 'index.md') {
      return [['link', { rel: 'preload', href: '/data/catalog/catalog.json', as: 'fetch', crossorigin: '' }]]
    }
    const ns = pageData.params?.ns as string | undefined
    const pkg = pageData.params?.pkg as string | undefined
    if (!ns || !pkg) return []
    const desc = packageDesc(ns, pkg)
    const title = desc ? `${desc.title} — OCX Index` : `${ns}/${pkg} — OCX Index`
    const description = desc?.description || `Install ocx.sh/${ns}/${pkg} from the OCX public package index.`
    return [
      ['meta', { property: 'og:title', content: title }],
      ['meta', { property: 'og:description', content: description }],
      ['meta', { property: 'og:url', content: `${SITE_URL}/${ns}/${pkg}` }],
      ['meta', { name: 'description', content: description }],
    ]
  },

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

  // Dual Shiki theme following site appearance (owner decision 2026-08-05,
  // revising mock 1f's always-dark rule) — spans carry --shiki-light/
  // --shiki-dark vars; docs-prose.css switches them on `.dark`.
  //
  // `headers` is OFF by default at the core-markdown level (verified
  // against alpha.18's `resolveConfig`/`createMarkdownRenderer` — it's
  // DefaultTheme's own config that normally turns this on, and this is a
  // blank theme, no `extends`). WP-E's OnThisPage.vue scroll-spy reads
  // `page.headers`, so it must be explicitly enabled here. `level: [2, 3]`
  // caps extraction to match OnThisPage.vue's two-tier (h2 + nested h3)
  // render — verified no `src/docs/**` page goes deeper than h3.
  markdown: {
    theme: { light: ocxCodeTheme('light'), dark: ocxCodeTheme('dark') },
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
