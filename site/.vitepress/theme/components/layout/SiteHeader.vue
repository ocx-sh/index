<script setup lang="ts">
import { useData, useRoute } from 'vitepress'
import Logo from './Logo.vue'
import ThemeToggle from './ThemeToggle.vue'
// WP-E additive edit: header-level ⌘K trigger, so the global palette is
// discoverable from every page (not just the catalog's own inline
// SearchInput, which is WP-C scope).
import { useCommandPalette } from '../../composables/useCommandPalette'

const { theme } = useData()
const route = useRoute()
const { open: openPalette } = useCommandPalette()

function isActive(prefix: string): boolean {
  if (prefix === '/docs/') return route.path.startsWith('/docs/')
  return !route.path.startsWith('/docs/')
}
</script>

<template>
  <header class="site-header">
    <a href="/" class="brand">
      <Logo class="brand-logo" />
      <span class="brand-name">index.ocx.sh</span>
    </a>
    <span class="header-spacer" />
    <nav class="site-nav">
      <a href="/" class="nav-link" :class="{ active: isActive('/') }">catalog</a>
      <a href="/docs/" class="nav-link" :class="{ active: isActive('/docs/') }">docs</a>
      <a :href="theme.githubUrl" target="_blank" rel="noopener noreferrer" class="nav-link">github ↗</a>
    </nav>
    <span class="nav-divider" />
    <button type="button" class="search-trigger" aria-label="Search (Ctrl+K)" @click="openPalette">
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
        <circle cx="11" cy="11" r="7" />
        <line x1="21" y1="21" x2="16.65" y2="16.65" />
      </svg>
      <span class="search-trigger-kbd">⌘K</span>
    </button>
    <ThemeToggle />
  </header>
</template>

<style scoped>
.site-header {
  height: 54px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 0 24px;
  border-bottom: 1px solid var(--c-line);
  background: var(--c-surface);
}

.brand {
  display: inline-flex;
  align-items: center;
  gap: 9px;
  color: var(--c-text-1);
}

.brand-logo {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
}

.brand-name {
  font-family: var(--font-mono);
  font-size: var(--text-base);
  font-weight: 600;
  color: var(--c-text-1);
}

.header-spacer {
  flex: 1;
}

.site-nav {
  display: inline-flex;
  gap: 22px;
  align-items: center;
}

.nav-link {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  font-weight: 500;
  color: var(--c-text-2);
  padding: 16px 1px 14px;
  border-bottom: 2px solid transparent;
}

.nav-link:hover {
  color: var(--c-text-1);
}

.nav-link.active {
  color: var(--c-accent);
  border-bottom-color: var(--c-accent);
}

.nav-divider {
  width: 1px;
  height: 20px;
  background: var(--c-line);
  flex-shrink: 0;
}

.search-trigger {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--c-text-3);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  padding: 4px 8px;
  background: none;
}

.search-trigger:hover {
  color: var(--c-text-1);
  border-color: var(--c-text-3);
}

.search-trigger-kbd {
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  font-weight: 500;
}

@media (max-width: 640px) {
  .site-header {
    gap: 12px;
    padding: 0 16px;
  }

  .brand-name {
    display: none;
  }

  .search-trigger-kbd {
    display: none;
  }
}
</style>
