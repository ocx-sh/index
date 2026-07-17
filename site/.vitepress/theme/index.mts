import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import HomeLayout from './HomeLayout.vue'
import './custom.css'

// Trimmed to exactly the catalog component set (adr_catalog_docs_colocation.md
// "site/ layout") — ocx-sh/ocx's website theme ships ~20 components
// (roadmap pages, terminal recordings, dependency explorer, etc.); none of
// that applies to a package index.
import CopySnippet from './components/CopySnippet.vue'
import PackageCatalog from './components/PackageCatalog.vue'
import PackageDetail from './components/PackageDetail.vue'
import PlatformIcons from './components/PlatformIcons.vue'
import TagBadge from './components/TagBadge.vue'
import VersionTree from './components/VersionTree.vue'

export default {
  extends: DefaultTheme,
  Layout: HomeLayout,
  enhanceApp({ app }) {
    app.component('CopySnippet', CopySnippet)
    app.component('PackageCatalog', PackageCatalog)
    app.component('PackageDetail', PackageDetail)
    app.component('PlatformIcons', PlatformIcons)
    app.component('TagBadge', TagBadge)
    app.component('VersionTree', VersionTree)
  },
} satisfies Theme
