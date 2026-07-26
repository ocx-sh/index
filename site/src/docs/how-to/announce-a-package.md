---
title: Announce a Package
---

# Announce a Package

Announcing is how a publisher records newly pushed tags in this index: you
assemble a canonical package root and open (or update) a pull request against
`ocx-sh/index` from your own fork, authored under your own GitHub identity.
There is no publisher-held index credential — the PR *is* the announcement,
and CI re-derives every claim in it from the physical registry before anything
can merge (see [Governance Contracts][governance-contracts]).

For an owner refreshing a package they already own, the whole flow is
machine-to-machine: no human clicks anything between your release workflow
pushing a tag and the index PR merging.

## Prerequisite {#prerequisite}

Three things need to be true before your first announce:

- The namespace is already [claimed][claim-a-namespace] in this index.
  Announce refreshes an existing package root; it cannot create one. Against
  an unclaimed package it refuses outright — `unclaimed namespace: no
  committed root at p/<ns>/<pkg>.json on main` — because a new package is a
  human-lane act (see
  [PR and Auto-Merge Semantics][pr-and-auto-merge-semantics]).
- `OCX_ANNOUNCE_TOKEN` is set to a token capable of opening pull requests
  against a public repository. A classic PAT works out of the box — see
  [Classic PAT Setup][classic-pat-setup].
- A fork of `ocx-sh/index` exists under your account. If it doesn't yet, the
  `ocx` CLI creates one for you — see [Fork Auto-Create][fork-auto-create].

## The `ocx` CLI Path {#the-ocx-cli-path}

Announcing is a two-command handoff: `ocx package push` records what you just
published, `ocx package announce` turns that record into a pull request.

`ocx package push --announce-file <path>` appends the primary tag you pushed,
plus any cascade tags it moved, to a scratch file at `<path>` — a
comma/newline list of tag names, byte-compatible with the reference tool's
own `--tags-file` format. That file is a **per-package, per-pipeline-run
scratch artifact**, never a persistent one: a file left over from a previous
run could silently re-add a tag you deliberately deleted (C2).

`ocx package announce --package <ns>/<pkg> --tags-file <path> --fork <owner>/index [--index-repo ocx-sh/index]`
turns the scratch file into the actual PR. It reads the committed root —
from `main` on a first run, or from the head of your own still-open announce
branch if one already exists from an earlier run in the same cycle, so two
announces in a row accumulate into one PR instead of racing each other's
diff (C4) — and **unions** the tags file's contents into it. `--tags-file`
only adds, it never deletes; dropping a tag is the separate, explicit
`--tags <a,b,c>`, which replaces the curated set outright and drops every
committed tag it does not name (C3). The command then builds the canonical
root plus any new CAS objects — each
observed tag's OCI image index, stored verbatim under the digest the registry
served it as — and opens or updates exactly one pull request against
`ocx-sh/index`, on a branch named `indexbot-announce-<ns>-<pkg>` — the fork's
topic branch is created directly at the upstream base SHA, and if the fork
itself doesn't exist yet, it's created first (C8). That branch-naming
convention matches the Python [reference tool][reference-tool], so the two
implementations dedupe against each other's open PRs instead of opening
duplicates (C9).

Two more things round out the surface:

- `--refresh` re-observes every tag already in the committed root — useful
  for picking up a moved digest under a rolling tag (`latest`, a cascade
  target) without turning announce into a full registry scan. It is the third
  way to name the curated set, so it is mutually exclusive with both
  `--tags` and `--tags-file`; the set stays owner-curated either way (C5).
- Re-announcing an already-current state is a no-op: if the serialized root
  would come out byte-identical to what's already committed, and there are no
  new CAS objects to add, the command exits `0` reporting `status:
  "unchanged"` — nothing is committed, and no warning is printed (C6). It
  still reports the pull request when your announce branch is already ahead
  of the index's `main` from an earlier run in the same cycle.

Yanking and un-yanking are their own, deliberately separate actions:
`--yank <tag> --yank-reason <text>` and `--unyank <tag>` mark or clear the
grace marker on a tag row that's still present in the set. Yank is never set
automatically, and `--refresh` never touches it — it's an owner decision a
routine refresh can't accidentally trigger or clear (C7).

## Copy-Paste GitHub Actions Snippet {#copy-paste-github-actions-snippet}

This block is meant to slot into an existing [GitHub Actions][gh-actions]
release workflow, right after whatever step builds or downloads your
artifacts.

The scratch file behind `--announce-file` lives under `$RUNNER_TEMP`, never
`/tmp`. On a GitHub-hosted runner the two are similar, but on a self-hosted
runner `/tmp` is host-wide and outlives the job — shared across whatever
concurrent jobs happen to land on that machine, which breaks the file's
per-package, per-run scratch lifecycle the moment two runs overlap (C2).
`$RUNNER_TEMP` is scoped to the job by construction. The filename folds in
the package name, the run id, and the run attempt, so retries and concurrent
packages in the same workflow never collide over the same path. The prepare
step both truncates it (`: >`) and publishes the resolved path to
`$GITHUB_ENV`, so the later steps name one variable instead of rebuilding the
same path expression three times and drifting. Truncation matters because
GitHub reuses `$RUNNER_TEMP` across retries of the same run, and a stale
leftover file could resurrect a tag you meant to drop. The cleanup step runs
`if: always()`, so a failed push or announce still leaves the runner's temp
directory clean instead of accumulating scratch files across retries.

```yaml
# At job level, alongside `runs-on:`.
env:
  OCX_ANNOUNCE_TOKEN: ${{ secrets.OCX_ANNOUNCE_TOKEN }}
  REF_NAME: ${{ github.ref_name }}

steps:
  - uses: ocx-sh/setup-ocx@<sha> # v1.x.y

  - name: Prepare announce-tags scratch file
    run: |
      tags_file="$RUNNER_TEMP/announce-tags-<pkg>-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT.txt"
      : > "$tags_file"
      echo "TAGS_FILE=$tags_file" >> "$GITHUB_ENV"

  - name: Push and announce
    if: ${{ env.OCX_ANNOUNCE_TOKEN != '' }}
    run: |
      ocx package push -i "<ns>/<pkg>:$REF_NAME" --cascade \
        --announce-file "$TAGS_FILE" <artifact-layers>...
      ocx package announce --package <ns>/<pkg> \
        --tags-file "$TAGS_FILE" --fork <your-account>/index

  - name: Clean up announce-tags scratch file
    if: always()
    run: rm -f "$TAGS_FILE"
```

Two details in that block are load-bearing rather than stylistic, and both
are easy to "simplify" back into bugs.

**No <span v-pre>`${{ }}`</span> inside any `run:` script.** Everything a
script needs arrives as an environment variable — `REF_NAME` and the token
from the job's `env:` block, `TAGS_FILE` via `$GITHUB_ENV`, and
`$RUNNER_TEMP` / `$GITHUB_RUN_ID` / `$GITHUB_RUN_ATTEMPT` from the runner's
own defaults. <span v-pre>`${{ }}`</span> is textual substitution performed
*before* the shell sees the script, so a value
containing `$(...)` or a backtick inside `run:` executes as code. A git tag is
a perfectly legal place to hide such a payload, and `github.ref_name` on a
tag-triggered release workflow is exactly that tag. Quoting the expansion does
not help; only keeping it out of the script text does.

**The token gate reads `env`, not `secrets`.** `secrets` is not one of the
contexts available to a step-level `if:` —
<span v-pre>`if: ${{ secrets.X != '' }}`</span> is not a subtly weaker check,
it is a workflow that fails to parse. Mapping the secret
into the job's `env:` once and testing `env.OCX_ANNOUNCE_TOKEN` is both valid
and the reason the `env:` block sits at job level.

Every flag in that block matches the shipped binary (`ocx package push
--help`, `ocx package announce --help`). Pin `setup-ocx` to a commit SHA from
the [`ocx-sh/setup-ocx`][setup-ocx] README.

## Classic PAT Setup {#classic-pat-setup}

Fine-grained PATs cannot open pull requests against a public repository they
don't own — a known [GitHub Actions][gh-actions] platform limitation, tracked
at [github/roadmap#600][github-roadmap-600], not an OCX restriction. Until
that changes, `OCX_ANNOUNCE_TOKEN` has to be a **classic** PAT, scoped to
`public_repo`, stored as a repository or organization secret named
`OCX_ANNOUNCE_TOKEN`. The token is read from the environment only — `ocx`
never writes it into the credential store it otherwise uses for registry
auth (X6). See [Machine-Account Recommendation][machine-account] for who
should hold that PAT.

## Machine-Account Recommendation {#machine-account}

Issue the classic PAT under a dedicated bot GitHub account rather than a
person's own account — the same pattern OCX's own mirror fleet uses with its
`ocx-bot` account. A bot account keeps PR authorship and token rotation
independent of who's currently on the team: nobody's departure revokes the
token, and nobody's personal PAT-rotation habits silently break the pipeline.

## Missing-Token Degrade {#missing-token-degrade}

The push-and-announce step in the snippet above is gated on the
`OCX_ANNOUNCE_TOKEN` secret being non-empty (see its `if:` condition in the
snippet above) — deliberately, so a fork of your own repository, which
GitHub never hands the secret to, doesn't hard-fail its CI just by existing.
When the token genuinely is required for a run and it's absent, `ocx
package announce --fork` exits `80` (`AuthError`) with a message naming the
missing variable, not a stack trace (C13). If you have no PR-capable token at
all, see [No-Token Manual Fallback][no-token-fallback] — that's a different
situation from this one.

## No-Token Manual Fallback {#no-token-fallback}

This is distinct from the [degrade above][missing-token-degrade]: it's for
publishers who genuinely have no classic PAT or machine-account token
available, not for a fork's CI run that's supposed to stay silent.
`--out <dir>` is mutually exclusive with `--fork`:

```sh
ocx package announce --package <ns>/<pkg> --tags-file <path> --out <dir>
```

writes the updated root and any new CAS objects to `<dir>` on disk instead of
opening a PR. You commit that directory's diff to your own fork by hand and
open the pull request yourself through GitHub's UI. It's the same shape as
[winget-create][winget-create-submit]'s `--output` flag, which writes a
manifest to disk instead of submitting it — a local-write mode that hands the
actual submission step back to the publisher.

## Fork Auto-Create {#fork-auto-create}

If `<your-account>/index` doesn't exist yet, `ocx package announce --fork`
creates it — idempotently, so re-running the same command is safe — before it
pushes anything. There's no separate "fork this repository" step to remember
(C8); the first announce run does it for you.

## The Reference Tool (`indexbot announce`) {#reference-tool}

This is an aside, not the primary path — most publishers should use
[the `ocx` CLI][the-ocx-cli-path] above. `indexbot announce`, the Python tool
living in this repo's `bot/`, is the **executable spec** the Rust client is
byte-conformance-tested against: whatever it produces for a given curated tag
set is the ground truth `ocx package announce` has to match (FP-9). It's
handy for local dry-run debugging via its own `--out <dir>` local-write mode,
but it isn't required for ordinary publishing.

## PR and Auto-Merge Semantics {#pr-and-auto-merge-semantics}

An announce PR is classified into one of two lanes (see
[Governance Contracts][governance-contracts]):

- **Machine lane**, eligible for auto-merge: the change is an owner-authored
  tag content refresh and/or an owner-authored tag add/remove, the PR
  author's `github_id` is in the target root's committed `owners[]` on every
  root the PR touches, no human-review-required key (G-05) is touched, and
  it isn't a new package. Once required checks are green, GitHub merges it —
  no human clicks anything, and the merge commit is authored by
  `github-actions[bot]` (FP-5). End to end, a release workflow pushing a tag
  to an already-claimed package lands in the index in about three minutes.
- **Human lane**, everything else: a new package (G-04), a change to a
  human-review-required key, or a PR authored by someone who isn't a listed
  owner. These route to a reviewer assigned from
  [`.github/maintainers.yml`][maintainers-yml] plus an idempotent
  review-request comment, and wait for approval — no matter how green the
  automated checks are (FP-6).

## Future {#future}

::: details Future
`ocx dist`, a planned cargo-dist-style workflow renderer, will eventually
generate the snippet above for you instead of copy-paste — it hasn't been
built yet (S11).

A GitLab CI/CD Component is a confirmed future track for publishers who build
on GitLab instead of GitHub Actions. It needs no new server-side capability:
even a GitLab-CI publisher only ever talks to the GitHub API against this
GitHub-hosted index, the same way the snippet above does.

Signing and attestation for announced packages is tracked separately, not
part of this flow yet — see [ocx-sh/ocx#199][ocx-199] and
[#203][ocx-203].
:::

## See Also {#see-also}

- [Claim a Namespace][claim-a-namespace] — the one-time step before your
  first announce
- [`CONTRIBUTING.md`][contributing] — PR lanes, spam posture, and what
  auto-merges
- [Governance Contracts][governance-contracts]

<!-- TODO(Track B): once governance-contracts.md gains G-19/G-20 rows, retarget this to #g-19 / #g-20 -->

<!-- external -->
[github-roadmap-600]: https://github.com/github/roadmap/issues/600
[gh-actions]: https://docs.github.com/en/actions
[setup-ocx]: https://github.com/ocx-sh/setup-ocx
[winget-create-submit]: https://github.com/microsoft/winget-create/blob/main/doc/submit.md
[ocx-199]: https://github.com/ocx-sh/ocx/issues/199
[ocx-203]: https://github.com/ocx-sh/ocx/issues/203

<!-- internal -->
[claim-a-namespace]: ./claim-a-namespace
[contributing]: https://github.com/ocx-sh/index/blob/main/CONTRIBUTING.md
[governance-contracts]: ../reference/governance-contracts
[maintainers-yml]: https://github.com/ocx-sh/index/blob/main/.github/maintainers.yml
[the-ocx-cli-path]: #the-ocx-cli-path
[classic-pat-setup]: #classic-pat-setup
[machine-account]: #machine-account
[missing-token-degrade]: #missing-token-degrade
[no-token-fallback]: #no-token-fallback
[fork-auto-create]: #fork-auto-create
[reference-tool]: #reference-tool
[pr-and-auto-merge-semantics]: #pr-and-auto-merge-semantics
