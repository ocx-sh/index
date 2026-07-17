<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { casUrl } from '../../utils/cas'

// The pane is always rendered by DetailPage (no more `v-if="root.desc?.readme"`
// gate) — `digest` is `null` when the package has no readme at all, in which
// case `load()` skips the fetch and goes straight to the empty-state
// placeholder below. A real digest that 404s/fails lands on the same
// placeholder (muted message, no crash).
const props = defineProps<{
  /** Bare `<ns>/<pkg>` route params — CAS URLs, NEVER `root.name` (see
   * `usePackageRoot`'s CAS-gotcha docblock). */
  bareName: string
  digest: string | null
}>()

const html = ref<string | null>(null)
const loading = ref(true)
const failed = ref(false)

const digestShort = () => (props.digest ?? '').replace(/^sha256:/, '').slice(0, 12)

async function load() {
  loading.value = true
  failed.value = false
  html.value = null
  if (!props.digest) {
    failed.value = true
    loading.value = false
    return
  }
  const url = casUrl(props.bareName, props.digest, 'md')
  if (!url) {
    failed.value = true
    loading.value = false
    return
  }
  try {
    // Dynamic import — `markdown-it` only reaches the browser as its own
    // chunk, fetched the first time a README actually renders, instead of
    // a static import pulling it into the shared every-page bundle.
    const [resp, { default: MarkdownIt }] = await Promise.all([fetch(url), import('markdown-it')])
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const text = await resp.text()
    // `html: false` is non-negotiable — README content is semi-trusted
    // (bot-mirrored from a third-party registry's __ocx.desc, not authored
    // here).
    const md = new MarkdownIt({ html: false })
    html.value = md.render(text)
  } catch {
    failed.value = true
  } finally {
    loading.value = false
  }
}

onMounted(load)
watch(() => [props.bareName, props.digest], load)
</script>

<template>
  <div class="readme-pane">
    <span class="readme-heading">README</span>
    <div class="readme-card">
      <p v-if="loading" class="readme-status">Loading README…</p>
      <div v-else-if="failed" class="readme-empty">No README available.</div>
      <!-- eslint-disable-next-line vue/no-v-html -- markdown-it html:false: source is escaped/non-HTML, safe to inject -->
      <div v-else class="readme-content" v-html="html" />
      <span v-if="digest && !loading" class="readme-provenance">fetched from CAS · README from <code>__ocx.desc</code> at {{ digestShort() }}</span>
    </div>
  </div>
</template>

<style scoped>
.readme-pane {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.readme-heading {
  font-family: var(--font-mono);
  font-size: var(--text-xs);
  font-weight: 600;
  color: var(--c-text-3);
  letter-spacing: 0.06em;
}

.readme-card {
  background: var(--c-surface);
  border: 1px solid var(--c-line);
  border-radius: var(--radius-lg);
  padding: 20px 24px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.readme-status {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  color: var(--c-text-3);
  margin: 0;
}

.readme-empty {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  color: var(--c-text-3);
  opacity: 0.6;
  text-align: center;
  padding: 32px 0;
}

.readme-provenance {
  font-family: var(--font-mono);
  font-size: var(--text-2xs);
  color: var(--c-text-3);
  align-self: flex-end;
}

/* First rendered block sits flush against the card's top padding — the UA
   default top margin on the first heading/paragraph otherwise stacks on top
   of `.readme-card`'s own padding, pushing content down too far. */
.readme-content > :deep(*:first-child) {
  margin-top: 0;
}

.readme-content :deep(h1),
.readme-content :deep(h2),
.readme-content :deep(h3) {
  font-family: var(--font-sans);
  color: var(--c-text-1);
}

.readme-content :deep(p) {
  font-family: var(--font-sans);
  font-size: var(--text-base);
  line-height: 1.65;
  color: var(--c-text-2);
}

.readme-content :deep(code) {
  font-family: var(--font-mono);
  font-size: var(--text-sm);
  background: var(--c-surface-2);
  padding: 1px 5px;
  border-radius: var(--radius-sm);
}

/* Flat-colored fences — no client-side Shiki (design mock 1c/1f: "code
   blocks always dark, both themes"). */
.readme-content :deep(pre) {
  background: var(--c-code-bg);
  border-radius: var(--radius-lg);
  padding: 12px 16px;
  overflow-x: auto;
}

.readme-content :deep(pre code) {
  background: none;
  padding: 0;
  font-size: var(--text-sm);
  line-height: 1.7;
  color: #c8d0da;
}

.readme-content :deep(a) {
  color: var(--c-accent);
}

.readme-content :deep(table) {
  border-collapse: collapse;
  width: 100%;
}

.readme-content :deep(th),
.readme-content :deep(td) {
  border: 1px solid var(--c-line);
  padding: 6px 10px;
  font-size: var(--text-sm);
}
</style>
