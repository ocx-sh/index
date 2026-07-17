import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
//
// Adapted from ocx-sh/ocx's website/.vitepress/config.mts (see
// .claude/artifacts/adr_catalog_docs_colocation.md "site/ layout" for the
// full port/adapt/drop inventory). Dropped relative to the source: the
// groupIcon/customIcons vite plugins (code-group tab icons — not needed
// without the ocx CLI's multi-shell install snippets), the licensed-asset
// R2 fallback plugin, and the dev/prod banner logic (`OCX_DEPLOY_TARGET`) —
// none of that applies to a package-index catalog + docs site.
export default defineConfig({
  srcDir: 'src',
  cleanUrls: true,

  title: 'OCX Index',
  description:
    'Package catalog and wire-format docs for the OCX public index (index.ocx.sh).',

  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Catalog', link: '/' },
      { text: 'Docs', link: '/docs/' },
    ],

    // Catalog root ("/") deliberately has no sidebar entry — only "/docs/"
    // gets one. This is the rescoping ocx/website's sidebar needs on this
    // repo: the source theme scopes its doc sidebar under "/" (docs live at
    // its site root there); here the catalog owns "/" and docs are one
    // level down at "/docs/".
    sidebar: {
      '/docs/': [
        {
          text: 'Reference',
          link: '/docs/reference/',
          items: [
            { text: 'Wire Format', link: '/docs/reference/wire-format' },
            { text: 'Entry Schema', link: '/docs/reference/entry-schema' },
            { text: 'Namespace Policy', link: '/docs/reference/namespace-policy' },
            { text: 'Governance Contracts', link: '/docs/reference/governance-contracts' },
            { text: 'Changelog', link: '/docs/reference/changelog' },
          ],
        },
        {
          text: 'How-To',
          link: '/docs/how-to/',
          items: [
            { text: 'Announce a Package', link: '/docs/how-to/announce-a-package' },
            { text: 'Claim a Namespace', link: '/docs/how-to/claim-a-namespace' },
            { text: 'Yank a Version', link: '/docs/how-to/yank-a-version' },
          ],
        },
        {
          text: 'Ops',
          link: '/docs/ops/',
          items: [
            { text: 'Rotate the Announce PAT', link: '/docs/ops/rotate-announce-pat' },
            { text: 'Run a Reconcile Dry Run', link: '/docs/ops/run-reconcile-dry-run' },
            { text: 'M-1 Flip', link: '/docs/ops/m1-flip' },
          ],
        },
        {
          text: 'Explanation',
          link: '/docs/explanation/',
          items: [
            { text: 'Architecture', link: '/docs/explanation/architecture' },
          ],
        },
      ],
    },

    socialLinks: [{ icon: 'github', link: 'https://github.com/ocx-sh/index' }],

    // Local search provider only — no third-party search vendor.
    search: {
      provider: 'local',
    },
  },
})
