<script setup lang="ts">
import { computed, ref } from 'vue'
import { useClipboard } from '@vueuse/core'
import { safeHref } from '../../utils/safeHref'
import PlatformMatrix from './PlatformMatrix.vue'
import CopyIcon from '../shared/CopyIcon.vue'
import CopyContextMenu, { buildTagCopyActions, type CopyAction } from '../shared/CopyContextMenu.vue'
import type { PackageRoot } from '../../composables/usePackageRoot'
import type { ImageIndex } from '../../composables/useImageIndex'

const props = defineProps<{
  root: PackageRoot
  /** `root.name` — already `ocx.sh/`-prefixed, safe for CLI command strings
   * directly (unlike CAS URLs). */
  qualifiedName: string
  /** Default row's primary tag (`utils/version.ts`'s `buildVersionTable`
   * output) — `null` when the package has no live tag at all. */
  primaryTag: string | null
  latestVersionLabel: string | null
  activeImageIndex: ImageIndex | null
  tagCount: number
}>()

// Install card: toggle between "latest" (no tag suffix) and "pinned"
// (`:<primaryTag>`) only when there's a real distinction to toggle between
// — i.e. `primaryTag === 'latest'` AND a precise version alias exists.
// Otherwise a single (possibly de-emphasized, for a deprecated package)
// pinned row, matching design mock 1d.
const canToggle = computed(() => props.primaryTag === 'latest' && !!props.latestVersionLabel)
const mode = ref<'latest' | 'pinned'>('latest')

// Context-menu target = the same tag the card currently denotes.
const effectiveTag = computed(() => {
  if (canToggle.value) return mode.value === 'pinned' ? props.latestVersionLabel : 'latest'
  return props.primaryTag
})

const menuActions = computed<CopyAction[]>(() =>
  effectiveTag.value ? buildTagCopyActions(props.qualifiedName, effectiveTag.value) : [],
)

// What the install commands operate on: bare qualified name in "latest"
// mode (matches `ocx add <name>` semantics), `name:tag` otherwise.
const installTarget = computed(() => {
  if (canToggle.value && mode.value === 'latest') return props.qualifiedName
  return effectiveTag.value ? `${props.qualifiedName}:${effectiveTag.value}` : null
})

interface InstallRowDef {
  key: 'local' | 'global' | 'exec' | 'install'
  icon: InstallRowDef['key']
  title: string
  command: string
}

// One row per install flavor (icon column | command bar) — owner spec:
// grid, not a toggle. Icon meanings match CopyContextMenu's action icons.
const installRows = computed<InstallRowDef[]>(() => {
  const target = installTarget.value
  if (!target) return []
  return [
    { key: 'local', icon: 'local', title: 'Add to project', command: `ocx add ${target}` },
    { key: 'global', icon: 'global', title: 'Add globally', command: `ocx --global add ${target}` },
    { key: 'exec', icon: 'exec', title: 'Run without installing', command: `ocx package exec ${target}` },
    { key: 'install', icon: 'install', title: 'Install package', command: `ocx package install ${target}` },
  ]
})

// Per-row copied feedback — a single shared flag would flash every bar at
// once, so track which row copied last.
const { copy: clipboardCopy } = useClipboard()
const copiedKey = ref<string | null>(null)
let copiedTimer: ReturnType<typeof setTimeout> | null = null

async function copyRow(key: string, text: string) {
  await clipboardCopy(text)
  copiedKey.value = key
  if (copiedTimer) clearTimeout(copiedTimer)
  copiedTimer = setTimeout(() => {
    copiedKey.value = null
  }, 1500)
}

const owners = computed(() => props.root.owners)

// `upstream.repository_url` is third-party metadata (wire-sourced, not
// authored here) — allowlist the scheme before it ever reaches an `:href`
// (CWE-79 guard, see `utils/safeHref.ts`). `null` degrades to plain text.
const safeUpstreamUrl = computed(() => safeHref(props.root.upstream?.repository_url))

// `source` = the repo whose CI built the artifacts (bot-derived from the
// registry annotation), a different thing from `upstream` above (the vendor
// a mirror attributes) — hence its own row, its own label, its own tooltip.
// Registry-sourced URL text, so the same CWE-79 guard applies; unlike
// `upstream` there is no org name to degrade to, so an unsafe value drops
// the whole row rather than printing the raw string.
const safeSourceUrl = computed(() => safeHref(props.root.source))
</script>

<template>
  <div class="meta-rail">
    <div class="rail-block">
      <div class="rail-header">
        <span class="rail-heading">INSTALL</span>
      </div>
      <div class="rail-card">
        <div v-if="installRows.length" class="install-toggle-wrap">
          <span v-if="canToggle" class="install-toggle">
            <button type="button" :class="{ active: mode === 'latest' }" @click="mode = 'latest'">latest</button>
            <button type="button" :class="{ active: mode === 'pinned' }" @click="mode = 'pinned'">pinned :{{ latestVersionLabel }}</button>
          </span>
          <div class="install-grid">
            <template v-for="row in installRows" :key="row.key">
              <span class="install-icon" :title="row.title">
                <svg v-if="row.icon === 'local'" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" /></svg>
                <svg v-else-if="row.icon === 'global'" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10" /><line x1="2" y1="12" x2="22" y2="12" /><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" /></svg>
                <svg v-else-if="row.icon === 'exec'" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3" /></svg>
                <svg v-else width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></svg>
              </span>
              <CopyContextMenu :actions="menuActions" :copy-text="text => copyRow(row.key, text)">
                <button
                  type="button"
                  class="install-command"
                  :class="{ copied: copiedKey === row.key, deemphasized: root.status === 'deprecated' }"
                  :title="row.title"
                  @click="copyRow(row.key, row.command)"
                >
                  <span class="install-prefix">$</span>
                  <span class="install-cmd">{{ row.command }}</span>
                  <CopyIcon :copied="copiedKey === row.key" />
                </button>
              </CopyContextMenu>
            </template>
          </div>
        </div>
        <p v-else class="rail-empty">No installable version.</p>
      </div>
    </div>

    <div class="rail-block">
      <div class="rail-header">
        <span class="rail-heading">PLATFORMS</span>
      </div>
      <div class="rail-card">
        <PlatformMatrix :platforms="activeImageIndex?.manifests ?? []" />
      </div>
    </div>

    <div class="rail-block">
      <div class="rail-header">
        <span class="rail-heading">METADATA</span>
      </div>
      <div class="rail-card">
        <div class="metadata-rows">
          <div class="metadata-row">
            <span class="metadata-key">registry</span>
            <span class="metadata-value truncate">{{ root.repository }}</span>
          </div>
          <div v-if="safeSourceUrl" class="metadata-row">
            <span class="metadata-key" title="Repository whose CI built these artifacts">source</span>
            <a class="metadata-value truncate link" :href="safeSourceUrl" target="_blank" rel="noopener noreferrer">{{ safeSourceUrl }} ↗</a>
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
  </div>
</template>

<style scoped>
.meta-rail {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

/* Header OUTSIDE the box — mirrors the left column's versions-header /
   versions-card split (DetailPage.vue) so the two columns' first boxes
   line up: same header font-size + same 10px header-to-box gap on both
   sides (user finding: rail cards should match the left column's style,
   and the two first boxes should align vertically). */
.rail-block {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.rail-header {
  display: flex;
  align-items: baseline;
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
  /* Matches .rail-card's 14px top padding — toggle sits as far from the
     grid below as from the card border above. */
  gap: 14px;
}

.install-toggle {
  display: inline-flex;
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  overflow: hidden;
  width: fit-content;
  align-self: center;
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

.install-grid {
  display: grid;
  /* Icon column | command bar. CopyContextMenu's trigger is renderless
     (`as-child`), so the slotted .install-command is the grid item itself.
     Column gap matches .rail-card's 16px horizontal padding so the icon
     sits visually centered between the card's left border and the bar. */
  grid-template-columns: auto 1fr;
  gap: 6px 16px;
  align-items: stretch;
}

.install-icon {
  display: flex;
  align-items: center;
  justify-content: flex-start;
  color: var(--c-text-3);
}

.install-grid .install-command {
  width: auto;
  min-width: 0;
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

/* Truncated *and* clickable (the source row) — keep the link color the
   `registry` row's plain treatment would otherwise override. */
.metadata-value.truncate.link {
  color: var(--c-accent);
}
</style>
