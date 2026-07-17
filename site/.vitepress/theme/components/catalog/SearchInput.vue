<script setup lang="ts">
import { ref } from 'vue'

// Design mock 1a: 44px search field, "/" badge. The badge is decorative
// only — the actual global ⌘K command palette is WP-E's
// `useCommandPalette`, a separate module this component never imports (see
// plan_site_redesign.md's frozen "/" decision). This component only
// exposes `focus()` for CatalogPage's page-scoped "/" handler to call.

defineProps<{ modelValue: string }>()
defineEmits<{ 'update:modelValue': [value: string] }>()

const inputEl = ref<HTMLInputElement | null>(null)

defineExpose({
  focus: () => inputEl.value?.focus(),
})
</script>

<template>
  <div class="search-input">
    <svg
      class="search-icon"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
    >
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
    <input
      ref="inputEl"
      type="text"
      class="search-field"
      placeholder="search packages — name, keyword, description…"
      :value="modelValue"
      @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    >
    <span class="search-kbd">/</span>
  </div>
</template>

<style scoped>
.search-input {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  height: 44px;
  padding: 0 14px;
  background: var(--c-surface);
  border: 1.5px solid var(--c-line);
  border-radius: var(--radius-lg);
  transition: border-color 0.15s;
}

.search-input:focus-within {
  border-color: var(--c-accent);
}

.search-icon {
  flex-shrink: 0;
  color: var(--c-text-3);
}

.search-field {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: none;
  font-family: var(--font-mono);
  font-size: var(--text-base);
  color: var(--c-text-1);
}

.search-field::placeholder {
  color: var(--c-text-3);
}

.search-kbd {
  flex-shrink: 0;
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  font-weight: 500;
  color: var(--c-text-3);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-sm);
  padding: 2px 6px;
  background: var(--c-surface-2);
}
</style>
