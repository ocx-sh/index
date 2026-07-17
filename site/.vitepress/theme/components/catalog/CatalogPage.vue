<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useCatalog } from '../../composables/useCatalog'
import { filterPackages } from '../../utils/filterPackages'
import SearchInput from './SearchInput.vue'
import FilterChips from './FilterChips.vue'
import ResultMeta from './ResultMeta.vue'
import CatalogGrid from './CatalogGrid.vue'
import PackageCard from './PackageCard.vue'
import SkeletonGrid from './SkeletonGrid.vue'
import EmptyState from './EmptyState.vue'

// Sole `useCatalog()` consumer — every other catalog component is a plain
// props-in/events-out leaf. This component owns all search/filter state.
const { catalog, loading } = useCatalog()

const query = ref('')
const activePlatforms = ref<string[]>([])
const activeKeywords = ref<string[]>([])
const deprecatedOnly = ref(false)
const keywordsExpanded = ref(false)

const KEYWORD_CHIP_LIMIT = 8

// ponytail: no debounce — this filters over at most ~500 in-memory objects
// synchronously on every keystroke via a plain computed, well under a
// frame budget. Upgrade path if the catalog grows large enough to jank:
// @vueuse/core's `watchDebounced` on `query`, feeding a separate debounced
// ref into `filterPackages` instead of `query` directly.
const filtered = computed(() =>
  filterPackages(catalog.value.packages, {
    query: query.value,
    platforms: activePlatforms.value,
    keywords: activeKeywords.value,
    deprecatedOnly: deprecatedOnly.value,
  }),
)

// Keyword chips = top-N by frequency across the WHOLE catalog (not the
// filtered subset — the chip rail stays stable as filters are applied).
const keywordFrequency = computed(() => {
  const freq = new Map<string, number>()
  for (const pkg of catalog.value.packages) {
    for (const kw of pkg.keywords) {
      freq.set(kw, (freq.get(kw) ?? 0) + 1)
    }
  }
  return [...freq.entries()]
    .map(([keyword, count]) => ({ keyword, count }))
    .sort((a, b) => b.count - a.count || a.keyword.localeCompare(b.keyword))
})

const visibleKeywords = computed(() =>
  keywordsExpanded.value ? keywordFrequency.value : keywordFrequency.value.slice(0, KEYWORD_CHIP_LIMIT),
)
const hiddenKeywordCount = computed(() => Math.max(0, keywordFrequency.value.length - KEYWORD_CHIP_LIMIT))

const activeFilterLabels = computed(() => [
  ...activePlatforms.value,
  ...activeKeywords.value,
  ...(deprecatedOnly.value ? ['deprecated'] : []),
])

function togglePlatform(os: string) {
  activePlatforms.value = activePlatforms.value.includes(os)
    ? activePlatforms.value.filter(p => p !== os)
    : [...activePlatforms.value, os]
}

function toggleKeyword(keyword: string) {
  activeKeywords.value = activeKeywords.value.includes(keyword)
    ? activeKeywords.value.filter(k => k !== keyword)
    : [...activeKeywords.value, keyword]
}

function clearFilters() {
  activePlatforms.value = []
  activeKeywords.value = []
  deprecatedOnly.value = false
}

// Page-scoped "/" handler — focuses the inline SearchInput. This is
// deliberately separate from WP-E's global ⌘K command palette (frozen
// cross-WP decision, plan_site_redesign.md Status block): no import from
// or dependency on any `search/`/`useCommandPalette` module here.
const searchInputRef = ref<InstanceType<typeof SearchInput> | null>(null)

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  return target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable
}

function onKeydown(event: KeyboardEvent) {
  if (event.key !== '/' || isEditableTarget(event.target)) return
  event.preventDefault()
  searchInputRef.value?.focus()
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <main class="catalog-page">
    <template v-if="loading">
      <div class="toolbar-skeleton" />
      <SkeletonGrid />
    </template>

    <EmptyState v-else-if="catalog.packages.length === 0" variant="no-data" />

    <template v-else>
      <div class="catalog-toolbar">
        <SearchInput ref="searchInputRef" v-model="query" />
        <FilterChips
          :active-platforms="activePlatforms"
          :visible-keywords="visibleKeywords"
          :active-keywords="activeKeywords"
          :hidden-keyword-count="hiddenKeywordCount"
          :keywords-expanded="keywordsExpanded"
          :deprecated-active="deprecatedOnly"
          @toggle-platform="togglePlatform"
          @toggle-keyword="toggleKeyword"
          @toggle-deprecated="deprecatedOnly = !deprecatedOnly"
          @toggle-expand="keywordsExpanded = !keywordsExpanded"
        />
        <ResultMeta
          :total="catalog.packages.length"
          :filtered="filtered.length"
          :active-filter-labels="activeFilterLabels"
          :generated="catalog.generated"
          @clear-filters="clearFilters"
        />
      </div>

      <EmptyState
        v-if="filtered.length === 0"
        variant="no-match"
        :query="query"
        :total="catalog.packages.length"
        @clear-search="query = ''"
      />
      <CatalogGrid v-else>
        <PackageCard v-for="pkg in filtered" :key="pkg.name" :pkg="pkg" />
      </CatalogGrid>
    </template>
  </main>
</template>

<style scoped>
.catalog-page {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  max-width: 1400px;
  width: 100%;
  margin: 0 auto;
  padding: var(--space-5) var(--space-6) var(--space-8);
}

.catalog-toolbar {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.toolbar-skeleton {
  height: 44px;
  background: var(--c-surface);
  border: 1.5px solid var(--c-line);
  border-radius: var(--radius-lg);
}
</style>
