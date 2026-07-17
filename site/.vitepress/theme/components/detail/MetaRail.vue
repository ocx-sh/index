<script setup lang="ts">
import { computed, ref } from 'vue'
import { useCopyState } from '../../composables/useCopyState'
import { safeHref } from '../../utils/safeHref'
import PlatformMatrix from './PlatformMatrix.vue'
import CopyIcon from '../shared/CopyIcon.vue'
import type { PackageRoot } from '../../composables/usePackageRoot'
import type { ObservationObject } from '../../composables/useObservation'

const props = defineProps<{
  root: PackageRoot
  /** `root.name` — already `ocx.sh/`-prefixed, safe for CLI command strings
   * directly (unlike CAS URLs). */
  qualifiedName: string
  /** Default row's primary tag (`utils/version.ts`'s `buildVersionTable`
   * output) — `null` when the package has no live tag at all. */
  primaryTag: string | null
  latestVersionLabel: string | null
  activeObservation: ObservationObject | null
  tagCount: number
}>()

// Install card: toggle between "latest" (no tag suffix) and "pinned"
// (`:<primaryTag>`) only when there's a real distinction to toggle between
// — i.e. `primaryTag === 'latest'` AND a precise version alias exists.
// Otherwise a single (possibly de-emphasized, for a deprecated package)
// pinned row, matching design mock 1d.
const canToggle = computed(() => props.primaryTag === 'latest' && !!props.latestVersionLabel)
const mode = ref<'latest' | 'pinned'>('latest')

const installCommand = computed(() => {
  if (canToggle.value) {
    return mode.value === 'latest'
      ? `ocx add ${props.qualifiedName}`
      : `ocx add ${props.qualifiedName}:${props.latestVersionLabel}`
  }
  if (props.primaryTag) return `ocx add ${props.qualifiedName}:${props.primaryTag}`
  return null
})

const { copied, copyText } = useCopyState(1500)

const owners = computed(() => props.root.owners)

// `upstream.repository_url` is third-party metadata (wire-sourced, not
// authored here) — allowlist the scheme before it ever reaches an `:href`
// (CWE-79 guard, see `utils/safeHref.ts`). `null` degrades to plain text.
const safeUpstreamUrl = computed(() => safeHref(props.root.upstream?.repository_url))
</script>

<template>
  <div class="meta-rail">
    <div class="rail-card">
      <span class="rail-heading">INSTALL</span>

      <div v-if="installCommand" class="install-toggle-wrap">
        <span v-if="canToggle" class="install-toggle">
          <button type="button" :class="{ active: mode === 'latest' }" @click="mode = 'latest'">latest</button>
          <button type="button" :class="{ active: mode === 'pinned' }" @click="mode = 'pinned'">pinned :{{ latestVersionLabel }}</button>
        </span>
        <button
          type="button"
          class="install-command"
          :class="{ copied, deemphasized: root.status === 'deprecated' }"
          @click="copyText(installCommand)"
        >
          <span class="install-prefix">$</span>
          <span class="install-cmd">{{ installCommand }}</span>
          <CopyIcon :copied="copied" />
        </button>
      </div>
      <p v-else class="rail-empty">No installable version.</p>
    </div>

    <div class="rail-card">
      <span class="rail-heading">PLATFORMS</span>
      <PlatformMatrix :platforms="activeObservation?.platforms ?? []" />
    </div>

    <div class="rail-card">
      <span class="rail-heading">METADATA</span>
      <div class="metadata-rows">
        <div class="metadata-row">
          <span class="metadata-key">registry</span>
          <span class="metadata-value truncate">{{ root.repository }}</span>
        </div>
        <div class="metadata-row">
          <span class="metadata-key">owners</span>
          <span class="metadata-value">
            <a v-for="(owner, i) in owners" :key="owner.github" :href="`https://github.com/${owner.github}`" target="_blank" rel="noopener noreferrer">
              @{{ owner.github }}<template v-if="i < owners.length - 1">, </template>
            </a>
          </span>
        </div>
        <div v-if="root.upstream" class="metadata-row">
          <span class="metadata-key">upstream</span>
          <a v-if="safeUpstreamUrl" class="metadata-value" :href="safeUpstreamUrl" target="_blank" rel="noopener noreferrer">{{ root.upstream.org }} ↗</a>
          <span v-else class="metadata-value">{{ root.upstream.org }}</span>
        </div>
        <div v-if="latestVersionLabel" class="metadata-row">
          <span class="metadata-key">latest</span>
          <span class="metadata-value plain">{{ latestVersionLabel }}</span>
        </div>
        <div class="metadata-row">
          <span class="metadata-key">tags</span>
          <span class="metadata-value plain">{{ tagCount }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.meta-rail {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.rail-card {
  background: var(--c-surface);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-lg);
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.rail-heading {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 600;
  color: var(--c-text-3);
  letter-spacing: 0.06em;
}

.rail-empty {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--c-text-3);
  margin: 0;
}

.install-toggle-wrap {
  display: flex;
  flex-direction: column;
  gap: 9px;
}

.install-toggle {
  display: inline-flex;
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  overflow: hidden;
  width: fit-content;
}

.install-toggle button {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-text-2);
  background: none;
  border: none;
  padding: 4px 10px;
  cursor: pointer;
}

.install-toggle button + button {
  border-left: 1px solid var(--c-line);
}

.install-toggle button.active {
  color: var(--c-accent);
  background: color-mix(in srgb, var(--c-accent) 8%, transparent);
}

.install-command {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  background: var(--c-surface-2);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  padding: 7px 10px;
  font-family: var(--font-mono);
  cursor: pointer;
  transition: border-color 0.15s;
  text-align: left;
}

.install-command:hover,
.install-command:focus-visible {
  border-color: var(--c-accent);
}

.install-command.deemphasized {
  opacity: 0.75;
}

.install-prefix {
  color: var(--c-accent);
  font-weight: 600;
  font-size: var(--text-xs);
  flex-shrink: 0;
}

.install-cmd {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--text-xs);
  color: var(--c-text-1);
}

.install-command svg {
  flex-shrink: 0;
  color: var(--c-text-3);
}

.install-command.copied {
  border-color: var(--c-ok);
}

.install-command.copied .install-cmd {
  color: var(--c-ok);
}

.install-command.copied svg {
  color: var(--c-ok);
}

.metadata-rows {
  display: flex;
  flex-direction: column;
  gap: 7px;
  font-family: var(--font-mono);
  font-size: var(--text-xs);
}

.metadata-row {
  display: flex;
  gap: 8px;
}

.metadata-key {
  color: var(--c-text-3);
  width: 74px;
  flex-shrink: 0;
}

.metadata-value {
  color: var(--c-accent);
  min-width: 0;
}

.metadata-value.plain {
  color: var(--c-text-1);
}

.metadata-value.truncate {
  color: var(--c-text-1);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
