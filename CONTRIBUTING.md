# Contributing to ocx-sh/index

## What This Repo Is

This is the source of truth for the OCX public package index, served as a
static sparse HTTP index at [index.ocx.sh](https://index.ocx.sh) — no
server, no database. Root files here map logical package names
(`ocx.sh/kitware/cmake`) to physical OCI registries via content-digest
observation objects. Most contributions are pull requests against `p/`, the
package-root tree, opened either by hand or by the `ocx` CLI / `indexbot`.

## Announcing a Package

If you're here to publish or refresh a package, you don't need to hand-edit
anything in this repo. See
[Announce a Package](site/src/docs/how-to/announce-a-package.md) for the
`ocx` CLI flow, and
[Claim a Namespace](site/src/docs/how-to/claim-a-namespace.md) first if this
is your namespace's first entry.

## PR Lanes

Every PR against this repo — an announce, a claim, a yank, or a code
change — is classified by a privileged governance job into one of two lanes.
The classifier reads the PR's author and changed-file diff via the GitHub
API only; it never checks out the PR's head content.

## What Auto-Merges

A PR is machine-lane, and eligible for auto-merge once required checks are
green, only when **all** of the following hold:

- the change is a tag content refresh and/or an owner-authored tag
  add/remove — not a new package;
- the PR author's `github_id` is in the committed root's `owners[]`, on
  every package root the PR touches;
- no human-review-required key is touched: `repository`, `owners`,
  `status`, `deprecated_message`, `superseded_by`, or an existing tag row's
  `yanked` field (G-05).

Owner-authored tag curation is machine lane by design: under owner-curated
tags, adding or removing a tag *is* the owner exercising their own curation
authority, and needs no third party's review — only proof the author is a
listed owner (FP-5).

## What Never Auto-Merges

Everything else routes to the human lane, and stays blocked regardless of
how green the automated checks are:

- **a new package** (G-04) — a first claim is always human-reviewed, no
  matter how many owners are listed or how green the checks are;
- **a change to a human-review-required key** (G-05, listed above);
- **a PR authored by a non-owner** — someone whose `github_id` isn't in the
  target root's `owners[]` can't refresh a package they don't own without a
  human deciding to accept it.

Human-lane PRs get reviewers assigned by the governance job from
[`.github/maintainers.yml`](.github/maintainers.yml), plus an idempotent
bot comment requesting review (FP-6).

## Spam and Abuse Posture

This repo runs an open PR lane: anyone with a GitHub account can open a pull
request, including a first-time contributor. The v1 posture is deliberately
minimal (FP-8):

- No CAPTCHA, no allowlist, no first-contributor approval wall.
- Fork PRs that fail their checks are labeled and stale-closed on the
  ordinary schedule — standard open-source triage, no bespoke machinery.
- GitHub's own
  [secondary rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
  already throttle PR storms.
- The verification gate — every claimed tag is re-derived from the physical
  registry and byte-compared before anything merges — means a spam PR
  cannot merge harmful content. The worst case is triage noise, not a bad
  publish.

Heavier controls (fork-run approval gating for first-time contributors, an
allowlist) are additive if real abuse shows up; they aren't built ahead of
evidence.

## Contributing to the Bot/Site/Schema Code

Changes to `bot/`, `site/`, or `schema/` follow the dev workflow documented
in [`CLAUDE.md`](CLAUDE.md) — run `task verify` before opening a PR. Commit
messages follow [Conventional Commits](https://www.conventionalcommits.org/).

## See Also

- [Announce a Package](site/src/docs/how-to/announce-a-package.md)
- [Claim a Namespace](site/src/docs/how-to/claim-a-namespace.md)
- [Governance Contracts](site/src/docs/reference/governance-contracts.md)
