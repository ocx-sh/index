import { describe, expect, test } from 'bun:test'
import { buildVersionTable, minorGroupHasYanked, rowHasHiddenYanked } from './version'

// Micro-suite for buildVersionTable's redesigned ownership: alias chains,
// yank threading, deprecated behavior. Parser fns (parseVersion/parseTag/
// compareVersions/versionDepth) are untouched by the redesign and already
// exercised indirectly here — no separate suite added for them.

describe('buildVersionTable', () => {
  test('alias chain: latest + major + minor + patch sharing one digest', () => {
    const table = buildVersionTable(
      {
        latest: { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
        3: { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
        '3.31': { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
        '3.31.7': { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
        '3.31.6': { content: 'sha256:bbb', observed: '2025-12-01T00:00:00Z' },
      },
      'active',
    )

    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('latest')
    expect(row.showLatestHighlight).toBe(true)
    expect(row.aliasChain.map(m => m.tag)).toEqual(['latest', '3', '3.31', '3.31.7'])
    expect(row.aliasChain.every(m => m.digest === 'sha256:aaa')).toBe(true)
    expect(row.preciseAliasTag).toBe('3.31.7')

    // 3.31.6 is a different digest — grouped, not part of the chain.
    const major = row.majorGroups.find(mg => mg.major === 3)!
    const minor = major.minorGroups.find(m => m.minorTag === '3.31')!
    expect(minor.patches.map(p => p.tag)).toEqual(['3.31.7', '3.31.6'])
  })

  test('preciseAliasTag: same-depth multi-alias picks the newest, not the last-sorted', () => {
    // latest + 2.0.0 + 1.0.0 all share one digest — both versions are depth
    // 3 (equal precision). The "latest x.y.z" pin must read 2.0.0 (newest),
    // not 1.0.0 (what a naive `.at(-1)` over the depth-then-newest-first
    // sorted alias chain would wrongly pick).
    const table = buildVersionTable(
      {
        latest: { content: 'sha256:eee', observed: '2026-01-01T00:00:00Z' },
        '2.0.0': { content: 'sha256:eee', observed: '2026-01-01T00:00:00Z' },
        '1.0.0': { content: 'sha256:eee', observed: '2025-01-01T00:00:00Z' },
      },
      'active',
    )

    const row = table.rows.find(r => r.isDefault)!
    expect(row.aliasChain.map(m => m.tag)).toEqual(['latest', '2.0.0', '1.0.0'])
    expect(row.preciseAliasTag).toBe('2.0.0')
  })

  test('yanked rolling tag: yanked "latest" surfaces in yankedRolling, absent from the chain', () => {
    const table = buildVersionTable(
      {
        latest: {
          content: 'sha256:fff',
          observed: '2026-01-01T00:00:00Z',
          yanked: { reason: 'bad rolling pointer', at: '2026-01-02T00:00:00Z' },
        },
        '1.2.3': { content: 'sha256:aba', observed: '2026-01-01T00:00:00Z' },
      },
      'active',
    )

    const row = table.rows.find(r => r.isDefault)!
    expect(row.yankedRolling).toEqual([{ tag: 'latest', digest: 'sha256:fff', yanked: { reason: 'bad rolling pointer', at: '2026-01-02T00:00:00Z' } }])
    expect(row.aliasChain.map(m => m.tag)).not.toContain('latest')
    expect(row.primaryTag).toBe('1.2.3')
  })

  test('yank threading: yanked patch is struck and carries its reason inline', () => {
    const table = buildVersionTable(
      {
        '3.30.2': {
          content: 'sha256:ccc',
          observed: '2026-05-14T00:00:00Z',
          yanked: { reason: 'upstream artifact checksum mismatch', at: '2026-05-14T00:00:00Z' },
        },
        '3.30.1': { content: 'sha256:ddd', observed: '2026-05-01T00:00:00Z' },
      },
      'active',
    )

    const row = table.rows.find(r => r.isDefault)!
    const minor = row.majorGroups[0].minorGroups[0]
    const yankedPatch = minor.patches.find(p => p.tag === '3.30.2')!
    expect(yankedPatch.yanked?.reason).toBe('upstream artifact checksum mismatch')

    // Yanked tags never win primary/alias-chain selection.
    expect(row.primaryTag).toBe('3.30.1')
    expect(row.aliasChain.map(m => m.tag)).not.toContain('3.30.2')
  })

  test('deprecated: no live latest, even if a stray "latest" tag is present', () => {
    const table = buildVersionTable(
      {
        latest: { content: 'sha256:eee', observed: '2026-01-01T00:00:00Z' },
        '0.10.0': { content: 'sha256:fff', observed: '2026-01-01T00:00:00Z' },
      },
      'deprecated',
    )

    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('0.10.0')
    expect(row.showLatestHighlight).toBe(false)
    expect(row.aliasChain.map(m => m.tag)).not.toContain('latest')
  })

  test('all-yanked row: no primary, no alias chain, groups still render', () => {
    const table = buildVersionTable(
      {
        '1.0.0': {
          content: 'sha256:111',
          observed: '2026-01-01T00:00:00Z',
          yanked: { reason: 'broken build', at: '2026-01-02T00:00:00Z' },
        },
      },
      'active',
    )

    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBeNull()
    expect(row.aliasChain).toEqual([])
    expect(row.majorGroups[0].minorGroups[0].patches[0].tag).toBe('1.0.0')
  })

  test('unknown tags carry digest + yanked through too', () => {
    const table = buildVersionTable(
      { nightly_build: { content: 'sha256:999', observed: '2026-01-01T00:00:00Z' } },
      'active',
    )
    expect(table.unknownTags).toEqual([{ tag: 'nightly_build', digest: 'sha256:999', yanked: undefined }])
  })

  test('primaryTag depth-fallback: depth-4 tag only (prerelease/build) wins with no shallower tags', () => {
    const table = buildVersionTable(
      { '1.2.3-rc1': { content: 'sha256:d4', observed: '2026-01-01T00:00:00Z' } },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('1.2.3-rc1')
  })

  test('primaryTag depth-fallback: depth-2 tag only (major.minor) wins with no shallower tags', () => {
    const table = buildVersionTable(
      { '1.2': { content: 'sha256:d2', observed: '2026-01-01T00:00:00Z' } },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('1.2')
  })

  test('primaryTag depth-fallback: depth-1 tag only (bare major) wins with no shallower tags', () => {
    const table = buildVersionTable(
      { 1: { content: 'sha256:d1', observed: '2026-01-01T00:00:00Z' } },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('1')
  })

  test('latest-only package: no versioned tags at all, majorGroups stays empty', () => {
    const table = buildVersionTable(
      { latest: { content: 'sha256:only', observed: '2026-01-01T00:00:00Z' } },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(row.primaryTag).toBe('latest')
    expect(row.majorGroups).toEqual([])
    expect(row.preciseAliasTag).toBeNull()
  })
})

describe('rowHasHiddenYanked / minorGroupHasYanked', () => {
  // Regression coverage for the "yanked tags render with zero distinction"
  // bug: `buildVersionTable` threads `yanked` correctly (see the yank-
  // threading tests above), but VersionTree.vue's collapsed default state
  // (every row/minor-group starts closed) gave zero passive signal that a
  // yanked release existed underneath — a user had to blindly expand a row
  // *and* open the exact right minor popover to ever see it. These two
  // functions are what VersionTree.vue now checks to color the collapsed
  // expand-toggle/minor-toggle before that drill-down happens.

  test('astral-sh/uv shape: a yanked patch nested under a synthesized minor group is flagged', () => {
    const table = buildVersionTable(
      {
        '1.0.0': { content: 'sha256:xxx', observed: '2026-07-17T00:00:00Z' },
        '0.9.0': {
          content: 'sha256:yyy',
          observed: '2026-07-01T00:00:00Z',
          yanked: { reason: 'broken build', at: '2026-07-20T00:00:00Z' },
        },
      },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(rowHasHiddenYanked(row)).toBe(true)

    const yankedMinor = row.majorGroups.find(mg => mg.major === 0)!.minorGroups[0]
    const liveMinor = row.majorGroups.find(mg => mg.major === 1)!.minorGroups[0]
    expect(minorGroupHasYanked(yankedMinor)).toBe(true)
    expect(minorGroupHasYanked(liveMinor)).toBe(false)
  })

  test('all-live package: no hidden yank anywhere', () => {
    const table = buildVersionTable(
      {
        latest: { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
        '1.2.3': { content: 'sha256:aaa', observed: '2026-01-01T00:00:00Z' },
      },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(rowHasHiddenYanked(row)).toBe(false)
  })

  test('yanked rolling tag alone does not count as "hidden" — it already renders unconditionally', () => {
    const table = buildVersionTable(
      {
        latest: {
          content: 'sha256:fff',
          observed: '2026-01-01T00:00:00Z',
          yanked: { reason: 'bad rolling pointer', at: '2026-01-02T00:00:00Z' },
        },
        '1.2.3': { content: 'sha256:aba', observed: '2026-01-01T00:00:00Z' },
      },
      'active',
    )
    const row = table.rows.find(r => r.isDefault)!
    expect(row.yankedRolling.length).toBe(1)
    expect(rowHasHiddenYanked(row)).toBe(false)
  })
})
