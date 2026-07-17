import { ref } from 'vue'

// Shape mirrors schema/observation-object.schema.json 1:1 (the `platform`
// object's dotted keys — `os.version`, `os.features` — are OCI image-spec
// property names verbatim, not a nested `os` object).

export interface PlatformSpec {
  architecture: string
  os: string
  'os.version'?: string
  'os.features'?: string[]
  variant?: string
  features?: string[]
}

export interface PlatformEntry {
  platform: PlatformSpec
  digest: string
}

export interface ObservationObject {
  platforms: PlatformEntry[]
}

// Module-level cache + in-flight dedup, shared across every component
// instance and every `useObservation()` call — this is the point (repeat
// hovers over an already-fetched digest hit the cache, not the network).
// ponytail: plain Map, no eviction — observation objects are small and a
// single detail page touches at most a few dozen distinct digests; add
// an LRU cap if a long-lived SPA session ever fetches hundreds.
const cache = new Map<string, ObservationObject>()
const inFlight = new Map<string, Promise<ObservationObject | null>>()

async function fetchObservation(ns: string, pkg: string, digest: string): Promise<ObservationObject | null> {
  const cached = cache.get(digest)
  if (cached) return cached

  const pending = inFlight.get(digest)
  if (pending) return pending

  const hex = digest.replace(/^sha256:/, '')
  const promise = (async (): Promise<ObservationObject | null> => {
    try {
      const resp = await fetch(`/p/${ns}/${pkg}/o/sha256/${hex}.json`)
      if (!resp.ok) return null
      const data: ObservationObject = await resp.json()
      cache.set(digest, data)
      return data
    } catch {
      return null
    } finally {
      inFlight.delete(digest)
    }
  })()
  inFlight.set(digest, promise)
  return promise
}

/**
 * Lazy fetch of an observation object CAS blob (`/p/<ns>/<pkg>/o/sha256/
 * <hex>.json`). `ns`/`pkg` are the bare route params (same CAS gotcha as
 * `usePackageRoot` — never `root.name`); `digest` is a tag's
 * `tags[tag].content` value (`sha256:<hex>`).
 *
 * Pure fetch + module-level cache only — no grouping/version logic here
 * (that's `utils/version.ts`'s `buildVersionTable`). Callers that trigger
 * `load()` from a hover interaction own their own debounce (~150-200ms);
 * this composable's cache makes repeated calls for the same digest free.
 */
export function useObservation() {
  const observation = ref<ObservationObject | null>(null)
  const loading = ref(false)

  // Sequence token scoped to this composable instance — guards against a
  // rapid double-`load()` (e.g. two hover targets in quick succession)
  // resolving out of order, which would otherwise let the first (now
  // stale) call's response overwrite the second's.
  let requestToken = 0

  async function load(ns: string, pkg: string, digest: string) {
    const token = ++requestToken
    loading.value = true
    const result = await fetchObservation(ns, pkg, digest)
    if (token !== requestToken) return
    observation.value = result
    loading.value = false
  }

  return { observation, loading, load }
}
