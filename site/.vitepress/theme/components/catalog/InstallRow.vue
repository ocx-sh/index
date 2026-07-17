<script setup lang="ts">
import { useCopyState } from '../../composables/useCopyState'
import CopyIcon from '../shared/CopyIcon.vue'

const props = defineProps<{
  /** Bare `<ns>/<pkg>` — this component builds the full `ocx add
   * ocx.sh/<name>` command itself. Never pass `root.name` here (it already
   * carries the `ocx.sh/` prefix — see `usePackageRoot`'s CAS-gotcha
   * docblock for the same trap on CAS URLs). */
  name: string
}>()

const { copied, copyText } = useCopyState(1500)

const command = `ocx add ocx.sh/${props.name}`
</script>

<template>
  <button type="button" class="install-row" :class="{ copied }" @click="copyText(command)">
    <span class="install-prefix">$</span>
    <span class="install-cmd">{{ command }}</span>
    <CopyIcon :copied="copied" class="install-icon" check-class="install-icon-check" />
  </button>
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
