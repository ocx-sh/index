import { describe, expect, test } from 'bun:test'
import { filterPackages } from './filterPackages'
import type { CatalogPackage } from '../composables/useCatalog'

function pkg(overrides: Partial<CatalogPackage>): CatalogPackage {
  return {
    namespace: 'kitware',
    package: 'cmake',
    name: 'kitware/cmake',
    status: 'active',
    deprecatedMessage: null,
    supersededBy: null,
    title: 'CMake',
    description: 'Cross-platform build system',
    keywords: ['build', 'c++'],
    latestVersion: '3.31.7',
    tagCount: 12,
    platforms: ['linux/amd64', 'darwin/arm64'],
    logoUrl: null,
    readmeUrl: null,
    ...overrides,
  }
}

describe('filterPackages', () => {
  test('query matches case-insensitively across name/title/description/keywords', () => {
    const packages = [
      pkg({ name: 'kitware/cmake', title: 'CMake', description: 'Cross-platform build system' }),
      pkg({ name: 'ocx-contrib/shellcheck', package: 'shellcheck', title: 'ShellCheck', description: 'Shell script linter', keywords: ['lint'] }),
    ]

    expect(filterPackages(packages, { query: 'CMAKE' }).map(p => p.name)).toEqual(['kitware/cmake'])
    expect(filterPackages(packages, { query: 'cross-platform' }).map(p => p.name)).toEqual(['kitware/cmake'])
    expect(filterPackages(packages, { query: 'lint' }).map(p => p.name)).toEqual(['ocx-contrib/shellcheck'])
    expect(filterPackages(packages, { query: 'nonexistent' })).toEqual([])
  })

  test('platforms facet: OR within the facet (matches ANY selected platform)', () => {
    const packages = [
      pkg({ name: 'a', platforms: ['linux/amd64'] }),
      pkg({ name: 'b', platforms: ['darwin/arm64'] }),
      pkg({ name: 'c', platforms: ['windows/amd64'] }),
    ]
    const result = filterPackages(packages, { platforms: ['linux', 'darwin'] }).map(p => p.name)
    expect(result.sort()).toEqual(['a', 'b'])
  })

  test('keywords facet: OR within the facet (matches ANY selected keyword)', () => {
    const packages = [
      pkg({ name: 'a', keywords: ['build'] }),
      pkg({ name: 'b', keywords: ['lint'] }),
      pkg({ name: 'c', keywords: ['test'] }),
    ]
    const result = filterPackages(packages, { keywords: ['build', 'lint'] }).map(p => p.name)
    expect(result.sort()).toEqual(['a', 'b'])
  })

  test('facets combine with AND across categories', () => {
    const packages = [
      pkg({ name: 'a', platforms: ['linux/amd64'], keywords: ['build'] }),
      pkg({ name: 'b', platforms: ['linux/amd64'], keywords: ['lint'] }),
      pkg({ name: 'c', platforms: ['darwin/arm64'], keywords: ['build'] }),
    ]
    // linux AND build -> only "a" satisfies both.
    const result = filterPackages(packages, { platforms: ['linux'], keywords: ['build'] })
    expect(result.map(p => p.name)).toEqual(['a'])
  })

  test('deprecatedOnly restricts to status === "deprecated"', () => {
    const packages = [
      pkg({ name: 'a', status: 'active' }),
      pkg({ name: 'b', status: 'deprecated' }),
      pkg({ name: 'c', status: 'yanked' }),
    ]
    expect(filterPackages(packages, { deprecatedOnly: true }).map(p => p.name)).toEqual(['b'])
  })

  test('empty filter returns every package unchanged', () => {
    const packages = [pkg({ name: 'a' }), pkg({ name: 'b' })]
    expect(filterPackages(packages, {})).toEqual(packages)
  })
})
