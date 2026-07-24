# E2E Topology (announce revamp)

The fork-PR announce lane (ADR-6) is validated end-to-end against the real
index — no disposable stand-in repo. The prior stand-in pair was removed by
the owner on 2026-07-19; see `handover_announce_alignment.md` (linked below,
"Target E2E topology") for that decision record.

```
michael-herwig/ocx-e2e-publisher       (small REAL Rust app; CI builds it,
  │                                     packages with a dev-channel ocx build)
  │  ocx package push ghcr.io/michael-herwig/... --announce-file tags.txt
  │  ocx package announce --tags-file tags.txt --fork michael-herwig/index
  ▼
michael-herwig/index                   (true GitHub fork of ocx-sh/index --
                                        parent verified, default branch main)
  │  fork PR, publisher's own identity, zero index-side credential
  ▼
ocx-sh/index                           (THE REAL INDEX: validate.yml
                                        verify-claims + governance gate)
```

| Repo | Role |
|---|---|
| `michael-herwig/ocx-e2e-publisher` | Rust app + CI: builds, pushes a real package, announces via a fork PR |
| `michael-herwig/index` | true GitHub fork of `ocx-sh/index` -- the publisher's PR target, not a copy |
| `ocx-sh/index` | this repo -- the real index the PR lands against |

## Governance lanes exercised

- **First claim -- human lane (G-04).** The E2E package is a brand-new root
  under the `michael-herwig` namespace, so its first announce PR is human
  lane by design (new package always is). Since the maintainer *is* the
  package owner, this is a self-review formality -- but it must go through
  the real lane, not be special-cased away.
- **Subsequent refreshes -- machine lane (G-19).** Once the root exists,
  later tag-content-refresh PRs from the same owner-authenticated publisher
  qualify for the machine lane and auto-merge, gated on `github_id`
  membership in the root's `owners[]`.

See [`adr_fork_pr_announce.md`](../../.claude/artifacts/adr_fork_pr_announce.md)
(FP-5, G-19/G-20) for the full lane-classification rules, and
[`handover_announce_alignment.md`](../../.claude/artifacts/handover_announce_alignment.md)
for the topology decision record and exit criteria.

## `scripts/e2e/publisher-harness/`

Retired. It hand-crafted a dummy dual-libc OCI package via `oras` for the
removed stand-in topology and never used the real `ocx` client -- nothing in
it serves the repurposed `ocx-e2e-publisher`, which is a real Rust app built
and published through the actual `ocx package push` / `ocx package announce`
CLI in its own repo. That repo owns its own CI; this repo has no
publisher-side scripts to maintain.
