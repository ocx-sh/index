# ADR: Fork-PR Announce Lane — Owner-Curated Tags, Verify-Only Reconcile

<!--
ADR-6. Companion to the 2026-07-17/18 announce-revamp discussion
(decision_log_2026-07-18.md). Owns the announce transport, tag provenance,
reconcile posture, and the governance lane split; amends
adr_public_index_registry_indirection.md (D4/D5), ADR-1 (`tags` provenance),
and ADR-4 (BD-4/5/6 + the G-table).
-->

## Metadata

**Status:** Accepted
**Date:** 2026-07-18
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** security | ci-cd | governance | integration
**Amends:** D4 (announce protocol) and D5 (bot merge policy) of
[`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md);
BD-4/BD-5/BD-6 and the G-01…G-18 carry-forward table of
[`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
(ADR-4, Amendment A1 there); the `tags` provenance rows of
[`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)
(ADR-1)
**Supersedes:** N/A (amends the above at row/decision level; see each doc's amendment marker)
**Superseded By:** N/A

## Context

The announce path decided in the original design bundle — D4 of
[`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md)
("announce = doorbell"), given CI mechanics by BD-4/BD-6 of
[`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
— is a `repository_dispatch` trigger fired from publisher CI. The trigger carries a
`client_payload` naming a package; the bot re-derives that package's entry from
registry truth and opens (then auto-merges) a PR. Firing `repository_dispatch`
against `ocx-sh/index` is **never anonymous**: GitHub requires a token scoped to the
target repo ([Triggering a workflow](https://docs.github.com/actions/using-workflows/triggering-a-workflow)),
which BD-6 (G-17) resolved as a per-publisher fine-grained PAT.

That PAT is the dead end. A fine-grained PAT scoped to `ocx-sh/index` can only be
minted by an account with collaborator access to `ocx-sh/index` — a third party
cannot mint one at all without first being granted access to the very repo the index
is trying to keep closed. The doorbell therefore cannot scale to the stated ambition
of "thousands of contributors": every publisher would need an index-side credential,
and the index would need to issue, scope, rotate, and revoke one per namespace. The
credential requirement is not a hardening detail — it is a structural ceiling on who
can publish.

The rest of the ecosystem does not have this ceiling. Every open registry surveyed in
[`research_index_announce_bots.md`](./research_index_announce_bots.md) — the
[Bazel Central Registry](https://github.com/bazelbuild/bazel-central-registry),
[winget-pkgs](https://github.com/microsoft/winget-pkgs), Homebrew, the
[OpenTofu Registry](https://github.com/opentofu/opentofu/issues/724) — accepts
contributions the ordinary open-source way: a pull request from a fork, under the
contributor's own GitHub identity, gated by CI and a trust decision cached in the
repo (a maintainer list, a verified-publisher label). No contributor holds a
credential *on the registry*. This ADR moves `ocx-sh/index` onto that model and
records the two provenance shifts it forces (owner-curated tags, verify-only
reconcile) plus the wire-discipline and governance rules that make an untrusted
fork PR safe to auto-merge.

The wire format itself does not change. The four frozen URL shapes
([`product-context.md`](../rules/product-context.md)) and the observation-object
layout (ADR-1 D2/D4) are untouched. What changes is **transport** (dispatch → fork
PR), **`tags` provenance** ("every observed tag" → "every announced tag"), and
**reconcile posture** (regenerate-and-write → verify-only). None of these is a
`format_version` break — a resolving client sees identical bytes and identical
semantics (FP-2 elaborates why the provenance flip is invisible to a client).

## Decision Drivers

- **No index-side credential in the publish path.** The doorbell's single structural
  fault is that publishing requires a token on `ocx-sh/index`. Removing that is the whole
  point; every decision below is subordinate to it.
- **Registry truth still wins.** The fork PR *claims* a root and CAS objects, but nothing
  claimed is trusted — CI re-derives every claimed tag from the registry and byte-compares
  (D5's chain, reused). This is D4's "the doorbell can't lie", carried to a payload that
  is now a file tree instead of a package id.
- **Authorization is data already in the root.** `owners[].github_id` (ND-8) is an
  immutable, rename-proof numeric identity — the natural key for "may this author refresh
  without human review", needing no new credential or store.
- **Boring GitHub-native primitives.** Fork PRs, `pull_request` / `pull_request_target`,
  branch protection, `gh pr merge --auto`, a committed YAML reviewer list — all ship with
  GitHub. No relay service, no webhook host, no long-lived secret.
- **The privileged/unprivileged split stays load-bearing.** BD-5's posture — untrusted
  PR-head code runs only in a zero-secret job; the credentialed job never checks out PR
  head — is exactly the defense a fork-PR lane needs (FP-7).

## Industry Context & Research

**Research artifact:** [`research_index_announce_bots.md`](./research_index_announce_bots.md)

That research concluded D4/D5's trust-once-then-doorbell shape matches every mature
index and recommended *not* redesigning it. This ADR keeps the trust model and
redesigns only the **transport** — the one open leg the research named ("how the
announce signal reaches the bot and how the bot authenticates the announcer"). Its own
findings point at the fork-PR answer:

- The [Bazel Central Registry](https://github.com/bazelbuild/bazel-central-registry)
  authorizes a version bump by whether a maintainer *listed in the module's own
  `metadata.json`* can approve it — trust cached as in-repo data, not a per-publisher
  registry credential. `owners[].github_id` is OCX's equivalent (FP-5, G-19).
- [winget-pkgs](https://github.com/microsoft/winget-pkgs) and Homebrew gate auto-merge
  on a *pre-established trust marker* (a verified-publisher label; the absence of a
  `new-formula`/`new-package` label) — the "label-as-trust-cache" pattern. OCX reads
  that marker straight from the root's `owners[]`.
- The [OpenTofu Registry](https://github.com/opentofu/opentofu/issues/724) is the
  closest analog: **PR = trust establishment (rare, human); refresh = frequent, no
  human, re-derived from source truth**. OCX collapses both onto one transport (the PR)
  and lets the governance gate pick the lane per-PR.
- [Go's sumdb](https://go.googlesource.com/proposal/+/master/design/25530-sumdb.md) and
  crates.io re-derive content from the authoritative source and never trust the
  announcer (the anti-tamper property OCX keeps, D5 chain, FP-4). crates.io's transport
  — one authoritative server, zero PRs — is unavailable to OCX ("zero production
  services"); a PR with CI as the writer is the closest boring analog.

**Key insight carried forward:** the fork PR *is* the doorbell — claimed root + CAS tree
as payload, unprivileged CI re-derivation as the "can't lie" check, `owners[]` membership
as the trust cache deciding auto-merge vs. review. Every piece had a research precedent;
the doorbell was simply pointed at the wrong GitHub primitive.

## Considered Options

### Option 1 (chosen): fork PR is the announce transport

**Description:** publishers open an ordinary pull request from a fork, under their own
GitHub identity. The PR carries the claimed root and CAS objects. CI re-derives and
verifies; `owners[]` membership decides the lane.

| Pros | Cons |
|---|---|
| Zero index-side credential for any publisher — removes the structural ceiling | Untrusted PR-head content now enters the repo; leans hard on BD-5's split (FP-7) |
| Reuses the ordinary open-source contribution flow every publisher already understands | Anyone can open a PR — spam surface (addressed by FP-8) |
| Authorization is `owners[].github_id`, data already in the root (ND-8) | The claimed tree must be byte-exact to survive canonical re-serialization (FP-4) |
| Matches BCR/OpenTofu/winget precedent exactly | |

### Option 2 (rejected): keep the `repository_dispatch` PAT doorbell

| Pros | Cons |
|---|---|
| Already designed (BD-4/BD-6); payload is a tiny package-id, easy to validate | **The structural fault this ADR exists to remove** — every publisher needs a mintable-only-by-collaborator PAT on `ocx-sh/index`; cannot scale past hand-issued credentials |
| Bot fully controls re-derivation; no claimed file tree to verify | Index must issue/scope/rotate/revoke one PAT per namespace forever — standing secret-management burden |

### Option 3 (rejected): a GitHub App as the announce credential

**Description:** an org-installed GitHub App mints short-lived installation tokens per
publisher, replacing the long-lived PAT.

| Pros | Cons |
|---|---|
| Ephemeral tokens (1h), scoped per install — the OIDC-adjacent direction the research flagged as trending | Still a **credential the index must provision per publisher** — the ceiling moves from "mint a PAT" to "install an App", not gone |
| Removes the long-lived-secret rotation problem | Adds a hosted App (webhook endpoint, registration, key custody) — a production moving part the "zero production services" driver forbids |
| | Deferred already in BD-6 as a v2 idea; solves secret *lifetime*, not the *who-can-publish* ceiling |

### Option 4 (rejected): issue-ops / `repository_dispatch` relay

**Description:** publishers file a structured issue (or comment); a privileged relay
workflow parses it and fires an internal `repository_dispatch`, so no publisher holds a
dispatch token.

| Pros | Cons |
|---|---|
| No publisher credential; anyone with a GitHub account can file an issue | A privileged workflow parsing attacker-controlled issue bodies is exactly the injection surface [GitHub Security Lab](https://securitylab.github.com/resources/github-actions-untrusted-input/) warns against — worse threat shape than a fork PR, not better |
| Familiar IssueOps ergonomics | Re-invents PR review/CI/merge as a bespoke issue state machine — a second orchestration layer the "boring technology" driver rejects |
| | The claimed data still has to be re-derived and verified somewhere; the issue body is a worse carrier than a committed file tree a diff can inspect |

**Chosen:** Option 1. The decisive line is the driver: Options 2 and 3 keep an
index-side credential (the exact ceiling); Option 4 removes the credential but replaces
it with a worse injection surface and a bespoke state machine. Only the fork PR removes
the credential *and* stays on GitHub-native, already-understood primitives.

## Decisions

### FP-1 — The fork PR is the announce transport; identity, authorization, and verification are separated

Announce is an ordinary pull request from a fork of `ocx-sh/index`, opened under the
publisher's own GitHub identity. No `repository_dispatch`, no publisher-held index-side
credential. The three concerns the doorbell fused into one PAT are split into three
independent, already-existing mechanisms — the BCR trust model applied to OCX's data:

- **Identity = the GitHub account** that authored the PR. GitHub authenticates it; the
  index does not issue it.
- **Authorization = `owners[].github_id`** in the *committed* (base-branch) package
  root. A PR author whose numeric id is in that array is an owner. `github_id` is
  immutable and rename-proof (ND-8) — the login string is display only, never the
  authorization key.
- **Verification = CI re-derivation from registry truth.** The PR *claims* a root and
  its CAS objects; nothing claimed is trusted. Unprivileged CI walks each claimed tag,
  re-derives the observation object from the physical registry, and byte-compares
  against the claimed CAS object (D5's verifiability chain, FP-4). A claim that
  disagrees with the registry fails the check — D4's "the doorbell can't lie", now
  applied to a claimed file tree rather than a package-id payload.

Separating the three is what lets an *untrusted* PR be safely auto-merged: identity is
GitHub's problem, authorization is a lookup against committed data, and content is never
trusted — only re-derived.

### FP-2 — Owner-curated tag sets: `tags` is "every announced tag", not "every observed tag"

The `tags` map's provenance flips. Under ADR-1 D2 the bot regenerated `tags` as *every*
tag observed on the physical repository, no filtering. Under this ADR the owner
**announces the tags they choose**; the announce PR is the sole authority that adds or
removes a tag from the set. The bot no longer enumerates the registry to populate
`tags` — it verifies the *curated* set the owner announced.

This is a governance/provenance change, **not a wire-format change and not a
client-visible one**. The `tags` map shape (tag name → `{content, observed, yanked?}`,
ADR-1 D2) is byte-identical. A resolving client asks "does tag *X* resolve, and to what"
and reads the row; it never depended on the map being *complete* — completeness was an
internal reconcile property, never a client guarantee (the index never promised "absent
here ⇒ absent on the registry"). Each present row is still content-verified against
registry truth (FP-1) — only set *membership* is now owner-decided.

**Yank ≠ delete** — curation makes distinct two operations the observe-everything model
conflated:

- **Delete** — the owner drops a tag from the announced set; the row disappears.
- **Yank** — the owner marks a still-present row `yanked` (ADR-1 D2's `{reason, at}`): a
  **migration-grace marker** that survives regeneration, keeps resolving for
  pinned/lockfile consumers, and signals "exists, do not adopt for new installs." A
  yanked row is exempt from reconcile's registry-existence check (FP-3) — a yanked tag
  whose registry manifest is gone is grace, not an anomaly.

Mutating an existing row's `yanked` field stays in the G-05 human-review key set (ADR-4)
— yank is a lifecycle assertion, not a content refresh.

### FP-3 — Verify-only reconcile: no write path

Nightly reconcile becomes **verify-only**. It never adds, removes, or rewrites a tag,
never opens a content PR, never commits. For every *committed* claim it checks the
physical registry: the announced tag still resolves, and the manifest digest still
matches the committed observation object. Inconsistencies — a vanished non-yanked tag, a
digest that moved under a pinned tag, a dangling CAS reference — are surfaced to humans
via the anomaly issue path (ADR-4 BD-2 exit `65`, reused), never auto-healed.

This is the direct consequence of FP-2: once the owner curates the tag set, reconcile
*cannot* be the authority that regenerates it — regenerating from observation would
silently overwrite the owner's curation with "whatever the registry currently has,"
re-conflating the two authorities FP-2 just separated. Reconcile's job narrows from
"regenerate and reconcile drift" to "verify the committed claims still hold, and shout
if they don't." Its integrity value (catch tamper, catch registry compromise, catch
drift) is fully retained; only the write leg is removed.

Consequence for ADR-4 G-18: the `RECONCILE_DRY_RUN` gate collapses into "always dry."
A verify-only reconcile has no mutating mode to gate, so the variable is retired (see
ADR-4 Amendment A1).

### FP-4 — Byte-exact wire discipline: the root serializer becomes a published spec

Because a fork PR *claims* file bytes the index will serve verbatim, the exact
serialization of a package root becomes a **client-facing contract**, not a private
render detail. Two CI checks enforce it on every announce PR, both unprivileged:

- **CAS objects** are already content-addressed — the file at `o/sha256/<hex>.json`
  must hash to `<hex>` (ADR-1 D5). A claimed CAS object whose bytes do not hash to its
  path fails. This check already existed; the fork-PR lane makes it load-bearing for
  untrusted input. It extends to **every** package-local CAS file a fork PR can claim:
  the desc blobs `o/sha256/<hex>.{md,svg,png}` (readme/logo, ADR-1 D2/D6) are hash-
  verified against their path digest the same way as observation objects — closing the
  gap that, on the old doorbell path, only tag observation objects were hashed (this
  gap closure is owner-decided for the fork-PR lane).
- **The root** must be **canonical**: CI parses the claimed root, re-serializes it with
  the index's canonical serializer, and byte-compares. A root that is not already in
  canonical form fails. This closes the gap that the root — unlike a CAS object — has no
  self-certifying digest in its own path, so canonical form is the only way to make
  "what the publisher claimed" and "what the index serves" the same bytes by
  construction.

The canonical root serializer is therefore a **published spec** any out-of-tree
publisher (including the Rust client, FP-9) can reproduce exactly — the same status
`bot/CONTRACTS.md` §1's canonical JSON already has for CAS digest inputs. Its exact form
(key order, indentation, newline, escaping) is fixed in `bot/CONTRACTS.md` (Phase 2);
this ADR fixes only that it *is* a client-facing spec, enforced by parse-then-re-serialize
byte comparison.

### FP-5 — Two governance lanes; G-19 gates the machine lane on owners-membership

Every announce PR is classified by the privileged governance job into one of two lanes.
The classifier reads the PR's author and changed-file diff **via the GitHub API only**,
never by checking out PR head (BD-5, unchanged):

- **Machine lane** (eligible for auto-merge): the change is a **tag content refresh
  and/or an owner-authored tag add/remove** (FP-2), *and* the PR author's `github_id` is
  in the committed root's `owners[]`, *and* no G-05 human-review key
  (`repository`, `owners`, `status`, `deprecated_message`, `superseded_by`, or an
  existing row's `yanked` value) is touched, *and* it is not a new package.
  Owner-authored tag add/remove is machine
  lane because, under owner curation, adding/removing a tag *is* the owner exercising
  their curation authority — it needs no third party's review, only proof the author is
  an owner.
- **Human lane** (blocks auto-merge, routes to review): any PR that is a new package
  (G-04, unchanged — new package is human lane by design), touches a G-05 key, or is
  authored by a **non-owner** (`github_id` ∉ `owners[]`). A non-owner cannot refresh a
  package they do not own without a human deciding to accept it.

**G-19 (new) — Owners-membership gate for the machine lane.** A fork PR qualifies for
auto-merge only if its author's `github_id` is a member of the target root's committed
`owners[]`. Evaluated by the privileged governance job from PR metadata (author id) and
base-branch root (`owners[]`) — never from PR-head content, so a PR cannot authorize
itself by editing its own `owners[]` (that edit is a G-05 change, which is human lane by
definition). G-19 is the machine-lane analog of BCR's "approvable by a listed
maintainer."

G-19 is evaluated **per root**: a PR touching *N* package roots is machine-lane only if
its author passes the `owners[]` check on **every** touched root — one non-owned root
routes the whole PR to the human lane. The reference tool (FP-9) produces single-package
PRs by construction, but an arbitrary fork PR is not so constrained, so the check is
per-root, not per-PR.

Auto-merge itself is unchanged from BD-5: branch protection plus `gh pr merge --auto
--squash` composed with the `governance/review-required` status check. The only new
condition on going green is G-19.

### FP-6 — Maintainers YAML: human-lane reviewer assignment (G-20)

**G-20 (new) — Maintainers-YAML reviewer assignment.** Human-lane PRs get reviewers
assigned by the privileged governance job from a committed `maintainers.yml`
(repo root or `.github/`; schema: a list of `{github, github_id}` entries — GitHub
logins for the review-request API, numeric ids for stable identity), plus an
**idempotent** bot comment requesting review. G-20 is the human-lane counterpart of
G-19: where the machine lane routes an owner-authored change to auto-merge, the human
lane routes everything else to a named human, rather than letting it sit unassigned.

`maintainers.yml` is committed repo data reviewed through the ordinary PR gate — the
same "trust cached as in-repo data" pattern as `owners[]`, one level up (index
maintainers rather than package owners). The governance job reads it from the base
branch (never PR head). Assignment and the review-request comment are idempotent so a
re-run on a new push does not spam.

### FP-7 — Threat-model reframe: no standing index-side secret in the announce path

The doorbell's threat model was "untrusted trigger input plus a write credential in the
same execution surface" (ADR-4 Context) — defended by never trusting the payload. The
fork-PR lane reframes it: there is **no long-lived, publisher-held, or namespace-scoped
secret anywhere in the announce path**. The publisher holds nothing on the index. The
only credential in play is the ambient, per-run `GITHUB_TOKEN` held by the privileged
governance job, which **never checks out PR-head content** and acts only through the
GitHub API (labels, status, review requests, auto-merge arming).

Three load-bearing invariants, restated for the fork-PR shape (BD-5 verbatim — the
fork-PR lane is precisely the scenario BD-5 was written to defend):

- Untrusted PR-head content runs **only** in the `pull_request` verification job, which
  holds **no secrets** (GitHub strips them for fork `pull_request`) and does anonymous
  registry reads only — hostile content runs where there is nothing to steal.
- The `pull_request_target` governance job (classify, G-19, G-20, arm auto-merge) reads
  the diff via the GitHub API and the root via the base branch — **never** `git checkout`
  of the fork ref.
- Auto-merge is armed by the privileged job *only after* the unprivileged verification is
  green — the credentialed step trusts the *check result*, never the claimed bytes.

Net: the reframe removes a whole credential class (the per-publisher PAT) and leans on
the split that already existed. The split is not new; its importance is.

### FP-8 — Spam posture: label and stale-close, no gatekeeping in v1

An open fork-PR lane means anyone can open a PR. v1 posture is deliberately minimal:

- Fork PRs that fail their checks are **labeled** (a failed-check / stale label) by the
  governance job and **stale-closed** on the ordinary schedule — the standard
  open-source triage move, no bespoke machinery.
- **No CAPTCHA, no allowlist, no first-contributor approval wall in v1.** GitHub's own
  secondary rate limits already throttle PR storms
  ([REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)),
  and the verification gate (FP-1/FP-4) means a spam PR cannot merge anything — the
  worst case is triage noise, not a bad publish.

Heavier abuse controls (fork-run approval gating for first-time contributors, an
allowlist) are available additively if real abuse appears; they are not built ahead of
evidence (see Deferred).

### FP-9 — Reference implementation and the ocx#216 relationship

`indexbot announce` (ADR-4 BD-1) is **repurposed**, not retired: it becomes the
**Python reference publisher tool**. It curates a tag set (`--tags` / `--tags-file`),
observes only the curated tags, builds the canonical root plus CAS bytes, and writes
them either locally (`--out`, for parity testing) or as a fork PR
(`--fork <owner/repo>`: commit to a fork branch, open the PR against upstream). The
retired pieces are the doorbell-specific ones — the `PACKAGE_ID` env-var trigger path,
the `client_payload` validator, the dispatch caller (ADR-4 BD-4's `validate_payload`
module; Phases 2–3 remove them).

Being the *reference* implementation is load-bearing: it is the executable definition of
the canonical root serializer (FP-4) and the fork-PR flow the OCX Rust client must
match. The Rust `ocx package announce` client command is tracked cross-repo as
**[ocx#216](https://github.com/ocx-sh/ocx/issues/216)** — it ports this contract, it
does not define it. `indexbot announce` and the E2E harness (below) are what ocx#216 is
verified against.

## Technical Details

```
publisher (fork of ocx-sh/index, own GitHub identity)
  indexbot announce --tags <curated> --fork <owner/fork>
    observe only curated tags → build canonical root + CAS bytes
    commit to fork branch → open PR against ocx-sh/index          (no index-side credential)
  ▼
validate.yml
  ├─ job: verify-claims        (pull_request, PR-head checkout, ZERO secrets)
  │    canonical-root byte-compare (FP-4) + CAS hash self-check
  │    per claimed tag: re-derive observation object from registry, byte-compare (FP-1)
  │    anonymous GHCR reads only
  └─ job: governance-gate      (pull_request_target, GITHUB_TOKEN only, NEVER checks out PR head)
       classify: machine lane (owner + refresh/curation) | human lane (new-pkg | G-05 key | non-owner)
       G-19: author github_id ∈ base-branch owners[] ?  → machine-lane green
       G-20: human lane → assign reviewers from maintainers.yml + idempotent review-request comment
       failed checks → label + stale-close (FP-8)
  ▼
branch protection: verify-claims + governance/review-required both required
  machine lane, both green → gh pr merge --auto --squash
  human lane               → blocked until a maintainer approves

reconcile.yml (nightly cron)  — VERIFY-ONLY (FP-3)
  for every committed tag: registry tag resolves? committed digest matches?
    yanked rows: registry-existence exempt (grace marker, FP-2)
    inconsistency → anomaly issue (exit 65), NEVER a write
  no index-write environment, no content PR, issues: write only
```

## Consequences

**Positive:**
- Removes the structural ceiling: any GitHub account can publish, no index-side
  credential to issue, scope, rotate, or revoke — the "thousands of contributors" model
  becomes reachable, on GitHub-native primitives only (contrast Options 3 and 4).
- Deletes a whole credential class from the threat surface (per-publisher PAT), leaning
  on the privileged/unprivileged split that already existed (FP-7).
- Owner-curated tags (FP-2) give the owner real control over what their package
  advertises, and finally separate yank (grace) from delete (remove).
- Reference `indexbot announce` (FP-9) is the executable spec ocx#216 ports against —
  the wire discipline (FP-4) is testable, not just described.

**Negative:**
- Untrusted PR-head content now enters the repo; correctness depends entirely on BD-5's
  split holding everywhere (FP-7) — one privileged step that checks out PR head is a real
  vulnerability, so the split must be audited, not assumed (Phase 6).
- An open PR lane is a spam surface; v1 accepts triage noise as the cost (FP-8).
- Reconcile can no longer self-heal drift by rewriting — only flag it (FP-3); fixing
  flagged drift is now an owner PR.
- The canonical-root spec (FP-4) is a new client-facing contract any publisher
  implementation (including ocx#216) must reproduce byte-for-byte.

**Risks:**
- **Split-integrity risk.** The entire safety argument is "the privileged job never
  touches PR-head content." Any future workflow edit that adds a PR-head checkout to a
  credentialed job silently breaks it. Mitigation: Phase 6 threat review + zizmor; the
  E2E negative cases below assert the boundary end-to-end.
- **Canonical-serializer drift.** If the published serializer and the CI check ever
  disagree, every honest publisher's PR fails. Mitigation: one serializer, one code
  path, exercised by both `indexbot announce` (producer) and the CI check (verifier) —
  same "single source" discipline ADR-1 D10 applied to CAS serialization.
- **Owner-key compromise.** Authorization is `owners[].github_id`; a compromised owner
  account can auto-merge a refresh. This is the same trust boundary BCR/winget accept
  (the maintainer list *is* the trust root); tamper is still caught after the fact by
  reconcile's verify-only integrity check (FP-3) and, later, by the deferred signing
  ADR.

## E2E Validation Strategy

The lane is validated end-to-end against a live GitHub + GHCR sandbox (topology and
scripts in [`plan_announce_revamp.md`](../state/plans/plan_announce_revamp.md) Phase 0/5),
because the load-bearing behavior (fork PR → real `pull_request` / `pull_request_target`
runs → auto-merge) only exists across real repos, not in unit tests:

- **Sandbox topology.** `michael-herwig/ocx-index-e2e` plays `ocx-sh/index` (a content
  copy, not a GitHub fork); `ocx-contrib/ocx-index-e2e` is its fork playing the
  publisher (GitHub forbids same-account self-forks);
  `michael-herwig/ocx-e2e-publisher` ORAS-pushes the pseudo package to
  `ghcr.io/michael-herwig/ocx-e2e-dummy` using an Actions `GITHUB_TOKEN` with
  `packages: write` — **no PAT**, proving the credential-free publish claim concretely.
- **Pseudo package.** `e2e-lab/dummy` (a logical namespace outside the reserved list),
  seeded on sandbox `main` with a curated initial tag set and
  `owners: [{github: michael-herwig, github_id: 3511590}]` — a pre-existing root,
  because a new package is human lane by design.
- **Positive path.** ORAS-push a new tag → `indexbot announce --fork
  ocx-contrib/ocx-index-e2e` → poll PR checks → assert auto-merge landed → assert the
  merged root matches registry truth byte-exactly → `task render:build` + smoke-test the
  local preview (render + local serve is the deploy assertion; no Cloudflare deploy for
  the sandbox).
- **Negative cases (each must fail closed).** Tampered claimed digest → verify-claims
  red; PR author not in `owners[]` → human lane, reviewer assigned, comment posted, no
  auto-merge (G-19); a G-05 key change (`repository`) → human lane (G-20); non-canonical
  root bytes → verify-claims red (FP-4); digest mutation of a pinned tag → reconcile
  anomaly path (FP-3).

## Links

- [`decision_log_2026-07-18.md`](./decision_log_2026-07-18.md) — narrative of the
  2026-07-17/18 discussion this ADR formalizes
- [`plan_announce_revamp.md`](../state/plans/plan_announce_revamp.md) — execution plan
  (Phase 1 is this ADR; Phases 2–7 implement it) and the E2E sandbox topology
- [`research_index_announce_bots.md`](./research_index_announce_bots.md) — BCR / winget
  / Homebrew / OpenTofu / Go / crates.io precedent; the transport leg this ADR settles
- [`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md)
  — D4 (announce protocol) superseded, D5 (bot merge policy) reinterpreted (FP-1/FP-5)
- [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
  — BD-4/BD-5/BD-6 amended, G-08/G-17 retired, G-11/G-12/G-18 amended, G-19/G-20 added
  (Amendment A1 there)
- [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)
  — `tags` provenance rows amended ("every observed tag" → "every announced tag");
  D2 shape and D5 chain unchanged (FP-2/FP-4)
- [`adr_namespace_policy.md`](./adr_namespace_policy.md) — ND-8 (`owners[].github_id`
  mandatory), the authorization key for FP-1/G-19; ND-5 first-claim human review
  (new package = human lane)
- [`product-context.md`](../rules/product-context.md) — `tags` provenance wording, Wire
  Contract design-authority pointer
- [ocx#216](https://github.com/ocx-sh/ocx/issues/216) — the Rust `ocx package announce`
  client that ports this contract (FP-9)
- [Bazel Central Registry](https://github.com/bazelbuild/bazel-central-registry),
  [OpenTofu Registry RFC](https://github.com/opentofu/opentofu/issues/724),
  [Go sumdb design](https://go.googlesource.com/proposal/+/master/design/25530-sumdb.md)
  — transport/trust precedents
- [GitHub Security Lab — untrusted input in Actions](https://securitylab.github.com/resources/github-actions-untrusted-input/)
  — the injection surface Option 4 was rejected against; the split FP-7 preserves

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-18 | Michael Herwig + Claude design swarm | Initial record from the 2026-07-17/18 announce-revamp discussion: fork-PR announce transport (FP-1), owner-curated tags (FP-2), verify-only reconcile (FP-3), byte-exact root discipline (FP-4), two-lane governance + G-19 (FP-5), maintainers-YAML reviewer assignment + G-20 (FP-6), threat-model reframe (FP-7), spam posture (FP-8), reference impl + ocx#216 (FP-9) |
