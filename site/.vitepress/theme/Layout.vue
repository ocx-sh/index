<script setup lang="ts">
import { useData } from 'vitepress'
import SiteHeader from './components/layout/SiteHeader.vue'
import CatalogPage from './components/catalog/CatalogPage.vue'
import DetailPage from './components/detail/DetailPage.vue'
import DocLayout from './components/docs/DocLayout.vue'
import NotFound from './NotFound.vue'
// WP-E additive edit: the ⌘K command palette is global (every page, not
// just docs), so it mounts once here rather than inside DocLayout.vue.
import SearchModal from './components/search/SearchModal.vue'

// Plain v-if dispatch, no global component registration (blank theme —
// see index.mts). SiteHeader always renders, including on the 404 page.
const { page, frontmatter } = useData()
</script>

<template>
  <div class="theme-shell">
    <SiteHeader />
    <NotFound v-if="page.isNotFound" />
    <CatalogPage v-else-if="frontmatter.layout === 'catalog'" />
    <DetailPage v-else-if="frontmatter.layout === 'detail'" />
    <DocLayout v-else />
    <SearchModal />
  </div>
</template>

<style scoped>
.theme-shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}
</style>
