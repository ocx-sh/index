import { afterEach, describe, expect, mock, test } from 'bun:test'
import { useObservation } from './useObservation'

// `useObservation` is a plain composable (no `onMounted`/lifecycle hooks),
// so it's callable directly outside a component here — `ref()` alone
// doesn't need one.

const originalFetch = globalThis.fetch

afterEach(() => {
  globalThis.fetch = originalFetch
})

function mockJsonResponse(digest: string) {
  return { ok: true, json: async () => ({ platforms: [{ platform: { architecture: 'amd64', os: 'linux' }, digest }] }) }
}

describe('useObservation', () => {
  test('discards a stale response that resolves after a newer load() call (out-of-order resolution)', async () => {
    const digestA = `sha256:${'a'.repeat(64)}`
    const digestB = `sha256:${'b'.repeat(64)}`
    const urlA = `/p/ns/pkg/o/sha256/${'a'.repeat(64)}.json`
    const urlB = `/p/ns/pkg/o/sha256/${'b'.repeat(64)}.json`

    const resolvers = new Map<string, () => void>()
    globalThis.fetch = mock((url: string) => new Promise((resolve) => {
      resolvers.set(url, () => resolve(mockJsonResponse(url === urlA ? digestA : digestB)))
    })) as unknown as typeof fetch

    const { observation, load } = useObservation()

    const p1 = load('ns', 'pkg', digestA)
    const p2 = load('ns', 'pkg', digestB)

    // Resolve the SECOND (newer) call first, then the first (now stale) —
    // simulates a slow response landing after a faster, later one.
    resolvers.get(urlB)!()
    await p2
    resolvers.get(urlA)!()
    await p1

    expect(observation.value?.platforms[0]?.digest).toBe(digestB)
  })

  test('in-flight dedup: two concurrent loads for the same digest share one fetch', async () => {
    const digest = `sha256:${'c'.repeat(64)}`
    let fetchCalls = 0
    let resolveFetch: (v: unknown) => void = () => {}
    globalThis.fetch = mock(() => {
      fetchCalls++
      return new Promise((resolve) => { resolveFetch = resolve })
    }) as unknown as typeof fetch

    const a = useObservation()
    const b = useObservation()

    const p1 = a.load('ns', 'pkg2', digest)
    const p2 = b.load('ns', 'pkg2', digest)

    resolveFetch(mockJsonResponse(digest))
    await Promise.all([p1, p2])

    expect(fetchCalls).toBe(1)
    expect(a.observation.value?.platforms[0]?.digest).toBe(digest)
    expect(b.observation.value?.platforms[0]?.digest).toBe(digest)
  })
})
