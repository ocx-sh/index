<script setup lang="ts">
import { computed } from 'vue'
import type { CatalogPackage } from '../../composables/useCatalog'
import { useImageFallback } from '../../composables/useImageFallback'
import { monogramHue, monogramInitials } from '../../utils/monogram'
import { OS_GLYPHS, osRank } from '../../utils/osGlyphs'
import MonogramTile from './MonogramTile.vue'
import InstallRow from './InstallRow.vue'

const props = defineProps<{ pkg: CatalogPackage }>()

/** Bare `<ns>/<pkg>` — the route path, the monogram hash input, and
 * `InstallRow`'s prop all use this, never `pkg.name` (which carries the
 * `ocx.sh/` prefix — same CAS-gotcha trap documented in `usePackageRoot`). */
const bareName = computed(() => `${props.pkg.namespace}/${props.pkg.package}`)

const hue = computed(() => monogramHue(bareName.value))
const initials = computed(() => monogramInitials(props.pkg.package))

// Tile fallback chain: logoUrl -> <img> (svg->png retry once on error) ->
// monogram -> cube placeholder. The cube branch is a defensive last
// resort for an empty-initials edge case (never expected in practice —
// `package` is non-empty per schema) rather than a designed "sometimes"
// toggle; the mock's own two example tile styles are visual variety in
// the fixture generator, not two independently-random UI states.
// `useImageFallback` owns the svg->png retry mechanics (shared with
// `IdentityBlock`'s logo chain); a non-svg `logoUrl` gets exactly one
// candidate — retrying the same URL after it already 404'd is pointless.
const logoCandidates = computed<(string | null)[]>(() => {
  const url = props.pkg.logoUrl
  if (!url) return []
  return url.endsWith('.svg') ? [url, url.replace(/\.svg$/, '.png')] : [url]
})
const { src: imgSrc, onError: onImgError } = useImageFallback(logoCandidates)

const showImg = computed(() => !!imgSrc.value)

const platforms = computed(() =>
  [...new Set(props.pkg.platforms.map(p => p.split('/')[0]))].sort((a, b) => osRank(a) - osRank(b)),
)
</script>

<template>
  <a :href="`/${bareName}`" class="package-card">
    <div class="card-header">
      <img v-if="showImg" :src="imgSrc!" alt="" class="card-tile-img" @error="onImgError">
      <MonogramTile v-else-if="initials" :hue="hue" :initials="initials" />
      <div v-else class="card-tile-cube">
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
          <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
          <line x1="12" y1="22.08" x2="12" y2="12" />
        </svg>
      </div>
      <div class="card-title-block">
        <div class="card-title-row">
          <span class="card-title">{{ pkg.title }}</span>
          <span v-if="pkg.latestVersion" class="card-version">{{ pkg.latestVersion }}</span>
          <span v-if="pkg.status === 'deprecated'" class="card-deprecated">DEPRECATED</span>
        </div>
        <div class="card-name">{{ bareName }}</div>
      </div>
    </div>

    <p class="card-desc">{{ pkg.description }}</p>

    <div class="card-meta">
      <span class="card-keywords">
        <span v-for="kw in pkg.keywords" :key="kw" class="card-keyword">{{ kw }}</span>
      </span>
      <span class="card-platforms">
        <svg
          v-for="os in platforms"
          :key="os"
          width="13"
          height="13"
          :viewBox="OS_GLYPHS[os]?.viewBox ?? '0 0 24 24'"
          fill="currentColor"
          :aria-label="OS_GLYPHS[os]?.label ?? os"
        >
          <path v-for="(p, i) in OS_GLYPHS[os]?.paths" :key="i" :d="p" />
          <rect v-for="(r, i) in OS_GLYPHS[os]?.rects" :key="i" :x="r.x" :y="r.y" :width="r.w" :height="r.h" />
        </svg>
        <span class="card-tag-count">{{ pkg.tagCount }} tags</span>
      </span>
    </div>

    <InstallRow :name="bareName" :latest-version="pkg.latestVersion" />
  </a>
</template>

<style scoped>
.package-card {
  display: flex;
  flex-direction: column;
  gap: 9px;
  background: var(--c-surface);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-lg);
  padding: 14px 14px 12px;
  color: inherit;
  transition: border-color 0.15s;
}

.package-card:hover,
.package-card:focus-visible {
  border-color: var(--c-accent);
}

.card-header {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.card-tile-img {
  width: 34px;
  height: 34px;
  flex-shrink: 0;
  border-radius: var(--radius-lg);
  object-fit: contain;
  background: var(--c-surface-2);
}

.card-tile-cube {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  flex-shrink: 0;
  border-radius: var(--radius-lg);
  background: var(--c-surface-2);
  color: var(--c-text-3);
}

.card-title-block {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.card-title-row {
  display: flex;
  align-items: baseline;
  gap: 8px;
}

.card-title {
  font-family: var(--font-sans);
  font-size: var(--text-md);
  font-weight: 600;
  line-height: 1.3;
  color: var(--c-text-1);
}

.card-version {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-text-3);
}

/* Same shape/sizing as IdentityBlock's `.identity-deprecated` badge, but
 * muted tokens instead of coral (`--c-accent-hover`) — a grid of cards is
 * not the place for the site's one interactive/highlight color (see
 * palette.css's "coral is the only interactive color" note); deprecated on
 * a card is a status fact, not a call to action. */
.card-deprecated {
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  font-weight: 600;
  color: var(--c-text-3);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-sm);
  padding: 2px 8px;
  letter-spacing: 0.05em;
}

.card-name {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--c-text-3);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.card-desc {
  margin: 0;
  font-family: var(--font-sans);
  font-size: var(--text-sm);
  line-height: 1.5;
  color: var(--c-text-2);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  min-height: 37px;
}

.card-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
}

.card-keywords {
  display: inline-flex;
  gap: 6px;
  flex-wrap: wrap;
}

.card-keyword {
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  font-weight: 500;
  color: var(--c-kw);
  background: var(--c-kw-bg);
  padding: 2px 7px;
  border-radius: var(--radius-sm);
}

.card-platforms {
  display: inline-flex;
  align-items: center;
  gap: 9px;
  color: var(--c-text-3);
  flex-shrink: 0;
}

.card-tag-count {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
}
</style>

<style>
/* Unscoped: `.install-row` lives inside `InstallRow.vue`'s own scoped
 * style, one component layer through `CopyContextMenu`'s slot passthrough —
 * a `scoped` selector here isn't guaranteed to reach across that boundary.
 * `:has()` gives `.package-card` here higher specificity than its own
 * `:hover` rule above (a `:has()` argument's specificity counts toward the
 * whole selector), so hovering the install box cancels the card's own
 * hover border without touching the box's unrelated hover style. */
.package-card:has(.install-row:hover) {
  border-color: var(--c-line);
}
</style>
