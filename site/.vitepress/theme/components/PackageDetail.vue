<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vitepress'
import CopySnippet from './CopySnippet.vue'
import VersionTree from './VersionTree.vue'
import PlatformIcons from './PlatformIcons.vue'
import { casUrl, LOGO_EXT_CANDIDATES } from '../utils/cas'

// Adapted from ocx-sh/ocx's website theme (adr_catalog_docs_colocation.md):
// route prefix `/catalog/<name>` -> `/<name>` (catalog is the site root
// here); `hasLogo`/`logoExt` replaced by a bare CAS digest; `hasReadme`
// replaced by a CAS digest that becomes a "View README" link instead of an
// unused flag; `upstream.disclaimer` renders an attribution badge
// (ADR: adr_namespace_policy.md ND-9 — upstream attribution object).
interface UpstreamInfo {
  org: string
  repository_url?: string
  disclaimer?: string | null
}

interface PackageInfo {
  name: string
  registry: string
  repository: string
  title: string
  description: string
  keywords: string[]
  logo: string | null
  readme: string | null
  latestTag: string
  latestVersion: string
  tags: string[]
  platforms: string[]
  upstream?: UpstreamInfo | null
}

const route = useRoute()
// URL is `/<name>` where `<name>` may contain slashes (nested OCI repos,
// e.g. `ocx/cli`) — the catalog owns the site root, so there is no prefix
// to strip here (unlike the source theme's `/catalog/` prefix).
const pkgName = computed(() => {
  const path = route.path.replace(/\.html$/, '').replace(/^\//, '').replace(/\/$/, '')
  return path
})

const info = ref<PackageInfo | null>(null)
const loading = ref(true)
const error = ref('')
const notFound = ref(false)

const qualifiedName = computed(() => {
  if (!info.value) return ''
  const registry = info.value.registry || ''
  return registry ? `${registry}/${info.value.name}` : info.value.name
})

const latestVersion = computed(() => info.value?.latestVersion || info.value?.latestTag || '')

const addProjectCmd = computed(() => {
  if (!info.value) return ''
  const tag = latestVersion.value ? `:${latestVersion.value}` : ''
  return `ocx add ${qualifiedName.value}${tag}`
})

const addGlobalCmd = computed(() => {
  if (!info.value) return ''
  const tag = latestVersion.value ? `:${latestVersion.value}` : ''
  return `ocx --global add ${qualifiedName.value}${tag}`
})

// Logo extension attempt — see utils/cas.ts's ponytail note.
const logoAttempt = ref(0)

const logoSrc = computed(() => {
  if (!info.value) return null
  const ext = LOGO_EXT_CANDIDATES[logoAttempt.value]
  if (!ext) return null
  return casUrl(info.value.name, info.value.logo, ext)
})

function onLogoError() {
  logoAttempt.value += 1
}

// README is always a `.md` blob (ADR D2: `o/sha256/<hex>.{md,svg,png}`) —
// unlike the logo, no extension ambiguity.
const readmeUrl = computed(() => info.value ? casUrl(info.value.name, info.value.readme, 'md') : null)

onMounted(async () => {
  try {
    const resp = await fetch(`/data/catalog/packages/${pkgName.value}/info.json`)
    if (resp.status === 404) {
      notFound.value = true
      return
    }
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    info.value = await resp.json()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Failed to load package info'
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="pkg-detail">
    <!-- Loading -->
    <div v-if="loading" class="loading">
      <div class="spinner" />
      <span>Loading package info…</span>
    </div>

    <!-- Not found (404) — friendly, distinct from a genuine fetch error -->
    <div v-else-if="notFound" class="empty">
      <a href="/" class="back-link">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M19 12H5" />
          <polyline points="12 19 5 12 12 5" />
        </svg>
        All packages
      </a>
      <p>Package data not available.</p>
    </div>

    <!-- Error -->
    <div v-else-if="error" class="error">
      Failed to load package info: {{ error }}
    </div>

    <!-- Content -->
    <template v-else-if="info">
      <!-- Back link -->
      <a href="/" class="back-link">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M19 12H5" />
          <polyline points="12 19 5 12 12 5" />
        </svg>
        All packages
      </a>

      <!-- Header -->
      <div class="header">
        <img
          v-if="logoSrc"
          :src="logoSrc ?? undefined"
          :alt="`${info.title} logo`"
          class="header-logo"
          @error="onLogoError"
        >
        <div v-else class="header-logo-placeholder">
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
            <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
            <line x1="12" y1="22.08" x2="12" y2="12" />
          </svg>
        </div>
        <div class="header-text">
          <h1 class="header-title">{{ info.title }}</h1>
          <code v-if="qualifiedName" class="header-repo">{{ qualifiedName }}</code>

          <div v-if="info.upstream?.disclaimer" class="disclaimer-badge">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            {{ info.upstream.disclaimer }}
          </div>

          <div class="header-body">
            <div class="header-body-main">
              <p v-if="info.description" class="header-desc">
                {{ info.description }}
              </p>
              <div v-if="info.keywords.length" class="meta-group">
                <span class="meta-label">Keywords</span>
                <div class="meta-badges">
                  <span v-for="kw in info.keywords" :key="kw" class="keyword">{{ kw }}</span>
                </div>
              </div>

              <a v-if="readmeUrl" :href="readmeUrl" target="_blank" rel="noreferrer" class="readme-link">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                  <polyline points="14 2 14 8 20 8" />
                </svg>
                View README
              </a>

              <div class="header-add">
                <span class="meta-label">Add</span>
                <div class="add-row">
                  <span class="add-scope">Project</span>
                  <CopySnippet label="$" :code="addProjectCmd" fill />
                </div>
                <div class="add-row">
                  <span class="add-scope">Global</span>
                  <CopySnippet label="$" :code="addGlobalCmd" fill />
                </div>
              </div>
            </div>
            <div v-if="info.platforms.length" class="meta-group header-platforms">
              <span class="meta-label">Supported Platforms</span>
              <PlatformIcons :platforms="info.platforms" mode="os-arch" />
            </div>
          </div>
        </div>
      </div>

      <!-- Versions -->
      <div class="versions-section">
        <div class="versions-header">
          <h3 class="versions-title">Versions ({{ info.tags.length }})</h3>
          <span v-if="info.tags.length" class="versions-hint">Click to copy identifier. Right-click for more options.</span>
        </div>
        <VersionTree
          v-if="info.tags.length"
          :tags="info.tags"
          :qualified-name="qualifiedName"
        />
        <div v-else class="empty">
          No versions available.
        </div>
      </div>

    </template>
  </div>
</template>

<style scoped>
.pkg-detail {
  margin: 1rem 0;
}

/* Back link */
.back-link {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--vp-c-brand);
  text-decoration: none;
  margin-bottom: 1rem;
  transition: color 0.15s;
}

.back-link:hover {
  color: var(--vp-c-brand-dark);
}

/* Header */
.header {
  display: flex;
  align-items: flex-start;
  gap: 1.25rem;
  margin-bottom: 1.5rem;
  padding-bottom: 1.5rem;
  border-bottom: 1px solid var(--vp-c-divider);
}

.header-logo {
  width: 64px;
  height: 64px;
  object-fit: contain;
  flex-shrink: 0;
}

.header-logo-placeholder {
  width: 64px;
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  color: var(--vp-c-text-3);
}

.header-text {
  min-width: 0;
}

.header-title {
  font-size: 1.75rem;
  font-weight: 700;
  margin: 0 0 0.2rem;
  border: none;
  padding: 0;
  line-height: 1.3;
}

.header-repo {
  display: inline-block;
  font-family: var(--vp-font-family-mono);
  font-size: 0.8rem;
  color: var(--vp-c-text-3);
  background: var(--vp-c-bg-soft);
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  margin-bottom: 0.5rem;
}

/* Upstream not-affiliated disclaimer (ADR: adr_namespace_policy.md ND-9) */
.disclaimer-badge {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  color: var(--vp-c-text-2);
  background: var(--vp-c-warning-soft);
  border-radius: 6px;
  padding: 0.35rem 0.6rem;
  margin-bottom: 0.6rem;
  max-width: fit-content;
}

.disclaimer-badge svg {
  flex-shrink: 0;
  color: var(--vp-c-warning-1);
}

.header-desc {
  font-size: 0.95rem;
  color: var(--vp-c-text-2);
  margin: 0;
  line-height: 1.5;
}

/* Description + keywords on the left, supported platforms in a right column. */
.header-body {
  display: flex;
  align-items: flex-start;
  gap: 1.5rem;
}

.header-body-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
}

.header-platforms {
  flex-shrink: 0;
}

.meta-group {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.meta-label {
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--vp-c-text-3);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.meta-badges {
  display: flex;
  gap: 0.35rem;
  flex-wrap: wrap;
}

.keyword {
  font-size: 0.75rem;
  padding: 0.15rem 0.5rem;
  background: var(--vp-c-brand-soft);
  border-radius: 4px;
  color: var(--vp-c-brand-dark);
}

.readme-link {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--vp-c-brand);
  text-decoration: none;
  width: fit-content;
}

.readme-link:hover {
  color: var(--vp-c-brand-dark);
}

/* Add commands — single-line snippets stacked under the description/keywords,
   forming the left column beside the Supported Platforms rail. */
.header-add {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  margin-top: 0.3rem;
}

.add-row {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.add-scope {
  font-size: 0.75rem;
  color: var(--vp-c-text-3);
  min-width: 3.5rem;
  flex-shrink: 0;
}

/* Versions */
.versions-section {
  margin-bottom: 1.5rem;
}

.versions-title {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--vp-c-text-2);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  margin: 0;
  border: none;
  padding: 0;
}

.versions-header {
  margin-bottom: 0.75rem;
}

.versions-hint {
  display: block;
  font-size: 0.7rem;
  color: var(--vp-c-text-3);
  margin-top: -0.4rem;
}

/* Loading */
.loading {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 2rem;
  color: var(--vp-c-text-3);
  font-size: 0.875rem;
}

.spinner {
  width: 20px;
  height: 20px;
  border: 2px solid var(--vp-c-divider);
  border-top-color: var(--vp-c-brand);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

/* Error */
.error {
  padding: 1rem;
  background: var(--vp-c-danger-soft);
  color: var(--vp-c-danger-1);
  border-radius: 8px;
  font-size: 0.875rem;
}

/* Empty state */
.empty {
  padding: 2rem;
  text-align: center;
  color: var(--vp-c-text-3);
  font-size: 0.875rem;
}

/* Responsive */
@media (max-width: 640px) {
  .header {
    flex-direction: column;
    align-items: center;
    text-align: center;
  }

  .header-body {
    flex-direction: column;
    gap: 0.75rem;
    width: 100%;
  }

  .meta-badges {
    justify-content: center;
  }

  .add-row {
    flex-direction: column;
    align-items: stretch;
    gap: 0.25rem;
  }

  .add-scope {
    min-width: 0;
  }
}
</style>
