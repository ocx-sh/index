# ADR: Index Bot Architecture and Workflow/CI Security Posture

## Metadata

**Status:** Accepted
**Date:** 2026-07-17 (decision discussion: 2026-07-16)
**Deciders:** Michael Herwig (owner) + Claude design swarm
**Domain Tags:** security | ci-cd | infrastructure
**Amends:** [adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md)
D4 (announce protocol) and D5 (bot merge policy); carries forward and reinterprets
[`design_spec_registry_indirection.md`](./design_spec_registry_indirection.md) §2f's
governance contracts G-01–G-18 under the locked-observation model — see
[adr_locked_observation_index_format.md](./adr_locked_observation_index_format.md)
**Supersedes:** N/A

## Context

The index bot is the only write path into a public package index. It is triggered by
`repository_dispatch` events whose `client_payload` originates from third-party
publisher CI (`ocx-contrib` and, eventually, other namespaces), and — for the refresh
case — it merges its own pull requests without a human in the loop (D5, "existing entry
refresh... auto-merge"). That combination — untrusted trigger input plus write
credentials in the same execution surface — is structurally the same threat shape as a
`pull_request_target` workflow, even though the trigger event is different. This ADR
treats it that way from the first commit rather than retrofitting hardening after an
incident.

The locked-observation format (`adr_locked_observation_index_format.md`) also changes
what the bot computes. Under the original pointer-only design (§2f of
`design_spec_registry_indirection.md`), "regenerate from registry truth" meant one
mutable pointer. Under locked-observation, it means observing every tag on a physical
repository, hashing platform-manifest sets into content-addressed observation objects,
and writing a `tags` map where every row is registry-derived. The bot's core logic gets
larger and more security-relevant at the same time — which is why the coverage,
input-validation, and privilege-split decisions below are made explicit now rather than
left implicit in workflow YAML.

Four research artifacts ground this ADR:
[`research_python_bot_stack.md`](./research_python_bot_stack.md),
[`research_python_bot_security.md`](./research_python_bot_security.md),
[`research_python_coverage_gate.md`](./research_python_coverage_gate.md), and
[`research_validate_render_pipeline.md`](./research_validate_render_pipeline.md).
Their conclusions are already partially codified in
[`quality-python.md`](../rules/quality-python.md)'s "CI Bots / Security-Critical
Automation" section; this ADR is the decision record for the parts that section only
summarizes, plus the workflow-level (not code-level) security posture.

## Decision Drivers

- **Registry truth wins, always.** The bot never trusts a dispatch payload for content
  — only as a lookup key. Every written field is re-derived from the physical registry
  or preserved verbatim from the last human-reviewed commit (D4, reaffirmed by G-09).
- **100% branch coverage is a design constraint, not a target bolted on afterward.** A
  security-critical bot with partial coverage is a bot with an unverified attack
  surface. The architecture must make 100% *reachable without mock hell*, not just
  declared in a config file.
- **Zero standing production services**, extended from the original ADR's driver: the
  bot has no server of its own — it runs only inside GitHub-hosted Actions runners,
  triggered by events, holding credentials only for the duration of a job.
- **Minimal dependency footprint in the credential-holding process.** Every runtime
  dependency imported by code that touches a write-scoped token is audit surface for
  that token, not just a normal supply-chain risk.
- **Boring technology.** Reuse `sysexits`-family exit codes, stdlib validation,
  GitHub-native primitives (Environments, auto-merge, required status checks) over
  bespoke merge logic or a second orchestration layer.

## Industry Context & Research

| Precedent | Lesson taken |
|---|---|
| [Trail of Bits' 2024 Homebrew audit](https://blog.trailofbits.com/2024/07/30/our-audit-of-homebrew/) | `pull_request_target`/`workflow_dispatch` shell-injection and self-hosted-runner privilege escalation are the concrete failure modes this ADR defends against — direct precedent for treating `repository_dispatch` payloads with the same suspicion. |
| [Bazel Central Registry's `bcr_validation.py`](https://github.com/bazelbuild/bazel-central-registry/tree/main/tools) | Shared core validation module with two thin CLI entry points (`--check` / `--check_all`) — the structural precedent for `indexbot`'s single console script with `validate`/`announce`/`reconcile` subcommands sharing one core. |
| Go module proxy "announce = doorbell" (already D4) | Reaffirmed: the announce payload can never lie, because nothing it says is trusted — only re-derived registry state is written. |
| [zizmor](https://zizmor.sh/) adoption (500+ projects incl. CPython, curl, PyPI) | Actions-specific static analysis (template injection, cache poisoning, impostor commits) is now the standard blocking gate for workflow YAML, not an optional extra. |
| [step-security/harden-runner](https://github.com/step-security/harden-runner) audit-then-block pattern | Run in `audit` mode for a period before flipping to `block`, so the bot is not broken by an unlisted egress endpoint discovered only in production. |

**Key insight** (from `research_python_bot_stack.md`): functional core / imperative
shell is not an aesthetic preference here — it is the concrete mechanism that makes
100% branch coverage achievable with in-memory fakes instead of mocking every I/O call
at every layer. Every architectural decision in BD-1 follows from that one finding.

## Considered Options

| Option | Rejected in favor of | Reason |
|---|---|---|
| Typed GitHub SDK ([PyGithub](https://github.com/PyGithub/PyGithub) or [githubkit](https://github.com/yanyongyu/githubkit)) | Plain [httpx](https://github.com/encode/httpx) calls in `adapters/github_api.py` | Audit surface. An SDK's own dependency tree and abstraction layer hide the exact HTTP calls a credential-holding process makes. The bot needs a handful of REST/GraphQL calls (contents, PR open/update, labels, `enablePullRequestAutoMerge`) — direct httpx keeps every request inspectable in one adapter module. |
| Importing [`jsonschema`](https://github.com/python-jsonschema/jsonschema) into the bot for schema validation | Stdlib-only hand-rolled structural checks in `core/validate_entry.py` | `jsonschema` pulls in `rpds-py`, a compiled Rust extension, transitively. A compiled dependency inside the credential-holding process is exactly the supply-chain surface `quality-python.md`'s "minimal deps" rule targets. [`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema) (same library, CLI wrapper) stays as a `uv tool run` invocation confined to the unprivileged `schema-validate` job, which holds zero secrets — an acceptable place for a heavier dependency chain because it never holds credentials. |
| [`vcrpy`](https://pypi.org/project/vcrpy/) cassette-based HTTP test doubles | [`respx`](https://github.com/lundberg/respx) route mocks | PAT-leak risk if cassette header-scrubbing is ever forgotten in a commit, and cassettes cannot synthesize the edge cases the suite needs on demand (401→token-refresh, 5xx retry/backoff, malformed JSON, missing digest header) — a real recorded session will not naturally contain them. |
| [`httpx2`](https://github.com/pydantic/httpx2) (Pydantic's 2026 stewardship fork of httpx) | `httpx` (current stable) | Immature: announced 2026, no track record yet for a security-critical dependency. `pytest-httpx2` already tracks `respx`-family mocking for both, so migrating later is a low-cost follow-up, not a reason to hold up this ADR. |

## Decisions

### BD-1 — Bot package: `uv` src layout, one console script, functional core / imperative shell

`bot/` lives at the repo root as a real [uv](https://docs.astral.sh/uv/)-managed
package — never loose `.github/scripts/*.py` files, per `quality-python.md`'s "ship as
a real uv package" rule. Import name `indexbot`. Python floor: **3.12**, pinned in
`bot/.python-version` — a recent, boring stable version. **Correction (verified
empirically post-implementation):** coverage.py's
`sys.monitoring`-based (["sysmon"](https://docs.python.org/3/library/sys.monitoring.html),
[PEP 669](https://peps.python.org/pep-0669/)) backend exists from 3.12, but its
*branch*-coverage measurement — the mode BD-3's gate actually uses (`branch = true`) —
requires Python 3.14+ (coverage.py's own `env.py` gate); on 3.12 it silently falls back
to the classic trace-based core. The 3.12 floor is kept for its own sake (boring,
already-adopted stable version), not because it unlocks a faster branch-coverage
backend today; `bot/pyproject.toml` no longer requests `core = "sysmon"` explicitly
(see BD-3) so no misleading `CoverageWarning` prints. Revisit the floor if the
sys.monitoring branch backend's overhead reduction becomes worth chasing once 3.14
is a reasonable minimum.

One console script, `indexbot`, with subcommands:

```
indexbot announce       # single-package regenerate + PR (repository_dispatch target)
indexbot reconcile      # full-index regenerate + PR/anomaly (nightly cron target)
indexbot validate       # G-02/G-03/G-15-class semantic checks on changed p/*.json
indexbot render         # p/ source → deploy tree (config.json, /data/catalog, wrapper pages)
indexbot seed-import    # CATALOG.md + logo + mirror.yml + live observe → root + CAS objects
indexbot classify-pr    # internal: diff a PR via GitHub API only, label new-package|refresh
indexbot governance-check  # internal: set the governance/review-required status check
```

`indexbot validate` is **not** the JSON Schema layer. Schema shape validation
(`schema/root.schema.json`, `schema/observation-object.schema.json`, `schema/
config.schema.json`) runs via the `check-jsonschema` CLI in the unprivileged
`schema-validate` job (BD-5), never imported into `indexbot`. `indexbot validate` runs
the checks a schema cannot express: path↔name derivation, repository host allowlist
(checked *before* any network call — SSRF ordering), reserved-namespace rejection
(charset/reserved-list contract owned by
[`adr_namespace_policy.md`](./adr_namespace_policy.md) ND-3/ND-4), digest-hex
`fullmatch` before any path join, content-digest self-consistency, dangling-reference
detection, and the D6/G-15 ownership probe (BD-4 covers its exact seam).

Module map (functional core / imperative shell, per `research_python_bot_stack.md` and
`quality-python.md`):

```
bot/
  pyproject.toml            # uv, ruff (incl. S), pyright --strict, coverage config, bandit, mutmut
  .python-version           # 3.12
  src/indexbot/
    exit_codes.py            # BD-2
    errors.py
    model.py                 # frozen dataclasses — RootEntry, TagRow, ObservationObject, …
    ports.py                 # RegistryPort, GitHubPort, FilePort, ClockPort (Protocol)
    core/                    # PURE — no I/O, exhaustively unit-tested with plain values
      observe.py              # registry truth → tags map + observation objects
      regenerate.py           # target-state computation from observations
      diff.py                 # current vs target → Patch | None
      anomaly.py               # G-13-class integrity check (BD-carry-forward)
      desc.py                  # __ocx.desc / sh.ocx.keywords handling
      backoff.py                # bounded retry policy (G-10)
      validate_payload.py       # BD-4: untrusted client_payload checks
      validate_entry.py         # BD-1: schema-adjacent semantic checks
      version_order.py          # ported from ocx/scripts/catalog-generate.py
      render.py                 # build_render_plan — reachability filter, config.json, catalog data
      catalog_md.py              # per-package wrapper Markdown emission
    adapters/                 # THIN — the only place httpx is imported
      ghcr.py                   # RegistryPort impl (bearer-token dance, tags/list, manifests)
      github_api.py             # GitHubPort impl (contents, PR, labels, GraphQL auto-merge)
      local_files.py            # FilePort impl (path-safe joins)
      system_clock.py           # ClockPort impl
    cli/
      _common.py                 # argv/env parsing, GITHUB_OUTPUT writer (incl. multiline form)
      announce.py, reconcile.py, validate.py, render.py, seed_import.py
      classify_pr.py, governance_check.py
  tests/
    fakes/                     # in-memory Protocol implementations
    ...
```

Runtime dependency: **httpx only**, and it is confined to `adapters/` — nothing in
`core/` or `cli/` imports it. This is the concrete enforcement of "the credential
process imports no schema library, no SDK, no cassette library" from Considered
Options: one HTTP library, one place it is allowed to appear, everything else is
stdlib or the bot's own pure functions.

### BD-2 — Exit-code contract (sysexits family)

The bot exposes exactly four outcomes as process exit codes, reusing the two
[sysexits(3)](https://man.freebsd.org/cgi/man.cgi?query=sysexits) numeric slots that
fit semantically, plus the two conventional Unix codes — not the full sysexits
catalog (YAGNI: four outcomes need four codes, not sysexits' full enumeration):

| Code | Meaning | Who acts on it |
|---|---|---|
| `0` | OK — no-op (nothing to regenerate) or applied (diff computed and committed/PR'd) | Workflow reads `result=no-op\|applied` from `$GITHUB_OUTPUT` to decide whether to skip the merge step |
| `1` | Validation failure — semantic check in `core/validate_entry.py` or `core/validate_payload.py` rejected the input | `schema-validate` / `validate` job fails the required status check |
| `65` | Anomaly — integrity violation requiring a human, **never auto-healed** (e.g. an already-observed tag's registry-derived digest changed) | `reconcile`/`announce` job fails, opens or labels an issue; never silently overwrites |
| `75` | Transient — backoff exhausted (GHCR 429/5xx weather, per `core/backoff.py`/G-10) | Workflow may retry later (cron re-runs reconcile nightly regardless; announce is not auto-retried within the same run past the bounded backoff) |

Every subcommand appends `result=<value>` (and, where applicable, `pr_number=` /
`anomaly_count=`) to the file at
[`$GITHUB_OUTPUT`](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions)
on exit `0`; workflows branch on the numeric exit code and the `result` output — never
on parsed log text. Exact call-site mapping (which core function raises which
condition) is Phase 2 (`WP2-B`, `WP2-E`) implementation work; this ADR fixes the
contract the workflows are written against, not the internal wiring.

### BD-3 — 100% coverage gate and required test-suite shapes

```toml
[tool.coverage.run]
branch = true
# No explicit `core` override — sys.monitoring branch coverage needs Python
# 3.14+ (BD-1's correction); requesting core="sysmon" on the 3.12 floor only
# prints a CoverageWarning before falling back to the classic trace core.
source = ["src"]
relative_files = true

[tool.coverage.report]
fail_under = 100
show_missing = true
exclude_also = [
  "if __name__ == .__main__.:",
  "if TYPE_CHECKING:",
]
```

No inline `# pragma: no cover`. The only exclusions are the small, reviewed
`exclude_also` list above — a diff to that list is visible in every PR, which is the
practical control in place of a per-line pragma-linter (none exists for
[coverage.py](https://coverage.readthedocs.io/)). `task verify` and CI invoke the
*identical* command
(`uv run pytest --cov --cov-branch --cov-report=term-missing`, `fail_under` enforced by
config) — no drift between local and CI gates, per `quality-python.md`.

Required test-suite shapes (each maps to a Phase 2 work package):

- **[hypothesis](https://hypothesis.readthedocs.io/) property tests** on
  `core/validate_payload.py`: `from_regex(PATTERN, fullmatch=True)` for acceptance, plus
  a second property seeded with `..`/absolute-path/injection tokens for rejection, plus
  a wall-clock-bounded test proving the length-cap makes worst-case regex work
  non-catastrophic (ReDoS wall-clock cap, `WP2-A`).
- **[respx](https://github.com/lundberg/respx) route mocks** at the `adapters/`
  boundary: token-dance incl. retry-token, paginated `tags/list`, manifest 200/404/
  401/429±`Retry-After`/5xx/malformed-JSON, `__ocx.desc` absent-ok (`WP2-C`); GitHub
  contents/PR/labels/GraphQL auto-merge seam (`WP2-D`).
- **Golden fixtures** for `core/render.py`: normal, orphan-pruned, yanked-excluded,
  shared-digest dedup, no-desc, PNG-only logo, nested-namespace cases (`WP2-F`).
- **Idempotency as a required test**: "run twice, second diff empty" against
  `core/regenerate.py`/`core/diff.py` — rerun-safety is a correctness property, tested
  directly, not assumed (`WP2-B`).
- **[mutmut](https://github.com/boxed/mutmut)** scheduled, non-blocking baseline —
  catches "100% executed, zero assertions" (coverage.py's own author's documented
  limitation) without slowing the PR gate. Promote to blocking only if the
  surviving-mutant count stays actionable in practice.

### BD-4 — Untrusted input handling: length-cap, `fullmatch`, env-var indirection, two-regex separation

> **Amended by [ADR-6](./adr_fork_pr_announce.md) Amendment A1 (2026-07-18):** the `repository_dispatch`
> `client_payload` *mechanism* below is retired with the doorbell (there is no
> dispatch payload under the fork-PR lane). The untrusted-input *hygiene* — length-cap,
> `re.fullmatch`, `..`/absolute-path rejection, env-var indirection over `run:`
> interpolation — carries forward verbatim to fork-PR claim verification. See
> Amendment A1 for the retired module (`core/validate_payload.py`) and the migrated
> discipline.

Any `repository_dispatch` `client_payload` field is:

1. **Length-capped before regex evaluation** — reject on length first, so worst-case
   regex work is bounded regardless of what the payload contains (Python's `re` has no
   built-in [ReDoS timeout](https://discuss.python.org/t/add-an-opt-in-timeout-parameter-to-re-to-mitigate-catastrophic-backtracking/107766)
   as of 2026; the length cap is the only reliable stopgap).
2. **Matched with `re.fullmatch` only** — never `match`/`search`, which would silently
   accept a valid prefix followed by injected garbage.
3. **Rejects `..` and absolute paths** explicitly, in addition to charset matching.
4. **Passed to any shell step via env-var indirection only** — `env:` block, never
   `run:` string interpolation:

   ```yaml
   - name: Validate payload
     env:
       PACKAGE_ID: ${{ github.event.client_payload.package }}
     run: uv run indexbot validate --package-id "$PACKAGE_ID"
   ```

The regex itself is **[`adr_namespace_policy.md`](./adr_namespace_policy.md) ND-3's
contract, not this ADR's** — that ADR fixes the exact two-segment package-id shape
(`^[a-z0-9](?:-?[a-z0-9])*$` namespace, `[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*` package,
≤140 combined characters) and the separate N-segment OCI-repository grammar
(`[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*`, per the
[OCI distribution spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)).
This ADR owns the **code-placement mechanics** that keep the two regexes structurally
separate:

- `core/validate_payload.py` compiles and exposes exactly one constant,
  `PACKAGE_ID_RE` — the 2-segment index-side grammar. It is used only to validate
  `client_payload.package` and derived `p/<ns>/<pkg>.json` paths.
- `core/validate_entry.py` compiles and exposes a distinct constant,
  `OCI_REPOSITORY_RE` — the N-segment registry-side grammar. It is used only to
  validate the entry's `repository` field.
- No function accepts "a repository-ish string" and applies either regex based on a
  runtime guess. Each call site imports the one constant it needs. This is the
  concrete fix for the class of bug ADR-2 documents in adjacent OCI tooling
  ([regclient](https://github.com/regclient/regclient)/
  [regsync](https://github.com/regclient/regclient/tree/main/cmd/regsync)): validating
  a fixed-arity identifier against the general N-segment grammar (or vice versa)
  silently admits or rejects values the field was never meant to accept.

### BD-5 — Privileged/unprivileged workflow split and the governance gate

> **Reaffirmed and extended by [ADR-6](./adr_fork_pr_announce.md) Amendment A1 (2026-07-18):** the split below is
> **load-bearing and unchanged** — it is exactly the defense the fork-PR lane needs. The
> `schema-validate` job additionally runs unprivileged claim verification (re-derive +
> byte-compare on PR head, still zero secrets); the governance-gate job additionally
> enforces owners-membership (G-19) and assigns reviewers from `maintainers.yml` (G-20),
> still never checking out PR head. See Amendment A1.

`validate.yml` is two jobs with deliberately different trust levels:

| Job | Trigger | Secrets | Checks out | Network | Required status check |
|---|---|---|---|---|---|
| `schema-validate` | `pull_request` | **None** | PR head (safe — GitHub strips secrets for this trigger) | Anonymous GHCR reads only (BD-1's `indexbot validate` ownership-probe reads) | `schema-validate` |
| governance-gate | `pull_request_target` | `GITHUB_TOKEN` only (labels/status), no PAT | **Never** PR-head content — base-branch code + GitHub API diff only | GitHub API only | `governance/review-required` |

The governance-gate job runs `indexbot classify-pr` (reads the PR's changed-file list
and diff via the GitHub API, never by checking out the ref) to classify it as
`new-package` (G-04 — added `p/*.json` path), `refresh` (existing entry, no
human-review-required key touched), or `human-review-required` (any of `repository`,
`owners`, `status`, `deprecated_message`, or an existing tag row's `yanked` field
changed — G-05's key set). It applies the corresponding label, then
`indexbot governance-check` sets the `governance/review-required` status: green for
`refresh` PRs once `schema-validate` is also green; red (blocking) for `new-package`
and `human-review-required` until a human approves.

Branch protection on `main` requires both `schema-validate` and
`governance/review-required`. Auto-merge for refresh-class PRs is
[`gh pr merge --auto`](https://cli.github.com/manual/gh_pr_merge) (or the equivalent
[`enablePullRequestAutoMerge` GraphQL mutation](https://docs.github.com/en/graphql/reference/mutations#enablepullrequestautomerge))
composed with branch protection — GitHub merges the PR itself once both checks report
success. No custom merge automation, no polling loop, no second bot watching PR state.

**Recorded risk:** required-status-check re-trigger timing and label races are novel —
GitHub re-evaluates `governance/review-required` on every push to the PR head, and a
label applied by `classify-pr` racing a concurrent `governance-check` run (e.g. two
announces of the same package landing PRs close together) is untested territory.
`WP2-S` needs a dedicated test plan covering: does re-approving after a new push reset
the status; does a human removing `new-package` unblock auto-merge or does the PR need
a fresh classification run. If the mechanism proves flaky in practice, the documented
fallback is plain required-review (drop the custom status check, require a human
approval on every PR) — a strictly less automated but unambiguously correct posture.

### BD-6 — Secrets and GitHub Environments

> **Amended by [ADR-6](./adr_fork_pr_announce.md) Amendment A1 (2026-07-18):** the **Announce PAT (G-17) row is
> retired** — the fork-PR lane holds no publisher-side index credential at all. The
> `index-write` Environment's role shrinks (verify-only reconcile no longer writes;
> announce PRs originate from the publisher's own fork, not an index-side token). The
> default `GITHUB_TOKEN` row stands. See Amendment A1 and ADR-6 FP-7.

| Credential | Scope | Held by | Bound to |
|---|---|---|---|
| `index-write` [GitHub Environment](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) | `contents: write`, `pull-requests: write` on `ocx-sh/index` | `announce.yml`/`reconcile.yml`'s commit-and-open-PR step only | Scope-only — **no required reviewers**. Consistent with G-05's auto-merge intent: human review already happens at the first-claim PR (G-04/ADR-2 ND-5); gating the write step itself a second time would duplicate that review, not add safety. |
| Announce PAT (G-17) | Fine-grained, **namespace-scoped** — one PAT per registered namespace, `contents:read` + `actions:dispatch` on `ocx-sh/index` | The publisher's own repo/org (e.g. `ocx-contrib`), never a single shared org secret | Fires the `repository_dispatch` trigger only; cannot write to the index directly |
| Default `GITHUB_TOKEN` | Read-only at workflow level (`permissions: {}`), elevated per-job | Actions runtime | `governance-gate`'s labels/status; `schema-validate`'s (unused) default read |

The `index-write` Environment holds its own token rather than an elevated
`GITHUB_TOKEN` for a specific, documented reason: GitHub does not trigger new workflow
runs from events created by the default `GITHUB_TOKEN`
([triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/trigger-a-workflow#triggering-a-workflow-from-a-workflow)).
A PR opened by `announce.yml`/`reconcile.yml` must itself trigger `validate.yml`'s
`pull_request` event — using a distinct credential in the Environment avoids the
no-self-trigger restriction that a plain `GITHUB_TOKEN` elevation would hit.

Announce PAT rotation procedure is documented content, not code — lands as an ops page
(`site/src/docs/ops/rotate-announce-pat.md`, `WP2-Q`) rather than automation. GitHub App
migration (removes the long-lived PAT entirely, per the "declining" row in
`research_python_bot_security.md`) is a v2 trigger, not built now.

[harden-runner](https://github.com/step-security/harden-runner) runs in `audit` mode on
the `announce.yml` and `reconcile.yml` jobs specifically — the ones that both fetch
(registry reads) and write (git commit/PR). `schema-validate` and `governance-gate`
already hold no secrets (BD-5) and gain little from egress monitoring. Flipping
`audit` → `block` is a separate later decision (Deferred), made once the allowlist has
accumulated enough real traffic to avoid breaking the bot on an unlisted endpoint.

### BD-7 — Toolchain security gates

| Gate | Trigger | Blocking? |
|---|---|---|
| [ruff](https://docs.astral.sh/ruff/) incl. `S` (bandit-derived) group | Every PR/push to `bot/**` | Blocking |
| [bandit](https://bandit.readthedocs.io/) | Every PR/push to `bot/**` | Blocking (second AST net beyond ruff's `S` subset) |
| [pyright](https://microsoft.github.io/pyright/) `--strict` | Every PR/push to `bot/**` | Blocking |
| [pip-audit](https://github.com/pypa/pip-audit) | Every PR + nightly | Blocking (PR), alert (nightly) |
| [zizmor](https://zizmor.sh/) | Every PR touching `.github/workflows/**` or `.github/actions/**` | Blocking |
| `pytest --cov` (100%, BD-3) | Every PR to `bot/**` | Blocking |

Ruff's `S` group is opt-in (`select = [..., "S"]` in `bot/pyproject.toml`) — it is not
part of any default rule selection. Minimum enforced codes: `S113` (HTTP call without a
timeout), `S310` (URL-open with unchecked scheme), `S603`/`S607` (subprocess call /
partial-path), per `quality-python.md`.

SHA-pinned actions everywhere, no exceptions, with [Renovate](https://docs.renovatebot.com/)
configured to open PRs bumping pinned SHAs (`renovate.json`, `WP1-D`) — the pin is
static, the bump process is automated, matching the existing repo-wide invariant
(`CLAUDE.md` Security Invariants). `permissions:` default-deny at the top of every
workflow, elevated per-job only where BD-5/BD-6 require it.

`research_python_bot_security.md` recommended adding
[semgrep](https://semgrep.dev/) (`p/python` + `p/security-audit` rulesets) as a
blocking gate for dataflow/taint checks neither ruff nor bandit perform. The owner
deferred this: at 42–500 packages the ruff+bandit+zizmor+pip-audit stack already covers
every threat class in scope (injection, SSRF, ReDoS, Actions-specific risk, supply
chain) — a fourth static-analysis tool is scope the "boring technology" driver argues
against until the codebase or threat surface actually grows past what the current stack
catches. Semgrep is not rejected, only not adopted yet (see Deferred).

`render-deploy.yml`'s build-order contract (VitePress build before `indexbot render`'s
dist-emission phase; `emptyOutDir` footgun) is
[`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md)'s decision, not
repeated here — this ADR's SHA-pinning and `permissions:` default-deny requirements
apply to that workflow exactly as they do to `validate.yml`/`announce.yml`/
`reconcile.yml`.

## Governance Contract Carry-Forward (G-01–G-18)

`design_spec_registry_indirection.md` §2f/§10/§11 defined G-01–G-18 against the
pointer-only index (one mutable pointer per package, no observation history). The
locked-observation model (root + tags map + CAS observation objects,
`adr_locked_observation_index_format.md`) changes what several of these contracts
regenerate. One row per contract, disposition under the current model:

| ID | Original contract | Disposition | Notes |
|---|---|---|---|
| G-01 | Schema-shape validation against `entry.schema.json` | **Kept, reinterpreted** | Now validates against `schema/root.schema.json` + `schema/observation-object.schema.json` (three schema files, not one). Executed by `check-jsonschema` in `schema-validate` (BD-5), never imported into `indexbot`. |
| G-02 | `name` equals the path-derived logical name | **Kept** | `p/<ns>/<pkg>.json` → `name` must equal `<ns>/<pkg>`. Executed by `indexbot validate` (`core/validate_entry.py`), hand-rolled, not schema-expressible. |
| G-03 | `repository` host allowlist | **Kept** | Anti-squat/anti-exfil guard, checked before any network call (SSRF ordering, BD-1). |
| G-04 | New entry file → `new-package` label + mandatory human review, never auto-merge | **Kept** | Executed by `classify-pr`/`governance-check` (BD-5). Namespace-fit judgment is ADR-2 ND-5's contract; this ADR only owns the mechanical gate. |
| G-05 | Green refresh → auto-merge eligible; yank/deprecate/transfer/`owners`/pointer change → human review always | **Kept, key set expanded** | Under the tags-map model, "refresh" means new/updated rows matching live registry truth. The human-review-required key set is `repository`, `owners`, `status`, `deprecated_message`, and any mutation of an *existing* tag row's `yanked` field. |
| G-06 | Render: `p/*.json` → `public/p/*.json` identity copy + `config.json` | **Reinterpreted** | No longer an identity copy. `indexbot render` (`core/render.py`) does reachability-filtered CAS copy, new-shape `config.json` emission, `/data/catalog/**` emission, and per-package wrapper-page emission — see `adr_catalog_docs_colocation.md`. Owned by the `indexbot render` subcommand, not a standalone script. |
| G-07 | Deploy idempotent; no-op on an unchanged tree | **Kept** | |
| G-08 | `repository_dispatch` + `client_payload.package`, env-var indirection, regex-validated before use | **Kept, regex reinterpreted** | Package-id regex is now the exact 2-segment form (ADR-2 ND-3), replacing the earlier N-segment-permissive draft in `design_spec_registry_indirection.md` §10 amendment 5. Mechanics: BD-4. **— Retired 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** no `repository_dispatch`/`client_payload` exists under the fork-PR lane; the input hygiene migrates to fork-PR claim verification. |
| G-09 | Field provenance partition: registry-derived vs human-governed fields never cross-contaminate | **Kept, field set updated** | Registry-derived (regenerated every announce/reconcile): the entire `tags` map + observation objects. Human-governed (never regenerated, only human-PR-changed): `name`, `repository`, `owners`, `status`, `deprecated_message`, `created`, `upstream`. `desc` is registry-derived (sourced from the `__ocx.desc` artifact / `sh.ocx.keywords` annotation) but only refreshed at announce/reconcile time from the currently-tagged content, per `adr_locked_observation_index_format.md`. **— Reinterpreted 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** the `tags` map is owner-curated (announced), not regenerated from every observed tag; each row's *content* is still derived/verified from registry truth, but the set's scope is the owner's curated selection (ADR-6 FP-2). |
| G-10 | Bounded backoff retry on manifest fetch before giving up | **Kept** | `core/backoff.py`; exhaustion maps to exit `75` (BD-2). |
| G-11 | Idempotent + cascade-safe convergence; diff routes to G-04/G-05 merge policy | **Kept** | Idempotency is now an explicit required test ("run twice, second diff empty", BD-3), not an implicit property. **— Partially superseded 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** the "publisher never enumerates" property no longer holds — under owner-curated tags the owner chooses the tag set (ADR-6 FP-2). Idempotency/cascade-safety within the curated scope is kept. |
| G-12 | Nightly reconcile regenerates every entry, diffs, opens one PR with all drift | **Kept** | **— Reframed verify-only 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** reconcile no longer regenerates, rewrites, or opens a content PR; it verifies every committed claim against the registry and flags anomalies via issue (ADR-6 FP-3). |
| G-13 | Reconcile-maintained `state/observed-digests.json`; digest change on an already-observed tag = hard-stop anomaly, first sight recorded not flagged | **Eliminated as a separate file** | The committed root **is** the observation ledger under the locked-observation model — every observed tag and its content digest already lives in the `tags` map. The anomaly check reads the committed root directly instead of an auxiliary state file. The exact mutability predicate (which tag classes may legitimately move vs. which digest changes are integrity violations) is `adr_locked_observation_index_format.md`'s contract; this ADR fixes that violations exit `65` and are never auto-healed (BD-2). |
| G-14 | Sibling-repo CI hardening explicit: `permissions:` default-deny + SHA-pinned actions on all workflows | **Kept** | BD-7. |
| G-15 | D6 ownership proof executed: fetch the physical manifest, verify the embedded canonical identifier equals the entry's logical `name` | **Reinterpreted as a pluggable loud-skip seam** | The identifier-embedding convention this depends on is unconfirmed against `ocx-mirror`'s actual publishing behavior. Implemented as a `RegistryPort` probe returning one of three outcomes — `confirmed`, `mismatch` (block-tier), `unconfirmed` (WARN + surfaced on the PR, **never a silent pass**). Resolving the convention is tracked against `ocx-mirror` publishing verification, not this ADR. |
| G-16 | Privileged/unprivileged workflow split | **Kept** | BD-5, in full. |
| G-17 | Announce abuse bounds: namespace-scoped PAT, per-package concurrency groups, schema-validated payload | **Kept** | BD-4 (payload), BD-6 (PAT scoping). `announce.yml` uses `concurrency: announce-<ns>-<pkg>`, `cancel-in-progress: true`. **— Retired 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** no namespace-scoped PAT exists; announce abuse bounds become the fork-PR spam posture — label failed-check PRs + stale-close (ADR-6 FP-8). |
| G-18 | Reconcile disabled/dry-run until the 42-package republish batch is parity-verified (M-1) | **Reinterpreted** | Mechanism changed from workflow-disable to a repo [Actions variable](https://docs.github.com/en/actions/learn-github-actions/variables) `RECONCILE_DRY_RUN`, read by `reconcile.yml` and passed to `indexbot reconcile --dry-run`. Same intent (no mutation before parity verification); flip is `gh variable set RECONCILE_DRY_RUN false`, documented as an ops page (`WP2-Q`), not a workflow-file edit. **— Collapses into always-dry 2026-07-18 → [ADR-6](./adr_fork_pr_announce.md) Amendment A1:** verify-only reconcile has no mutating mode to gate, so `RECONCILE_DRY_RUN` is retired (ADR-6 FP-3). |

## Technical Details

```
repository_dispatch (event_type: "announce", client_payload: {package: "<ns>/<pkg>"})
  │  from ocx-contrib CI, PAT scoped to the "announce" trigger only (G-17)
  ▼
announce.yml
  ├─ job: validate-payload        (BD-4 — env-var indirection, no secrets)
  └─ job: regen-and-pr            (index-write Environment, harden-runner audit-mode)
       indexbot announce --package-id "$PACKAGE_ID"
         core/observe → core/regenerate → core/diff → (no-op | commit+PR)
         exit 0 (no-op/applied) | 65 (anomaly) | 75 (backoff exhausted)
  ▼ (PR opened, triggers pull_request on validate.yml — needs the Environment's own token, BD-6)
validate.yml
  ├─ job: schema-validate         (pull_request, zero secrets, PR-head checkout OK)
  │    check-jsonschema against schema/*.json (never indexbot-imported)
  │    indexbot validate          (G-02/G-03/G-15-class semantic checks)
  └─ job: governance-gate         (pull_request_target, GITHUB_TOKEN only, never checks out PR head)
       indexbot classify-pr  → label (new-package | refresh | human-review-required)
       indexbot governance-check → sets "governance/review-required" status
  ▼
branch protection: schema-validate + governance/review-required both required
  refresh, both green            → gh pr merge --auto
  new-package / human-review-required → blocked until human approval

reconcile.yml (nightly cron + workflow_dispatch)
  indexbot reconcile [--dry-run via vars.RECONCILE_DRY_RUN, G-18]
    regenerates every entry from registry truth, diffs against committed root
    clean-subset PR (routine drift) + anomaly issue + exit 65 (integrity violations)
```

## Risks

1. **Governance-gate status-check mechanics are novel** (BD-5) — re-trigger timing on
   push, label races between concurrent classification runs. Dedicated test plan
   required in `WP2-S`; fallback is plain required-review if the mechanism proves
   flaky in practice.
2. **G-15's identifier-embedding convention is unconfirmed** against `ocx-mirror`'s
   actual publishing behavior. The pluggable loud-skip seam prevents a silent false
   pass, but the seam itself needs verification once `ocx-mirror` publishing is
   observable — tracked as an out-of-scope coupling (see Deferred).
3. **Announce volume flooding the PR queue** is not a risk at 42–400 packages (D5's
   scale envelope), but the direct-commit upgrade path (crates.io's own lesson, once
   its sparse index also outgrew PR-per-change) is worth recording now so it is not
   re-researched later — see Deferred.
4. **GHCR weather** (429/5xx, regional CDN degradation) is handled by bounded backoff
   (G-10) and the transient exit code (BD-2); reconcile's nightly cadence self-heals
   any announce that failed to converge.

## Deferred / Out of Scope

- **Direct-commit upgrade path** for announce-class PRs, if PR volume ever floods at a
  much larger package count (crates.io's own scaling lesson). Not needed at 42–400
  packages; recorded here so the option is not lost.
- **[semgrep](https://semgrep.dev/) `p/python` + `p/security-audit`** as a blocking
  dataflow/taint gate — research-recommended, owner-deferred (BD-7) until the bot's
  scope or threat surface grows past what ruff+bandit+zizmor+pip-audit already catch.
- **harden-runner `block` mode** — starts in `audit` (BD-6); flips to `block` only
  once the egress allowlist has accumulated enough real announce/reconcile traffic to
  avoid a false-positive outage.
- **GitHub App migration** for the announce credential, removing the long-lived
  namespace-scoped PAT (G-17) entirely in favor of OIDC-style short-lived tokens —
  v2 trigger per the original ADR's D4 transport ladder, not built now.

## Validation

- [ ] `task verify` runs the identical `pytest --cov --cov-branch --cov-report=
      term-missing` command CI runs (BD-3) — no drift.
- [ ] `ruff check` (incl. `S`), `bandit`, `pyright --strict`, `pip-audit` all green on
      `bot/**` (BD-7).
- [ ] `zizmor` clean on every workflow in `.github/workflows/**` (BD-7).
- [ ] `mutmut` baseline recorded, non-blocking (BD-3).
- [ ] Governance-gate status-check race test plan executed and its outcome recorded
      (Risk 1) before Phase 3's E2E gate.
- [ ] `RECONCILE_DRY_RUN` flips to `false` only after M-1 parity verification (G-18).

## Links

- [`plan_index_v1.md`](../state/plans/plan_index_v1.md) — canonical phase/work-package
  decomposition (Phase 0 origin; Phase 1 WP1-B/C/D/E; Phase 2 WP2-A..M, WP2-S/T/U;
  Phase 3 WP3-A gate)
- [`adr_public_index_registry_indirection.md`](./adr_public_index_registry_indirection.md) —
  D4 (announce protocol), D5 (bot merge policy), amended above
- [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md) —
  the wire/observation format `indexbot`'s core computes against
- [`adr_namespace_policy.md`](./adr_namespace_policy.md) — ND-3 (the two regexes this
  ADR places in code), ND-4 (reserved segments), G-04/G-05/G-15 cross-references
- [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md) — `render-deploy.yml`
  build-order contract this ADR's SHA-pinning/`permissions:` requirements apply to
- [`design_spec_registry_indirection.md`](./design_spec_registry_indirection.md) §2f,
  §10, §11 — the original G-01–G-18 text this ADR carries forward
- [`decision_log_2026-07-16.md`](./decision_log_2026-07-16.md) — narrative of the
  discussion this ADR formalizes (§10 "Bot + CI posture")
- [`quality-python.md`](../rules/quality-python.md) "CI Bots / Security-Critical
  Automation" — the code-level rules this ADR's decisions feed
- `research_python_bot_stack.md`, `research_python_bot_security.md`,
  `research_python_coverage_gate.md`, `research_validate_render_pipeline.md` — source
  research
- [`adr_fork_pr_announce.md`](./adr_fork_pr_announce.md) — ADR-6, the fork-PR announce
  lane that amends BD-4/BD-5/BD-6 and the G-table below (Amendment A1)

---

## Amendment A1 — Fork-PR announce lane (2026-07-18)

[`adr_fork_pr_announce.md`](./adr_fork_pr_announce.md) (ADR-6) replaces the
`repository_dispatch` announce doorbell with an ordinary **fork pull request**: no
publisher holds a credential on `ocx-sh/index`; the PR carries the claimed root + CAS
objects; unprivileged CI re-derives every claimed tag from registry truth and
byte-compares; `owners[].github_id` membership decides auto-merge vs. human review.
This amendment records the effect on this ADR's decisions and governance table. Per
immutable-ADR discipline the original text above is unchanged — the markers on BD-4/5/6
and on the G-table rows point here; this section carries the current disposition.

**Blanket provenance note.** Wherever the decisions and carry-forward table above say
"every observed tag" or describe the `tags` map as "regenerated from registry truth,"
read **"every announced tag" (owner-curated)** post-ADR-6: the owner curates the tag
set, and CI verifies each claimed row against the registry rather than the bot
enumerating the registry to populate it (ADR-6 FP-2). Each row's *content* is still
derived/verified from registry truth; only set *membership* is owner-decided.

### BD-decision dispositions

- **BD-4 — Untrusted input handling.** The `repository_dispatch` `client_payload`
  *mechanism* is retired (there is no dispatch payload). The *hygiene* — length-cap,
  `re.fullmatch`, `..`/absolute-path rejection, env-var indirection over `run:`
  interpolation — carries forward to fork-PR claim verification (`core/verify_claims`;
  `LocalFiles` path-safe joins for PR-added files). `core/validate_payload.py` and its
  `PACKAGE_ID`-env caller are removed (ADR-6 FP-1/FP-9; Phases 2–3).
- **BD-5 — Privileged/unprivileged split.** **Reaffirmed, load-bearing, unchanged in
  shape** — it is precisely the defense the fork-PR lane needs (ADR-6 FP-7). The
  unprivileged `schema-validate` job additionally runs claim verification on PR head
  (re-derive + byte-compare, still zero secrets, anonymous GHCR reads). The privileged
  `governance-gate` job (`pull_request_target`, never checks out PR head) additionally
  enforces the owners-membership gate (G-19) and assigns reviewers from `maintainers.yml`
  (G-20). Auto-merge stays `gh pr merge --auto --squash` composed with branch
  protection; the only new condition on going green is G-19.
- **BD-6 — Secrets and Environments.** The **Announce PAT row (G-17) is retired** — no
  publisher-side index credential exists. The `index-write` Environment's role shrinks:
  verify-only reconcile (G-12) no longer writes, and announce PRs originate from the
  publisher's own fork rather than an index-side token, so the no-self-trigger rationale
  for a distinct Environment token no longer applies to the announce path. The default
  ambient `GITHUB_TOKEN` row stands — it is the only credential in the announce path, held
  by the privileged job that never touches PR-head content (ADR-6 FP-7). Exact per-job
  token wiring is Phase 3.

### Governance-table delta

Overrides the corresponding rows in *Governance Contract Carry-Forward* above, and adds
G-19/G-20 (the series extends beyond G-18):

| ID | Post-ADR-6 disposition | Notes |
|---|---|---|
| G-08 | **Retired** | No `repository_dispatch`/`client_payload`. Announce is a fork PR (ADR-6 FP-1); untrusted-input hygiene migrates to claim verification (BD-4 above). |
| G-09 | **Reinterpreted** | `tags` is owner-curated (announced), not regenerated from every observed tag. Each row's *content* is still derived/verified from registry truth; scope narrows to the curated set (ADR-6 FP-2). |
| G-11 | **Partially superseded** | "Publisher never enumerates" no longer holds — the owner curates the tag set (ADR-6 FP-2). Idempotency/cascade-safety within the curated scope is kept. |
| G-12 | **Reframed verify-only** | Nightly reconcile never adds/removes/rewrites a tag, never opens a content PR. It verifies every committed claim against the registry and flags anomalies via issue (exit `65`, BD-2). Yanked rows are exempt from the registry-existence check (grace, ADR-6 FP-2/FP-3). |
| G-17 | **Retired** | No namespace-scoped PAT. Announce abuse bounds become the fork-PR spam posture — label failed-check PRs + stale-close, no CAPTCHA/allowlist in v1 (ADR-6 FP-8). |
| G-18 | **Collapses into always-dry** | Verify-only reconcile has no mutating mode to gate; `RECONCILE_DRY_RUN` is retired (ADR-6 FP-3). |
| **G-19** (new) | **Owners-membership gate for the machine lane** | A fork PR qualifies for auto-merge only if its author's `github_id` is in the target root's committed `owners[]`. Evaluated by the privileged governance job from PR metadata + base-branch root — never PR-head content (ADR-6 FP-5). |
| **G-20** (new) | **Maintainers-YAML reviewer assignment** | Human-lane PRs get reviewers assigned from a committed `maintainers.yml` (repo root or `.github/`; list of `{github, github_id}`) by the privileged governance job, plus an idempotent bot review-request comment (ADR-6 FP-6). |

G-04 (new package = human review), G-05 (human-review key set), G-13 (committed root is
the ledger), G-15 (ownership probe) and G-16 (the split itself) are **unchanged** — G-04
is the "new package = human lane by design" rule the fork-PR lane relies on, and G-05's
key set is the human-lane trigger.

**Additive correction to G-05's enumeration (not a scope change).** The G-05 row above
enumerates the human-review key set as `repository`, `owners`, `status`,
`deprecated_message`, and an existing tag row's `yanked` value — it omits
**`superseded_by`**, which pre-dates this branch. The authoritative, complete set is
`repository`, `owners`, `status`, `deprecated_message`, **`superseded_by`**, and a
`yanked`-value change, as implemented by `core/diff.classify_change` and documented in
`site/src/docs/reference/governance-contracts.md` and `.../entry-schema.md`. This note
records the omission additively; the decided G-05 row is left verbatim per immutable-ADR
discipline. ADR-6 FP-5 uses the corrected set.

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Michael + Claude design swarm | Initial record from the 2026-07-16 design discussion |
| 2026-07-17 | Phase 1 review-fix | BD-1/BD-3 corrected: sys.monitoring branch-coverage support needs Python 3.14+, not 3.12 — verified empirically (coverage 7.15.2 `CoverageWarning: Can't use core=sysmon`). Dropped the now-inert `core = "sysmon"` / `COVERAGE_CORE` settings from `bot/pyproject.toml`, `bot/taskfile.yml`, `ci.yml`; 3.12 floor kept for its own sake, not as a sysmon prerequisite. |
| 2026-07-18 | Michael + Claude design swarm | Amendment A1 (fork-PR announce lane, ADR-6): BD-4 mechanism retired/hygiene carried forward, BD-5 reaffirmed + extended (G-19/G-20), BD-6 Announce-PAT retired; G-table delta — G-08/G-17 retired, G-11 partially superseded, G-12 reframed verify-only, G-18 collapses to always-dry, G-09 reinterpreted, G-19 (owners-membership auto-merge) + G-20 (maintainers-YAML reviewer assignment) added. Original rows preserved; markers point to Amendment A1. |
