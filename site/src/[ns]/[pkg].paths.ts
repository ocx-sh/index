import { basename, resolve } from 'node:path'
import { existsSync, readdirSync } from 'node:fs'
import { defineRoutes } from 'vitepress'

// cwd invariant: this loader runs inside VitePress's Node build/dev
// process, which is always invoked with `site/` as the working directory
// (`package.json`'s `dev`/`build` scripts run `vitepress dev`/`vitepress
// build` directly; `taskfile.yml`'s `site:build` task is `cd site && bun
// install && bun run build`). `resolve(process.cwd(), '..', ...)` therefore
// resolves against the repo root. If that invariant ever changes (e.g.
// VitePress invoked from the repo root instead), this silently discovers
// zero packages rather than failing the build — consistent with the
// empty-`p/`/missing-`/data/catalog` degrade-never-fail contract, but every
// detail page would then 404.
//
// `OCX_RENDER_INDEX_DIR` mirrors indexbot render's own `--index-dir` (a
// prefix BEFORE the literal `p/` component, empty == the real repo-root
// `p/` — `cli/render.py`'s `_p_prefix`) — one shared knob for both halves
// of the render pipeline, set by `taskfile.yml`'s `site:build` task from
// its `RENDER_INDEX_DIR` var (default ""). `task demo:serve` is the one
// caller that sets it (to "demo", reading `demo/p/**`); a plain `task
// site:build` / `task render:build` / `task verify` / CI / `bun run dev`
// leaves it unset and is byte-identical to before this override existed —
// an explicit env var, not directory presence, gates it, so a stray
// gitignored `demo/` left over from an earlier `task demo:seed` can never
// leak into those non-demo builds.
const indexDir = (process.env.OCX_RENDER_INDEX_DIR ?? '').replace(/\/+$/, '')
const P_DIR = indexDir
  ? resolve(process.cwd(), '..', indexDir, 'p')
  : resolve(process.cwd(), '..', 'p')

interface PackageParams {
  ns: string
  pkg: string
}

/** `{ns, pkg}` for every `p/<ns>/<pkg>.json` package root — mirrors the
 * bot's own `_package_roots` discovery (`cli/render.py`): a package id is
 * exactly a `.json` file one level under a namespace directory, which
 * excludes every CAS subtree entry (`p/<ns>/<pkg>/o/sha256/**`, always a
 * directory at this depth, never a file). */
function discoverPackages(): PackageParams[] {
  if (!existsSync(P_DIR)) return []

  const params: PackageParams[] = []
  for (const nsEntry of readdirSync(P_DIR, { withFileTypes: true })) {
    if (!nsEntry.isDirectory()) continue
    const nsDir = resolve(P_DIR, nsEntry.name)
    for (const pkgEntry of readdirSync(nsDir, { withFileTypes: true })) {
      if (pkgEntry.isFile() && pkgEntry.name.endsWith('.json')) {
        params.push({ ns: nsEntry.name, pkg: basename(pkgEntry.name, '.json') })
      }
    }
  }
  return params
}

export default defineRoutes({
  // Relative to this file's own directory (`site/src/[ns]/`) — VitePress
  // resolves `watch` against `path.dirname(pathsFile)`, so three levels up
  // reaches the repo root, then into `p/*/*.json` (every package root,
  // never a CAS object — those are 4+ segments deep). Mirrors the same
  // `OCX_RENDER_INDEX_DIR` selection as `P_DIR` so `bun run dev` HMR watches
  // whichever tree is actually active.
  watch: indexDir ? `../../../${indexDir}/p/*/*.json` : '../../../p/*/*.json',
  paths: () => discoverPackages().map(params => ({ params })),
})
