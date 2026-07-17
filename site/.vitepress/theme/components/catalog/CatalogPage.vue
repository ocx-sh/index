<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useCatalog } from '../../composables/useCatalog'
import { filterPackages } from '../../utils/filterPackages'
import { isEditableTarget } from '../../utils/dom'
import SearchInput from './SearchInput.vue'
import FilterChips from './FilterChips.vue'
import ResultMeta from './ResultMeta.vue'
import CatalogGrid from './CatalogGrid.vue'
import PackageCard from './PackageCard.vue'
import SkeletonGrid from './SkeletonGrid.vue'
import EmptyState from './EmptyState.vue'

// Sole `useCatalog()` consumer among `catalog/**` components — every other
// catalog component is a plain props-in/events-out leaf, and this one owns
// all search/filter state. (The command palette also calls `useCatalog()`,
// lazily on first open, for its package results — see `useCatalog.ts` and
// `search/SearchModal.vue`.)
const { catalog, loading, load: loadCatalog } = useCatalog()
onMounted(loadCatalog)

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

// Roving-tabindex grid nav (WAI-ARIA APG "grid" pattern): exactly one card
// is a Tab stop at a time (index into `filtered`); arrow keys move it,
// `PackageCard`'s own `<a>` picks up `tabindex` as a plain fallthrough
// attribute (not declared as a prop there — no changes needed in
// PackageCard.vue/CatalogGrid.vue to wire this). Resets to the first card
// whenever the filtered set changes so a fresh Tab from the search bar
// always lands on card 0, never a stale arrow-nav position.
const activeCardIndex = ref(0)
watch(filtered, () => { activeCardIndex.value = 0 })

const ARROW_DELTA: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1 }

function onGridKeydown(event: KeyboardEvent) {
  const grid = event.currentTarget as HTMLElement
  const cards = [...grid.querySelectorAll<HTMLAnchorElement>('.package-card')]
  const currentIndex = cards.indexOf(document.activeElement as HTMLAnchorElement)
  if (currentIndex === -1) return

  // Column count read straight off the resolved grid track list — cheap,
  // and always right for the auto-fill/responsive breakpoints in
  // CatalogGrid's CSS without duplicating its media queries here.
  const columns = getComputedStyle(grid).gridTemplateColumns.split(' ').length
  const delta = ARROW_DELTA[event.key] ?? (event.key === 'ArrowUp' ? -columns : event.key === 'ArrowDown' ? columns : undefined)
  if (delta === undefined) return

  event.preventDefault()
  const nextIndex = Math.min(cards.length - 1, Math.max(0, currentIndex + delta))
  if (nextIndex === currentIndex) return
  activeCardIndex.value = nextIndex
  cards[nextIndex]?.focus()
}

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
// or dependency on any `search/`/`useCommandPalette` module here (`utils/
// dom.ts` is a neutral leaf, not scoped under either, so importing it
// doesn't break that rule).
const searchInputRef = ref<InstanceType<typeof SearchInput> | null>(null)

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
      <CatalogGrid v-else @keydown="onGridKeydown">
        <PackageCard
          v-for="(pkg, i) in filtered"
          :key="pkg.name"
          :pkg="pkg"
          :tabindex="i === activeCardIndex ? 0 : -1"
        />
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
