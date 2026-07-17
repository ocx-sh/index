<script setup lang="ts">
// Presentational only — CatalogPage owns all filter STATE (active
// selections) and the keyword top-N/expand computation; this component
// just renders whatever chip lists it's given and emits toggle events.

import { OS_GLYPHS, OS_ORDER } from '../../utils/osGlyphs'

interface KeywordChip {
  keyword: string
  count: number
}

defineProps<{
  activePlatforms: string[]
  visibleKeywords: KeywordChip[]
  activeKeywords: string[]
  hiddenKeywordCount: number
  keywordsExpanded: boolean
  deprecatedActive: boolean
}>()

const emit = defineEmits<{
  'toggle-platform': [os: string]
  'toggle-keyword': [keyword: string]
  'toggle-deprecated': []
  'toggle-expand': []
}>()
</script>

<template>
  <div class="filter-chips">
    <button
      v-for="os in OS_ORDER"
      :key="os"
      type="button"
      class="chip"
      tabindex="-1"
      :class="{ active: activePlatforms.includes(os) }"
      :aria-pressed="activePlatforms.includes(os)"
      @click="emit('toggle-platform', os)"
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path v-for="(p, i) in OS_GLYPHS[os].paths" :key="i" :d="p" />
        <rect v-for="(r, i) in OS_GLYPHS[os].rects" :key="i" :x="r.x" :y="r.y" :width="r.w" :height="r.h" />
      </svg>
      {{ os }}
      <span v-if="activePlatforms.includes(os)" class="chip-close">✕</span>
    </button>

    <span v-if="OS_ORDER.length" class="chip-divider" />

    <button
      v-for="kw in visibleKeywords"
      :key="kw.keyword"
      type="button"
      class="chip"
      tabindex="-1"
      :class="{ active: activeKeywords.includes(kw.keyword) }"
      :aria-pressed="activeKeywords.includes(kw.keyword)"
      @click="emit('toggle-keyword', kw.keyword)"
    >
      {{ kw.keyword }}
      <span v-if="activeKeywords.includes(kw.keyword)" class="chip-close">✕</span>
    </button>

    <button
      v-if="hiddenKeywordCount > 0 || keywordsExpanded"
      type="button"
      class="chip-more"
      tabindex="-1"
      @click="emit('toggle-expand')"
    >
      {{ keywordsExpanded ? 'show less' : `+${hiddenKeywordCount} more` }}
    </button>

    <button
      type="button"
      class="chip"
      tabindex="-1"
      :class="{ active: deprecatedActive }"
      :aria-pressed="deprecatedActive"
      @click="emit('toggle-deprecated')"
    >
      deprecated
      <span v-if="deprecatedActive" class="chip-close">✕</span>
    </button>
  </div>
</template>

<style scoped>
.filter-chips {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  flex-wrap: wrap;
}

.chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-text-2);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-full);
  padding: 4px 11px;
  background: var(--c-surface);
  cursor: pointer;
  transition:
    border-color 0.15s,
    color 0.15s,
    background-color 0.15s;
}

.chip:hover {
  color: var(--c-text-1);
}

.chip.active {
  color: var(--c-accent-hover);
  border-color: var(--c-accent-tint-border);
  background: var(--c-accent-tint-bg);
}

.chip-close {
  font-size: 10px;
}

.chip-more {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-text-3);
  background: none;
  border: none;
  padding: 4px 6px;
  cursor: pointer;
}

.chip-more:hover {
  color: var(--c-text-1);
}

.chip-divider {
  width: 1px;
  height: 18px;
  background: var(--c-line);
  margin: 0 4px;
  flex-shrink: 0;
}
</style>
