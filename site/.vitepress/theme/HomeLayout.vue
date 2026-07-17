<script setup lang="ts">
// Adapted from ocx-sh/ocx's website theme (adr_catalog_docs_colocation.md):
// hero + embedded catalog. The source theme's DevBanner (early-development
// notice) is stripped entirely — not applicable to a public package index.
import DefaultTheme from 'vitepress/theme'
import PackageCatalog from './components/PackageCatalog.vue'

const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #home-features-after>
      <div class="catalog-section">
        <div class="catalog-header">
          <h2>Browse the Catalog</h2>
          <p>Every published package, searchable — logical name, version tree, supported platforms.</p>
        </div>
        <PackageCatalog />
      </div>
    </template>
  </Layout>
</template>

<style scoped>
.catalog-section {
  max-width: 1152px;
  margin: 0 auto;
  padding: 0 24px 64px;
}

@media (min-width: 640px) {
  .catalog-section {
    padding: 0 48px 64px;
  }
}

@media (min-width: 960px) {
  .catalog-section {
    padding: 0 64px 64px;
  }
}

.catalog-header {
  text-align: center;
  margin-bottom: 24px;
}

.catalog-header h2 {
  font-size: 24px;
  font-weight: 700;
  margin: 0 0 8px;
  border: none;
  padding: 0;
}

.catalog-header p {
  color: var(--vp-c-text-2);
  font-size: 14px;
  margin: 0;
}
</style>
