<script setup lang="ts">
import { onMounted, ref } from 'vue'

const props = defineProps<{
  total: number
  filtered: number
  /** Active FILTER CHIP labels only (platforms/keywords/deprecated) — not
   * the free-text search query, which has its own "clear search" affordance
   * in `EmptyState`'s no-match variant. */
  activeFilterLabels: string[]
  /** `catalog.generated` — lexicographic-max ISO timestamp, or null. */
  generated: string | null
}>()

defineEmits<{ 'clear-filters': [] }>()

// Relative-time math reads `Date.now()` — computed post-mount only so SSR
// output and the first client render agree (no hydration mismatch).
const updatedLabel = ref<string | null>(null)

onMounted(() => {
  if (!props.generated) return
  const then = new Date(props.generated).getTime()
  if (Number.isNaN(then)) return
  const minutes = Math.max(0, Math.floor((Date.now() - then) / 60_000))
  if (minutes < 1) {
    updatedLabel.value = 'just now'
  } else if (minutes < 60) {
    updatedLabel.value = `${minutes}m ago`
  } else if (minutes < 60 * 24) {
    updatedLabel.value = `${Math.floor(minutes / 60)}h ago`
  } else {
    updatedLabel.value = `${Math.floor(minutes / (60 * 24))}d ago`
  }
})
</script>

<template>
  <div class="result-meta">
    <span class="count">{{ filtered === total ? `${total} packages` : `${filtered} of ${total} packages` }}</span>
    <span class="filters">{{ activeFilterLabels.length ? activeFilterLabels.join(' · ') : 'sorted by name' }}</span>
    <button v-if="activeFilterLabels.length" type="button" class="clear-btn" tabindex="-1" @click="$emit('clear-filters')">
      clear filters
    </button>
    <span class="spacer" />
    <span v-if="updatedLabel" class="updated">updated {{ updatedLabel }}</span>
  </div>
</template>

<style scoped>
.result-meta {
  display: flex;
  align-items: baseline;
  gap: var(--space-3);
  flex-wrap: wrap;
}

.count {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  font-weight: 600;
  color: var(--c-text-1);
}

.filters,
.updated {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--c-text-3);
}

.clear-btn {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-accent);
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
}

.clear-btn:hover {
  color: var(--c-accent-hover);
}

.spacer {
  flex: 1;
}
</style>
