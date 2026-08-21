# Research — Supply-Chain-Safe npm Release for `@ocx-sh/catalog`

Date: 2026-08-21 · Axis: domain/supply-chain · For: catalog extraction (hex-plan run)
Worker: sonnet researcher; synthesis: session orchestrator.
Context: development starts local-only (no GitHub repo); repo comes later.

## Bootstrap sequence

1. **Create the `@ocx-sh` npm org now** — the only real anti-squatting move
   (npm has no reservation mechanism).
2. First publish is **manual**: `@ocx-sh/catalog@0.1.0` from a laptop with a
   granular 2FA-bypass token; delete the token immediately after.
   (npm trusted publishing requires the package to already exist — cannot be
   pre-wired, unlike PyPI. Placeholder-publish tools exist
   (azu/setup-npm-trusted-publish) — skipped, no reason to burn a version.)
3. The moment the GitHub repo + workflow exist: register the trusted publisher
   (OIDC), publish via CI only from then on.

## Trusted publishing / provenance facts

- Providers: GitHub Actions, GitLab CI/CD, CircleCI — no self-hosted runners.
- Since 2026-05-20 new trusted-publisher configs must explicitly scope allowed
  workflows. Per-package config, no bulk setting.
- Needs npm CLI ≥11.5.1, job `permissions: id-token: write`; pass
  `--provenance` explicitly (no-op when automatic — practitioner-reported
  necessity, Phil Nash 2026-01).
- **Provenance requires a PUBLIC repo** — silently never attaches otherwise.
  Time-sensitive note for repo creation, not today.
- Adding OIDC/provenance later is additive; already-published versions
  unaffected.

## Pack verification (fully local, pre-repo)

CI/vitest gate, the 2026-standard triad + one smoke:

```
npm pack  →  npx publint  →  npx @arethetypeswrong/cli --pack
+ ~15-line smoke: install tarball into mkdtemp, run `ocx-catalog --version` + a fixture build
```

Catches the exports-map/types/bin-stripped class (grim 0.1.0 shipped without
its bin — npm "auto-corrected" the manifest with only a warning). grim's
release.yml additionally greps `npm publish --dry-run` output for
"auto-corrected" and fails — port that guard verbatim. midnight-smoker exists
but is heavier than one package needs.

## Renovate baseline

`config:recommended` + three packageRules: github-actions manager with
`pinDigests: true` (matches repo SHA-pin invariant); grouped minor/patch npm
PR; weekly `lockFileMaintenance`. Nothing npm-specific beyond that.

## Versioning

Manual `npm version` + tag-triggered publish. **Skip changesets** — single
package, pre-1.0; revisit only on a second `@ocx-sh/*` package or real
changelog pain.
