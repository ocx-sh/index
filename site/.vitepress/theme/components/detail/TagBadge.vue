<script setup lang="ts">
import {
  ContextMenuRoot,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
} from 'reka-ui'
import { useCopyState } from '../../composables/useCopyState'
import CopyIcon from '../shared/CopyIcon.vue'

// Relocated verbatim from `components/TagBadge.vue` (pre-redesign) into
// `components/detail/` — WP-D owns this rework. The five copy actions'
// command strings + 1300/1500ms timing are UNCHANGED from the original.

// This component's template root is `<ContextMenuRoot>`, a reka-ui
// component that ships `inheritAttrs: false` and never forwards `$attrs`
// to its rendered slot content (confirmed against
// node_modules/reka-ui/dist/ContextMenu/ContextMenuRoot.js — its render
// function only spreads named props onto `MenuRoot`, nothing else). Vue's
// automatic attrs-fallthrough would otherwise land any caller-supplied,
// non-prop/non-emit listener (every `<TagBadge ... @mouseenter="...">` in
// VersionTree.vue — the hover-driven platform-matrix preview) on
// `ContextMenuRoot` itself, where reka-ui silently drops it: the hover
// never reaches the real DOM element at all (diagnosis: "detail page does
// not show the correct matrix of platforms" — confirmed via a synthetic
// `dispatchEvent('mouseenter', ...)` on the badge producing no effect).
// `inheritAttrs: false` + explicit `v-bind="$attrs"` on the actual
// interactive `<code>` element below re-targets the fallthrough past
// `ContextMenuRoot` to where it belongs — the standard Vue 3 fix for a
// non-forwarding wrapper root.
defineOptions({ inheritAttrs: false })

const props = withDefaults(defineProps<{
  tag: string
  qualifiedName: string
  variant?: 'default' | 'rolling' | 'minor' | 'child'
  /** Presence of `tags[tag].yanked` on the wire — struck + dashed amber,
   * never interactive-looking (still clickable/copyable; a yanked tag is
   * still a real, installable artifact, just discouraged). */
  yanked?: boolean
  /** `tags[tag].yanked.reason`, when known. Surfaced via the badge's own
   * `title` tooltip so a yank reason is reachable for every yanked badge —
   * not just patch-level ones nested in a minor-group popover with its own
   * dedicated reasons list (VersionTree.vue's `.yanked-reasons`). Ignored
   * when `yanked` is false. */
  yankedReason?: string
}>(), {
  variant: 'default',
  yanked: false,
  yankedReason: undefined,
})

const emit = defineEmits<{ copied: [] }>()

// useCopyState.ts's docstring names TagBadge as one of its intended
// consumers — the 1500ms copied-flag reset is its job now; the extra
// 1300ms `emit('copied')` timer (fires 200ms before the checkmark fades,
// so the popover it closes doesn't visibly outlast the badge's own
// feedback) stays TagBadge's own layer on top.
const { copied, copyText: copyViaState } = useCopyState(1500)

function addProjectCmd() {
  return `ocx add ${props.qualifiedName}:${props.tag}`
}

function addGlobalCmd() {
  return `ocx --global add ${props.qualifiedName}:${props.tag}`
}

function inspectCmd() {
  return `ocx package inspect ${props.qualifiedName}:${props.tag}`
}

// ponytail: tentative sixth action (plan_site_redesign.md WP-D deliverable
// text) — isolated in its own function + its own ContextMenuItem block below
// so dropping it is a two-line removal, not a refactor.
function execCmd() {
  return `ocx package exec ${props.qualifiedName}:${props.tag}`
}

async function copyText(text: string) {
  if (copied.value) return
  await copyViaState(text)
  setTimeout(() => emit('copied'), 1300) // start fade-out 200ms before checkmark ends
}

function identifier() {
  return `${props.qualifiedName}:${props.tag}`
}

function badgeTitle(): string {
  if (!props.yanked) return 'Click to copy identifier'
  return props.yankedReason ? `Yanked — ${props.yankedReason} — click to copy identifier` : 'Yanked — click to copy identifier'
}

async function handleClick() {
  await copyText(identifier())
}
</script>

<template>
  <ContextMenuRoot :modal="false">
    <ContextMenuTrigger as-child>
      <code
        class="tag-badge"
        :class="[variant, { copied, yanked }]"
        :title="badgeTitle()"
        v-bind="$attrs"
        @click="handleClick"
      >
        <span class="tag-text">{{ tag }}</span>
        <CopyIcon :copied="true" :size="12" check-class="tag-check" />
      </code>
    </ContextMenuTrigger>

    <ContextMenuContent class="ctx-menu">
        <ContextMenuItem class="ctx-item" @select="copyText(identifier())">
          <CopyIcon :copied="false" :size="14" />
          <span>Copy identifier</span>
        </ContextMenuItem>
        <ContextMenuItem class="ctx-item" @select="copyText(tag)">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
            <line x1="7" y1="7" x2="7.01" y2="7" />
          </svg>
          <span>Copy tag</span>
        </ContextMenuItem>
        <ContextMenuItem class="ctx-item" @select="copyText(addProjectCmd())">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
            <polyline points="7 10 12 15 17 10" />
            <line x1="12" y1="15" x2="12" y2="3" />
          </svg>
          <span>Add to project</span>
        </ContextMenuItem>
        <ContextMenuItem class="ctx-item" @select="copyText(addGlobalCmd())">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10" />
            <line x1="2" y1="12" x2="22" y2="12" />
            <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
          </svg>
          <span>Add globally</span>
        </ContextMenuItem>
        <ContextMenuItem class="ctx-item" @select="copyText(inspectCmd())">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <span>Inspect command</span>
        </ContextMenuItem>
        <!-- ponytail: tentative sixth item (plan: "easy to drop") — delete
             this block + `execCmd()` above to revert to the five verbatim
             actions. -->
        <ContextMenuItem class="ctx-item" @select="copyText(execCmd())">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="5 3 19 12 5 21 5 3" />
          </svg>
          <span>Exec command</span>
        </ContextMenuItem>
    </ContextMenuContent>
  </ContextMenuRoot>
</template>

<style scoped>
.tag-badge {
  position: relative;
  display: inline-flex;
  align-items: center;
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  background: var(--c-surface-2);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-sm);
  color: var(--c-text-2);
  cursor: pointer;
  transition: border-color 0.3s, color 0.3s, background 0.3s;
  user-select: none;
}

.tag-badge.rolling {
  font-weight: 600;
}

.tag-badge.child {
  font-size: var(--text-2xs);
  color: var(--c-text-3);
}

.tag-badge:hover {
  border-color: var(--c-accent);
  color: var(--c-accent);
}

.tag-text {
  transition: opacity 0.15s ease-in;
}

.tag-check {
  position: absolute;
  inset: 0;
  margin: auto;
  opacity: 0;
  transition: opacity 0.15s ease-in;
}

.tag-badge.copied {
  border-color: var(--c-ok);
  color: var(--c-ok);
}

.tag-badge.copied .tag-text {
  opacity: 0;
  transition: opacity 0.1s ease-out;
}

.tag-badge.copied .tag-check {
  opacity: 1;
  transition: opacity 0.1s ease-out;
}

/* Yanked — struck, dashed amber, muted (design mock 1c/1d). */
.tag-badge.yanked:not(.copied) {
  color: var(--c-text-3);
  border-style: dashed;
  border-color: var(--c-warn);
  text-decoration: line-through;
}
</style>

<style>
/* Context menu — unscoped so portal renders correctly */
.ctx-menu {
  min-width: 200px;
  padding: 0.35rem;
  background: var(--c-surface);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-lg);
  z-index: 100;
  animation: ctx-fade-in 0.12s ease-out;
}

.ctx-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.45rem 0.6rem;
  border-radius: var(--radius-sm);
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  color: var(--c-text-2);
  cursor: pointer;
  outline: none;
  transition: background 0.1s, color 0.1s;
}

.ctx-item:hover,
.ctx-item[data-highlighted] {
  background: var(--c-surface-2);
  color: var(--c-accent);
}

@keyframes ctx-fade-in {
  from { opacity: 0; transform: scale(0.96); }
  to { opacity: 1; transform: scale(1); }
}
</style>
