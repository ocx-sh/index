# Handover: Announce Alignment — Index-Side Work for the Rust Client + Live E2E

- **Date:** 2026-07-19
- **From:** ocx-side design session (ocx-sion worktree, Fable orchestrator)
- **For:** a dedicated instance working in `ocx-sh/index`
- **Status of this doc:** work order — owner-reviewed structure, individual items carry their own pending/ratified marker. **Refreshed 2026-07-24** (Track P0) against `design_spec_announce_initiative.md`: S3/S4/S12/§5-coverage folded into ratified decisions, the fixtures work item marked delivered, multi-root PRs moved to resolved.

## Mission

Bring the index repo into full alignment with the fork-PR announce lane (ADR-6) so the
Rust client (`ocx package announce`, ocx-sh/ocx#216) can be implemented against it and
integration-tested **against the real index** — no sandbox indirection. The index side owns:
bot fixes, contract fixtures, stale-surface cleanup, and the governance path for the first
real E2E package claim.

## Authority & inputs (read before starting)

| Artifact | Where | Role |
|---|---|---|
| `adr_fork_pr_announce.md` (ADR-6) | this repo, `.claude/artifacts/` | design authority for the announce lane (FP-1..FP-9, G-19/G-20) |
| `bot/CONTRACTS.md` §12, §14 | this repo | executable spec; §14 = client-facing byte-exact serializer contract |
| PR #49 (open) | this repo | phase 3: workflow YAML alignment — prerequisite for most items below |
| `adr_announce_publisher_surface.md` (Proposed) | ocx repo (`ocx-sion` worktree), `.claude/artifacts/` | client-side surface: forge-neutral CLI, token model, CI units |
| `research_publish_to_bcr_anatomy.md` / `_transfer.md` | ocx repo, `.claude/artifacts/` | BCR problem→solution catalog + adopt/adapt/avoid map (observability + dedupe requirements come from here) |
| ocx-sh/ocx#216 | GitHub | Rust client tracking issue |

## Target E2E topology (owner decision 2026-07-19 — replaces the sandbox)

```
michael-herwig/ocx-e2e-publisher       (repurposed: small REAL Rust app; CI builds it,
  │                                     packages with a dev-channel ocx build)
  │  ocx package push ghcr.io/michael-herwig/... --announce-file tags.txt
  │  ocx package announce --tags-file tags.txt --fork michael-herwig/index
  ▼
michael-herwig/index                   (true GitHub fork of ocx-sh/index — created 2026-07-19,
                                        parent verified, default branch main)
  │  fork PR, publisher's own identity, zero index-side credential
  ▼
ocx-sh/index                           (THE REAL INDEX: validate.yml verify-claims +
                                        governance gate; first claim = human lane G-04,
                                        subsequent refreshes = machine lane G-19)
```

- The old sandbox pair — `michael-herwig/ocx-index-e2e` + `ocx-contrib/ocx-index-e2e` fork —
  was "the wrong way around" (a disposable stand-in index instead of the real one). **Both
  repos already deleted (owner, 2026-07-19).** Only `michael-herwig/ocx-e2e-publisher`
  survives, repurposed as above. Consequence: `scripts/e2e/setup-sandbox.sh` and the
  sandbox topology in `scripts/e2e/README.md` now reference dead repos — cleanup is due,
  not deferred; ADR-6's "E2E validation strategy" section describes the deleted topology
  and needs a superseded-by note pointing here.
- ocx ships the client from a feature branch via **floating dev releases** (`<version>-dev`
  tag, never build-timestamp pins); the publisher repo consumes that dev build.
- The E2E package becomes a **real entry** in the real index under the `michael-herwig`
  namespace — first-claim human lane is part of the test, not test pollution.

## Ratified decisions this handover encodes

1. **Unchanged ⇒ no-op** (owner, 2026-07-18): announce that produces byte-identical root and
   no new CAS files must skip commit + PR entirely, exit 0. The serializer determinism +
   `regenerate()` timestamp-preservation make this a single byte comparison.
2. **E2E restructure** as diagrammed above.
3. **v1 "what's new" = explicit curated tags** (registry-scan later); `ocx package push
   --announce-file` appends pushed + cascade tags; announce consumes the file.
4. Announce-file lifecycle: per-pipeline-run scratch file, never persistent.
5. **Always fork — no direct push, ever** (register S3, owner 2026-07-22): every announce
   goes through a reviewed fork PR, first-party included. One path for everyone; kills the
   grimoire tri-state permission probe. No direct push to `ocx-sh/index` from anyone.
6. **PAT-only day one** (register S4): a dedicated `ocx-bot` machine account (classic PAT,
   `public_repo`) drives the ocx-contrib fleet; third parties bring their own classic PAT.
   Fine-grained PATs cannot fork/PR public repos (github/roadmap#600). A GitHub App is a
   future scaling option only — and never with any permission on a publisher's source repo
   (xz / BCR #157 lesson).
7. **One shared `ocx-contrib/index` fork for the whole mirror fleet** (register S12):
   branch-per-package avoids collisions; a fork-per-mirror was rejected. Third parties use
   their own fork.
8. **100% bot branch coverage stays** (register §5): `fail_under = 100` is already green — do
   not lower (owner corrected an earlier 90% suggestion). New bot work raises the bar, never
   relaxes it.

## Index work items (ordered)

1. **Land PR #49** (phase 3 workflows). Everything below assumes it.
2. **Bot: unchanged-root short-circuit** in `cli/announce.py` — currently `run()` always
   commits and opens a PR even when `serialize_package_root(target) == current_raw` and no
   new CAS/desc files exist (verified: `announce.py:218-267` has no comparison). Fix: detect,
   print "unchanged, nothing to announce", exit 0 before any fork write. Regression test.
   This keeps the Python reference tool the executable spec (FP-9) for a behavior the Rust
   client will ship (ocx-side ADR).
3. **Serializer conformance fixtures for the Rust port** — ✅ **DELIVERED** (Track P0 WP-P1,
   2026-07-24). `bot/tests/golden/serializer/` holds the golden byte vectors: `root/minimal.json`
   and `root/full-fields.json` (yank + superseded_by + upstream + desc + a non-ASCII title) plus
   two `observation/sha256/*.json` vectors (multi-platform `os.features`, and an ensure_ascii
   non-ASCII probe). `bot/tests/core/test_serializer_golden.py` round-trips each against the real
   `serialize_package_root`/`serialize_observation_object` and asserts the fixture inventory,
   riding `task bot:test` at 100% branch coverage (drift fails here first). Vendored into ocx at
   `crates/ocx_lib/tests/fixtures/index_wire/` (Track P0 WP-P4). Original scope, for the record:
   golden byte vectors for CONTRACTS §14 — canonical root serialization (field order, 2-space
   indent, trailing newline) and CAS canonical form (minified, alphabetized, ascii, no trailing
   newline).
4. **Stale-surface cleanup** (post-#49): delete `.github/workflows/announce.yml` (retired
   doorbell; already broken — calls nonexistent `--validate-only`), delete
   `site/src/docs/ops/rotate-announce-pat.md`, rewrite `site/src/docs/how-to/
   announce-a-package.md` for the fork-PR flow (bot-based instructions now, Rust CLI
   instructions once ocx#216 ships), fix the stale cross-link in `claim-a-namespace.md`,
   add G-19/G-20 to `site/src/docs/reference/governance-contracts.md`.
5. **E2E enablement**: review/claim path for the `michael-herwig` namespace first entry in
   `p/` (human lane G-04 — the maintainer is the owner, so this is a self-review formality
   but must go through the real lane). Remove `scripts/e2e/setup-sandbox.sh` + rewrite
   `scripts/e2e/README.md` for the real-index topology (sandbox repos already deleted, see
   above); keep/adapt `scripts/e2e/publisher-harness/` only where it still serves the
   repurposed `ocx-e2e-publisher`. Add superseded-by note to ADR-6's E2E section.
6. **Optional hardening**: governance/validate treatment of empty-diff PRs (label +
   auto-close) as defense against non-conforming clients — low priority once item 2 ships.
7. **Observability floor** (from BCR transfer research): every bot/CI failure path a
   publisher can hit must surface a structured reason (step summary or PR comment), never a
   bare exit — BCR's most-repeated community complaint. Audit `validate.yml` job outputs
   against this bar.

## Interface contract with the ocx side (do not build here)

- Rust `ocx package announce` (feature branch in ocx repo): forge-neutral surface, GitHub
  impl, additive `--tags-file` union vs `--tags` replace, `--yank/--unyank`, unchanged
  short-circuit, fork PR open/update with dedupe. Consumes item 3 fixtures.
- `ocx package push --announce-file` append.
- Reusable CI units (GitHub action/workflow, GitLab component) come after the CLI works —
  placement decision (setup-ocx vs dedicated repos) still open owner-side.

## Owner decisions ratified 2026-07-19 (ocx-side ADR now Accepted)

- Additive `--tags-file` union (client-side; deletion via explicit `--tags` replace only).
- Fork auto-create by the client when missing.
- Land ocx PR #217 (`feat/index-indirection`) before the announce branch.
- GitLab-hosted index = real future track → forge-neutral user surface enforced.
- `michael-herwig/index` fork created (parent verified).

## Pending owner decisions (track, don't implement)

- CI-unit repo placement (D4 of the ocx-side ADR) — needed only at CI-unit phase.
- desc-blob authoring surface (index-side gap — no template, write path unspecified).

**Resolved since this handover was written:** Multi-root announce PRs are **allowed** — no
client refusal (register C12). G-19 evaluates ownership per-root from the base ref, so a
mixed owned/unowned PR falls to the human lane without escalation; the client naturally emits
one PR per package.

## Exit criteria

End-to-end green run: publisher repo tags a release → CI builds Rust app → dev-ocx pushes
package + appends announce-file → dev-ocx announce opens fork PR on the real index →
`validate.yml` verify-claims green → correct lane classification → merge → rendered
`index.ocx.sh` serves the root → `ocx install` resolves the package from a clean machine.
Second identical run: announce reports "unchanged", zero PRs created.
