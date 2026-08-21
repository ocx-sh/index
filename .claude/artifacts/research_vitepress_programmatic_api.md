# Research — Driving VitePress 2 (alpha) Programmatically from an npm Package

Date: 2026-08-21 · Axis: design patterns · For: `@ocx-sh/catalog` extraction (hex-plan run)
Worker: sonnet researcher; synthesis: session orchestrator.

## Node API surface (vitepress@2.0.0-alpha.19, main)

```ts
build(root?, { outDir, base, mpa, onAfterConfigResolve, … })   // src/node/build/build.ts
createServer(root?, serverOptions?, restartServer?, config?)   // src/node/server.ts
serve({ root?, base?, port? })                                 // src/node/serve/serve.ts
```

- **Undocumented, best-effort API** — no doc page exists; maintainer guidance is
  vuejs/vitepress#1509 ("most is exported, reference cli.ts, no guarantee").
  → Pin the exact alpha version; re-verify against `cli.ts` on every bump.
- Hard ESM (`type: module`, CJS dropped per #2703) — wrapper must be ESM.
- `srcDir = resolve(root, userConfig.srcDir || '.')`; `.vitepress/{theme,cache,
  dist,config.*}` located by hardcoded convention under `root`.

## Theme-from-package

- `userThemeDir` is **hardcoded** to `<root>/.vitepress/theme` — no config
  knob. Documented pattern: staged shim file `.vitepress/theme/index.ts` →
  `import Theme from '@ocx-sh/catalog/theme'; export default Theme`.
- Vue dual-instance risk pre-solved: VitePress aliases `/^vue$/` graph-wide
  (`src/node/alias.ts`) to one copy — safe as long as the theme imports `vue`
  normally (never bundle a private Vue).

## Invocation pattern (recommended)

`mkdtemp` scratch root per invocation → write synthesized pages + theme shim +
generated config → `build(scratchRoot, { outDir, cacheDir })` with **explicit**
outDir/cacheDir (stale `.vitepress/cache` bleed otherwise) → cleanup on
exit/SIGINT (nothing in VitePress cleans a caller-supplied root).

- Page synthesis must be real files on disk — chokidar watcher; no virtual-
  module hook in the public surface.
- No confirmed OSS project doing exactly this pattern (closest unverified:
  vitepress-theme-openapi — check its source before leaning on precedent).

## Vite-in-Vite pitfall (grim's Astro lesson, VitePress edition)

- Never `createServer()` in-process under vitest/another Vite process:
  NODE_ENV/mode fights (vite.dev JS-API warning), config bleed
  (vitest-dev/vitest#1363), hanging teardown (vitejs/vite#22934, #18224).
- Tests use `build()` (clean lifecycle); dev server runs in a child process.

## Determinism (golden-diff impact)

- Content-hashed filenames deterministic in the common case, but
  vitejs/vite#13071 documents unexplained byte-level drift across identical
  builds (closed unfixed; suspected esbuild worker ordering).
- → Golden diff normalizes hashed asset filenames (`assets/*.{hash}.js` →
  `assets/*.js`) and compares content, never raw bytes of Vite chunks.
- Unverified: whether VitePress 2 alpha embeds timestamps in HTML, and whether
  #13071 reproduces under Rolldown-Vite — empirical `grep`/double-build check
  is a plan work item.
