# Index Bot Security Guardrail (consumer side)

Always-loaded (no `paths:`) — the announce lane is the highest-risk surface
this repository operates. The bot's *code* now lives in
[ocx-sh/indexbot](https://github.com/ocx-sh/indexbot) and carries its own
security bar (coverage, serializer, untrusted-input hygiene, per-contract
tests); this file governs what stays here: the workflows, the deployment
policy, and which bot version runs.

Design authority: ADR-6 (`adr_fork_pr_announce.md`, FP-1/FP-4/FP-5/FP-7),
ADR-4 (`adr_index_bot_and_workflow_security.md`, BD-3/BD-4/BD-5 + Amendment
A1) in `.claude/artifacts/`.

## Security bar (Block-tier — never negotiate)

- **One trigger per workflow file.** `pull_request` and `pull_request_target`
  fire on the same PR head commit, so a workflow declaring both must pick a
  half with a job-level `if: github.event_name == ...` — and a job skipped by
  such an `if:` STILL emits a check run, conclusion `skipped`, under its own
  name. GitHub counts `skipped` as satisfying a required status check and
  resolves duplicate-named contexts to the most recent, so the privileged run
  publishes a green-equivalent impostor of the unprivileged half's required
  context. That is why `schema-validate-pr` (`validate.yml`, `pull_request`)
  and `governance-gate`/`arm-auto-merge` (`governance.yml`,
  `pull_request_target`) live in separate files. Never merge them back, and
  never re-add a `github.event_name` guard to either.
- **Untrusted-PR-data-only contract.** The privileged governance job
  (`pull_request_target`, `governance-gate` in `governance.yml`) NEVER checks
  out or executes PR-head content. It acts through the GitHub API and
  base-branch data only. PR-head code runs solely in the zero-secret
  `pull_request` job. Any workflow edit that adds a PR-head checkout (`ref:` at
  `pull_request.head`) to a credentialed job breaks the entire safety argument
  (FP-7, G-16).
- **The allowlist is a committed file, never a variable.** G-03's host set is
  per-deployment policy (`.github/index-policy.json`). Never move it to an env
  var, `vars.` or `secrets.` — "extend only via reviewed PR" is the control,
  and a settings-page value widens registry trust with no diff and no
  reviewer. This deployment's policy stays exactly `{"ghcr.io", "ocx.sh"}`,
  pinned by a named test in `bot-tools/tests/security/`.
- **The bot version is pinned, hash-locked and bumped by pull request.**
  `bot-tools/pyproject.toml` pins an exact `ocx-indexbot==X.Y.Z` and
  `bot-tools/uv.lock` hashes the transitive set; every job runs
  `uv sync --frozen`. The privileged governance job executes that code, so a
  floating version (`>=`, `~=`, a bare `uvx ocx-indexbot`) would let a
  compromised release run with a write-scoped token and no reviewer — the same
  argument that keeps the host allowlist a committed file.

## Test bar (do not lower)

- `task bot:test` — `bot-tools/tests/security/` asserts what only this
  deployment can: the workflow split and its job arrangement
  (`test_workflow_split.py`), `validate.yml`'s changed-files pathspec
  (`test_workflow_pathspec.py`, replayed against real `git`), the shipped
  registry policy and the retired-surface absences
  (`test_deployment_policy.py`). Changing a governance workflow means updating
  its named test in the same change.
- `task bot:workflows` — `indexbot workflows-check`, the package's
  deployment-independent invariants (WF-01..WF-07) over this repo's tree.
  Both are CI jobs; neither is optional.
- A bot-side rule change (a G-05 key, a lane decision, an anomaly predicate)
  belongs in `ocx-sh/indexbot` with its own named test, and arrives here as a
  version bump.

## Untrusted-input hygiene in workflows (BD-4, carried forward)

- Pass untrusted values via env-var indirection, never `run:` interpolation.
- Untrusted PR content that reaches a step summary goes inside a fenced block,
  never into a `::error` title or any shell-evaluated position.
- Any `client_payload`-style field is length-capped, then `re.fullmatch`ed,
  and rejected on `..`/absolute paths — never `match`/`search`.
