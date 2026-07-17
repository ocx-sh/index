<script setup lang="ts">
import { computed } from 'vue'
import { safeHref } from '../../utils/safeHref'

// MANDATORY whenever `upstream.disclaimer` is present — a governance
// invariant (adr_namespace_policy.md ND-9), never conditionally hidden.
// DetailPage owns the `v-if="root.upstream?.disclaimer"` gate; this
// component assumes it's always called with a real string.
const props = defineProps<{
  disclaimer: string
  repositoryUrl?: string
}>()

// `repositoryUrl` is third-party wire metadata — allowlist the scheme
// before it reaches an `:href` (CWE-79 guard, see `utils/safeHref.ts`).
// `null` degrades to plain text rather than dropping the line entirely.
const safeRepositoryUrl = computed(() => safeHref(props.repositoryUrl))
</script>

<template>
  <div class="disclaimer-banner">
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="disclaimer-icon">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="8" x2="12" y2="12" />
      <line x1="12" y1="16" x2="12.01" y2="16" />
    </svg>
    <span class="disclaimer-text">
      {{ disclaimer }}
      <template v-if="repositoryUrl">
        Upstream: <a v-if="safeRepositoryUrl" :href="safeRepositoryUrl" target="_blank" rel="noopener noreferrer">{{ repositoryUrl.replace(/^https?:\/\//, '') }} ↗</a><span v-else>{{ repositoryUrl.replace(/^https?:\/\//, '') }}</span>
      </template>
    </span>
  </div>
</template>

<style scoped>
.disclaimer-banner {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  background: var(--c-warn-bg);
  border: 1px solid color-mix(in srgb, var(--c-warn) 45%, transparent);
  border-radius: var(--radius-lg);
  padding: 10px 14px;
}

.disclaimer-icon {
  color: var(--c-warn);
  flex-shrink: 0;
  margin-top: 1px;
}

.disclaimer-text {
  font-family: var(--font-sans);
  font-size: var(--text-sm);
  line-height: 1.55;
  color: var(--c-text-1);
}

.disclaimer-text a {
  color: var(--c-accent);
}

.disclaimer-text a:hover {
  color: var(--c-accent-hover);
}
</style>
