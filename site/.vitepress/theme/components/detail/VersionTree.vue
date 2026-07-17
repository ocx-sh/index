<script setup lang="ts">
import { reactive, ref, computed } from 'vue'
import {
  CollapsibleRoot,
  CollapsibleTrigger,
  CollapsibleContent,
  PopoverRoot,
  PopoverTrigger,
  PopoverPortal,
  PopoverContent,
} from 'reka-ui'
import TagBadge from './TagBadge.vue'
import CopyIcon from '../shared/CopyIcon.vue'
import { useCopyState } from '../../composables/useCopyState'
import type { MinorGroup, VariantRow, VersionTable } from '../../utils/version'

// Relocated + reworked from `components/VersionTree.vue` (pre-redesign).
// WP-D is the single owner of `buildVersionTable`'s redesign (plan
// "Version-table ownership") — this component only renders its output.
// `table` is pre-built by `DetailPage` (which already calls
// `buildVersionTable` once for its own derived state) and passed down —
// this component never calls `buildVersionTable` itself, so the table is
// computed exactly once per package load, not once per consumer.
const props = defineProps<{
  table: VersionTable
  status: 'active' | 'deprecated' | 'yanked'
  /** `root.name` — already carries the `ocx.sh/` prefix, safe to use
   * directly as the copy-command identifier (unlike CAS URLs, which need
   * the bare `<ns>/<pkg>` route params instead — see `usePackageRoot`'s
   * CAS-gotcha docblock). */
  qualifiedName: string
}>()

const emit = defineEmits<{
  /** Fired on hover/focus of any rendered tag, carrying its observation
   * digest — `DetailPage` debounces this into a `useObservation().load()`
   * call to drive `MetaRail`'s Platforms card (mock 1c: "per-version matrix
   * on tag hover"). */
  'hover-tag': [digest: string]
}>()

/** Digest to revert to on mouseleave — the default row's own primary tag,
 * so hovering away from the tree falls back to the package's eager-loaded
 * observation rather than leaving the last-hovered tag's platforms shown. */
const defaultPrimaryDigest = computed(() => {
  const row = props.table.rows.find(r => r.isDefault)
  if (!row?.primaryTag) return null
  return row.aliasChain.find(m => m.tag === row.primaryTag)?.digest ?? null
})

// `PopoverContent` below renders through `PopoverPortal` — teleported to
// `document.body`, outside `.version-table`'s DOM subtree (and, since it's
// `position`-anchored to the trigger rather than laid out inline, usually
// outside `.version-table`'s bounding box too). Moving the pointer from a
// minor-group's popover trigger into the popover's own patch badges
// therefore crosses `.version-table`'s rendered edge and fires this
// `mouseleave` mid-hover — reverting the platform-matrix preview back to
// the default digest before the patch badge's own `hover-tag` ever lands
// (contributing cause, alongside TagBadge.vue's `$attrs` fix, of
// "platform matrix doesn't show the right platforms" for any tag reachable
// only via a minor-group popover). Guarded on `openPopovers` (already
// tracked below for the copy-closes-popover behavior) so a leave that's
// really "into an open popover" is a no-op.
function handleLeave() {
  if ([...openPopovers.values()].some(Boolean)) return
  if (defaultPrimaryDigest.value) emit('hover-tag', defaultPrimaryDigest.value)
}

const { copied: aliasCopied, copyText: copyAliasText } = useCopyState(1500)
const lastCopiedAliasTag = ref<string | null>(null)

function copyAliasMember(tag: string) {
  lastCopiedAliasTag.value = tag
  copyAliasText(`${props.qualifiedName}:${tag}`)
}

// Track open state of minor popovers so we can close on copy
const openPopovers = reactive(new Map<string, boolean>())

function isPopoverOpen(key: string): boolean {
  return openPopovers.get(key) ?? false
}

// Track popovers that are closing (for exit animation)
const closingPopovers = reactive(new Set<string>())

function closePopover(key: string) {
  closingPopovers.add(key)
  setTimeout(() => {
    openPopovers.set(key, false)
  }, 200)
}

// Clean up closing state when popover actually closes
function handlePopoverUpdate(key: string, open: boolean) {
  openPopovers.set(key, open)
  if (open) closingPopovers.delete(key)
}

function isClosing(key: string): boolean {
  return closingPopovers.has(key)
}

function hasBreakdown(row: VariantRow): boolean {
  return row.majorGroups.length > 0
}

function remainingCount(row: VariantRow): number {
  let count = 0
  for (const mg of row.majorGroups) {
    if (mg.majorTag) count++
    for (const minor of mg.minorGroups) {
      count += 1 + minor.patches.length
    }
  }
  return count
}

function minorKey(major: number, minor: MinorGroup): string {
  return `${major}:${minor.minorTag}`
}

function patchLabel(count: number): string {
  return count === 1 ? '1 PATCH RELEASE' : `${count} PATCH RELEASES`
}
</script>

<template>
  <div class="version-table" @mouseleave="handleLeave">
    <CollapsibleRoot
      v-for="row in table.rows"
      :key="row.label"
      class="variant-row"
    >
      <div class="variant-row-header">
        <span class="variant-label" :class="{ default: row.isDefault }">
          <template v-if="row.isDefault">(default)</template>
          <template v-else>{{ row.label }}</template>
        </span>

        <span v-if="row.aliasChain.length" class="alias-chain">
          <button
            v-for="member in row.aliasChain"
            :key="member.tag"
            type="button"
            class="alias-segment"
            :class="{
              latest: row.showLatestHighlight && member.tag === 'latest',
              copied: aliasCopied && lastCopiedAliasTag === member.tag,
            }"
            @click="copyAliasMember(member.tag)"
            @mouseenter="emit('hover-tag', member.digest)"
          >
            <span class="alias-text">{{ member.tag }}</span>
            <CopyIcon :copied="true" :size="11" check-class="alias-check" />
          </button>
        </span>

        <!-- Yanked rolling tags (e.g. a yanked "latest") never make the
             live alias chain, but yanking one must still be visible —
             render struck-through/dashed-amber right next to the chain
             (TagBadge's existing yanked styling). -->
        <span v-if="row.yankedRolling.length" class="yanked-rolling">
          <TagBadge
            v-for="rt in row.yankedRolling"
            :key="rt.tag"
            :tag="rt.tag"
            :qualified-name="qualifiedName"
            variant="rolling"
            :yanked="true"
            @mouseenter="emit('hover-tag', rt.digest)"
          />
        </span>

        <span v-if="row.aliasChain.length > 1" class="alias-hint">= same digest, one copy target</span>
        <span v-else-if="row.isDefault && status === 'deprecated'" class="alias-hint">no "latest" tag — deprecated</span>

        <span class="row-spacer" />

        <CollapsibleTrigger v-if="hasBreakdown(row)" class="expand-toggle">
          <span class="expand-count">{{ remainingCount(row) }}</span>
          <svg class="chevron" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9" /></svg>
        </CollapsibleTrigger>
      </div>

      <CollapsibleContent v-if="hasBreakdown(row)" class="variant-row-detail">
        <div class="major-groups">
          <div
            v-for="mg in row.majorGroups"
            :key="mg.major"
            class="major-group"
          >
            <!-- Major version tag as row header -->
            <div class="major-header">
              <TagBadge
                v-if="mg.majorTag"
                :tag="mg.majorTag"
                :qualified-name="qualifiedName"
                variant="rolling"
                :yanked="!!mg.yanked"
                @mouseenter="mg.digest && emit('hover-tag', mg.digest)"
              />
              <span v-else class="major-number">{{ mg.major }}</span>
            </div>
            <!-- Minor groups for this major -->
            <div v-if="mg.minorGroups.length" class="minor-groups">
              <div
                v-for="minor in mg.minorGroups"
                :key="minor.minorTag"
                class="minor-group"
              >
                <TagBadge
                  :tag="minor.minorTag"
                  :qualified-name="qualifiedName"
                  variant="minor"
                  :yanked="!!minor.yanked"
                  @mouseenter="minor.digest && emit('hover-tag', minor.digest)"
                />
                <PopoverRoot
                  v-if="minor.patches.length"
                  :open="isPopoverOpen(minorKey(mg.major, minor))"
                  @update:open="handlePopoverUpdate(minorKey(mg.major, minor), $event)"
                >
                  <PopoverTrigger class="expand-toggle minor-toggle">
                    <svg class="chevron" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9" /></svg>
                    <span class="expand-count">·{{ minor.patches.length }}</span>
                  </PopoverTrigger>
                  <PopoverPortal>
                    <PopoverContent class="minor-popover" :class="{ closing: isClosing(minorKey(mg.major, minor)) }" side="bottom" align="start" :side-offset="4">
                      <span class="popover-title">{{ minor.minorTag }} — {{ patchLabel(minor.patches.length) }}</span>
                      <div class="minor-children">
                        <TagBadge
                          v-for="patch in minor.patches"
                          :key="patch.tag"
                          :tag="patch.tag"
                          :qualified-name="qualifiedName"
                          variant="child"
                          :yanked="!!patch.yanked"
                          @mouseenter="emit('hover-tag', patch.digest)"
                          @copied="closePopover(minorKey(mg.major, minor))"
                        />
                      </div>
                      <div class="yanked-reasons">
                        <span v-for="patch in minor.patches.filter(p => p.yanked)" :key="patch.tag" class="yanked-reason">
                          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" /><line x1="12" y1="9" x2="12" y2="13" /><line x1="12" y1="17" x2="12.01" y2="17" /></svg>
                          {{ patch.tag }} yanked — {{ patch.yanked!.reason }} · {{ patch.yanked!.at.slice(0, 10) }}
                        </span>
                      </div>
                    </PopoverContent>
                  </PopoverPortal>
                </PopoverRoot>
              </div>
            </div>
          </div>
        </div>
      </CollapsibleContent>
    </CollapsibleRoot>

    <!-- Unknown tags row -->
    <CollapsibleRoot
      v-if="table.unknownTags.length"
      class="variant-row unknown-row"
    >
      <div class="variant-row-header">
        <span class="variant-label other">other</span>
        <div class="key-tags">
          <TagBadge
            v-for="tag in table.unknownTags.slice(0, 5)"
            :key="tag.tag"
            :tag="tag.tag"
            :qualified-name="qualifiedName"
            :yanked="!!tag.yanked"
            @mouseenter="emit('hover-tag', tag.digest)"
          />
        </div>
        <CollapsibleTrigger
          v-if="table.unknownTags.length > 5"
          class="expand-toggle"
        >
          <span class="expand-count">+{{ table.unknownTags.length - 5 }}</span>
          <svg class="chevron" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9" /></svg>
        </CollapsibleTrigger>
      </div>
      <CollapsibleContent v-if="table.unknownTags.length > 5" class="variant-row-detail">
        <div class="detail-section">
          <div class="tag-row">
            <TagBadge
              v-for="tag in table.unknownTags.slice(5)"
              :key="tag.tag"
              :tag="tag.tag"
              :qualified-name="qualifiedName"
              :yanked="!!tag.yanked"
              @mouseenter="emit('hover-tag', tag.digest)"
            />
          </div>
        </div>
      </CollapsibleContent>
    </CollapsibleRoot>
  </div>
</template>

<style scoped>
/* Tag rows */
.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  align-items: center;
}

/* Table layout */
.version-table {
  display: flex;
  flex-direction: column;
}

/* Variant row */
.variant-row {
  border-bottom: 1px solid var(--c-line);
}

.variant-row:last-child {
  border-bottom: none;
}

.variant-row-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0;
  min-height: 2.25rem;
  flex-wrap: wrap;
}

.variant-label {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 600;
  color: var(--c-text-1);
  min-width: 5rem;
  flex-shrink: 0;
}

.variant-label.default {
  color: var(--c-text-3);
  font-style: italic;
  font-weight: 400;
}

.variant-label.other {
  color: var(--c-text-3);
  font-style: italic;
  font-weight: 400;
}

/* Segmented alias-chain control (design mock 1c). */
.alias-chain {
  display: inline-flex;
  align-items: stretch;
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  overflow: hidden;
}

.alias-segment {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 500;
  color: var(--c-text-2);
  background: none;
  border: none;
  border-left: 1px solid var(--c-line);
  padding: 0.25rem 0.6rem;
  cursor: pointer;
}

.alias-segment:first-child {
  border-left: none;
}

.alias-segment:hover {
  color: var(--c-accent);
}

.alias-segment.latest {
  color: var(--c-accent);
  font-weight: 600;
  background: color-mix(in srgb, var(--c-accent) 8%, transparent);
}

/* Copy feedback — check-icon fade (unified with TagBadge's pattern, not a
   text-color highlight — see components/shared/CopyIcon.vue docblock). */
.alias-text {
  transition: opacity 0.15s ease-in;
}

.alias-check {
  position: absolute;
  inset: 0;
  margin: auto;
  opacity: 0;
  color: var(--c-ok);
  transition: opacity 0.15s ease-in;
}

.alias-segment.copied .alias-text {
  opacity: 0;
  transition: opacity 0.1s ease-out;
}

.alias-segment.copied .alias-check {
  opacity: 1;
  transition: opacity 0.1s ease-out;
}

/* Yanked rolling tags (e.g. a yanked "latest") — sit next to the
   alias-chain control; TagBadge's own `.yanked` modifier carries the
   struck-through/dashed-amber styling. */
.yanked-rolling {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.alias-hint {
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  color: var(--c-text-3);
}

.row-spacer {
  flex: 1;
}

.key-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  align-items: center;
  flex: 1;
  min-width: 0;
}

/* Expand toggle (variant row + minor group) */
.expand-toggle {
  display: inline-flex;
  align-items: center;
  gap: 0.15rem;
  padding: 0.2rem 0.4rem;
  border: none;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--c-text-3);
  cursor: pointer;
  font-size: var(--text-2xs);
  font-family: var(--font-mono);
  flex-shrink: 0;
  transition: all 0.15s;
}

.expand-toggle:hover {
  background: var(--c-surface-2);
  color: var(--c-text-2);
}

.chevron {
  transition: transform 0.2s ease;
}

.expand-toggle[data-state='open'] .chevron {
  transform: rotate(180deg);
}

.expand-count {
  opacity: 0.8;
}

/* Expanded detail */
.variant-row-detail {
  overflow: hidden;
}

.variant-row-detail[data-state='open'] {
  animation: row-open 200ms ease-out;
}

.variant-row-detail[data-state='closed'] {
  animation: row-close 200ms ease-in;
}

@keyframes row-open {
  from { height: 0; opacity: 0; }
  to { height: var(--reka-collapsible-content-height); opacity: 1; }
}

@keyframes row-close {
  from { height: var(--reka-collapsible-content-height); opacity: 1; }
  to { height: 0; opacity: 0; }
}

.detail-section {
  padding: 0 0 0.5rem 5.75rem;
}

/* Major groups */
.major-groups {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  padding: 0.5rem 0 0.5rem 5.75rem;
}

.major-group {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
}

.major-header {
  flex-shrink: 0;
}

.major-number {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 600;
  color: var(--c-text-2);
  padding: 0.2rem 0.4rem;
}

/* Minor version groups */
.minor-groups {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  align-items: flex-start;
}

.minor-group {
  display: flex;
  align-items: center;
  gap: 0.25rem;
}

.minor-toggle {
  padding: 0.1rem 0.25rem;
}

/* Minor children popover */
.minor-children {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}

.popover-title {
  display: block;
  font-family: var(--font-mono);
  font-size: 10px;
  font-weight: 500;
  color: var(--c-text-3);
  letter-spacing: 0.05em;
  margin-bottom: 0.4rem;
}

.yanked-reasons {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  margin-top: 0.4rem;
}

.yanked-reason {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  color: var(--c-warn);
}

/* Responsive — see plan_site_redesign.md WP-D responsive contract. Every
   row's breakdown (CollapsibleRoot below) starts closed — `default-open`
   is intentionally omitted, relying on reka-ui's own `false` default —
   uniformly, on every viewport (user finding: versions box collapsed by
   default, same on mobile as desktop). The row header (segmented
   alias-chain control) stays visible regardless of collapse state; only
   the major/minor breakdown is gated behind each row's own expand-toggle
   chevron. */
@media (max-width: 640px) {
  .variant-label {
    min-width: 3.5rem;
    font-size: var(--text-2xs);
  }

  .variant-row-header {
    gap: 0.5rem;
  }

  .major-groups,
  .detail-section {
    padding-left: 4.25rem;
  }
}
</style>

<style>
/* Popover — unscoped because it renders in a portal */
.minor-popover {
  max-width: 360px;
  padding: 0.6rem;
  background: var(--c-surface);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-lg);
  z-index: 100;
  animation: popover-in 150ms ease-out;
}

.minor-popover.closing {
  animation: popover-out 200ms ease-in forwards;
}

@keyframes popover-in {
  from { opacity: 0; transform: translateY(-4px); }
  to { opacity: 1; transform: translateY(0); }
}

@keyframes popover-out {
  from { opacity: 1; transform: translateY(0); }
  to { opacity: 0; transform: translateY(-4px); }
}
</style>
