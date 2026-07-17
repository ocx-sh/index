<script setup lang="ts">
import { computed } from 'vue'
import { useCopyState } from '../../composables/useCopyState'
import CopyIcon from '../shared/CopyIcon.vue'
import CopyContextMenu, { type CopyAction } from '../shared/CopyContextMenu.vue'

const props = defineProps<{
  /** Bare `<ns>/<pkg>` — this component builds the full `ocx add
   * ocx.sh/<name>` command itself. Never pass `root.name` here (it already
   * carries the `ocx.sh/` prefix — see `usePackageRoot`'s CAS-gotcha
   * docblock for the same trap on CAS URLs). */
  name: string
  /** Catalog's `latestVersion`, if known — the right-click menu's
   * tag-scoped actions (Copy tag / Add to project / Add globally / Inspect
   * / Exec, mirroring `TagBadge.vue`'s per-tag menu) qualify against this
   * tag when present, falling back to the bare identifier otherwise — same
   * as the box's own left-click command below, which never pins a tag. */
  latestVersion?: string | null
}>()

const { copied, copyText } = useCopyState(1500)

const qualifiedName = computed(() => `ocx.sh/${props.name}`)
const command = computed(() => `ocx add ${qualifiedName.value}`)

// TagBadge's `qualifiedName:tag` identifier, adapted: a catalog card has no
// selected tag, so fall back to the bare qualified name when latestVersion
// is unknown.
const identifier = computed(() =>
  props.latestVersion ? `${qualifiedName.value}:${props.latestVersion}` : qualifiedName.value,
)

const actions = computed<CopyAction[]>(() => {
  const list: CopyAction[] = [
    { label: 'Copy identifier', command: identifier.value, icon: 'identifier' },
  ]
  if (props.latestVersion) {
    list.push({ label: 'Copy tag', command: props.latestVersion, icon: 'tag' })
  }
  list.push(
    { label: 'Add to project', command: `ocx add ${identifier.value}`, icon: 'project' },
    { label: 'Add globally', command: `ocx --global add ${identifier.value}`, icon: 'global' },
    { label: 'Inspect command', command: `ocx package inspect ${identifier.value}`, icon: 'inspect' },
    { label: 'Exec command', command: `ocx package exec ${identifier.value}`, icon: 'exec' },
  )
  return list
})

// The card wraps this component in `<a href>` (catalog grid navigates to
// the detail page on click) — the box is a copy-only shorthand precisely so
// a click here never opens the detail page. `stopPropagation` alone does
// NOT cancel an ancestor anchor's navigation: that's the click event's
// *default action*, gated on `preventDefault`, not on whether the event
// kept bubbling. Both belong here, on the element that owns the click,
// rather than bolted on as `@click.stop` at whichever call site happens to
// wrap this component in an anchor.
function onClick(event: MouseEvent) {
  event.preventDefault()
  event.stopPropagation()
  copyText(command.value)
}
</script>

<template>
  <CopyContextMenu :actions="actions" :copy-text="copyText">
    <button type="button" class="install-row" tabindex="-1" :class="{ copied }" @click="onClick">
      <span class="install-prefix">$</span>
      <span class="install-cmd">{{ command }}</span>
      <CopyIcon :copied="copied" class="install-icon" check-class="install-icon-check" />
    </button>
  </CopyContextMenu>
</template>

<style scoped>
.install-row {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  background: var(--c-surface-2);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-md);
  padding: 6px 9px;
  font-family: var(--font-mono);
  cursor: pointer;
  transition: border-color 0.15s;
  text-align: left;
}

.install-row:hover,
.install-row:focus-visible {
  border-color: var(--c-accent);
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

.install-icon {
  flex-shrink: 0;
  color: var(--c-text-3);
}

.install-row.copied {
  border-color: var(--c-ok);
}

.install-row.copied .install-cmd {
  color: var(--c-ok);
}

.install-icon-check {
  color: var(--c-ok);
}
</style>
