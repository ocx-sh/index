"""Static-assertion workflow-security suite (spec X7, register §5).

Covers G-14 (`permissions:` default-deny + SHA-pinned `uses:` across every
workflow), G-16/FP-7 (no `pull_request_target` job ever checks out PR head),
the `contents: write` split that lets `governance.yml` arm auto-merge at all,
and the trigger split that keeps a `pull_request_target` run from ever
emitting a check run named after a branch-protection-required context. The
repo has no runtime YAML dependency and the credential process must gain
none, so these tests hand-parse the specific keys (`permissions:`, `uses:`,
`ref:`, `on:`, `run:`) with the stdlib only — a line scan, never a YAML
library import.

## What moved into `ocx-indexbot`, and where it is now

0.2.0 made every generated CI job exactly one `indexbot` command, so the
shell these tests used to assert on no longer exists in this repository.
Nothing was dropped — each control moved to a named test in
`ocx-sh/indexbot`, and the pointers are here so the next reader does not
conclude a control vanished:

* **`test_workflow_pathspec.py` — DELETED.** It replayed `validate.yml`'s
  changed-files pathspec against real `git`. That diff is now
  `adapters/local_git.LocalGit.changed_package_roots`, and all four of its
  properties are replayed against real `git` in
  `tests/adapters/test_local_git.py`: `:(glob)` so `*` stops at `/` and no
  CAS object is selected (`::test_changed_package_roots_skips_cas_objects`,
  ocx-sh/index#57); three dots, never two
  (`::test_changed_package_roots_ignores_base_branch_movement`, PRs
  #351/#423/#538); `--diff-filter=d` keeping a symlink type-change
  (`::test_changed_package_roots_excludes_deletes_but_keeps_type_changes`);
  and the pattern following the deployment's declared depth rather than a
  hardcoded two (`::test_changed_package_roots_honours_the_declared_segment_count`,
  with `tests/cli/test_validate_pr.py::test_the_root_glob_comes_from_the_declared_segment_count`
  proving the CLI derives it from policy). The deployment half of that last
  one — that THIS index declares two segments — stays here, in
  `test_deployment_policy.py::test_this_index_declares_the_ocx_identity_it_publishes_under`.
* **Base-ref materialization** (`$RUNNER_TEMP/indexbot-base`, `git cat-file
  -e` before `git show`) is `cli/validate_pr._materialize_base` over
  `cli/_wiring._run_validate_pr`'s `mkdtemp`, pinned by
  `tests/cli/test_wiring.py::test_validate_pr_is_wired_to_local_git_and_an_out_of_tree_base_port`
  and `tests/cli/test_validate_pr.py::test_base_ref_bytes_land_in_the_base_tree_not_the_workspace`.
* **The `SAME_REPO_PR` provenance comparison** is `cli/validate_pr._same_repo_pr`
  — see `test_reserved_namespace_flag_is_gated_on_a_same_repo_pull_request`
  below for the per-test citations.
* **The `gh pr merge` arm/withdraw shell** is `adapters/github_api.py` — see
  the two `arm-auto-merge` tests below for the per-test citations.

What stays here is what only this deployment can assert: which job holds
which token, what each job checks out, which command each job runs with which
flags, and the absence of the overrides that would disarm a gate from the
pipeline side.
"""

from __future__ import annotations

import re
from pathlib import Path

from ocx_indexbot.ci.render import parse_header_version

_REPO_ROOT = Path(__file__).resolve().parents[3]
_WORKFLOWS_DIR = _REPO_ROOT / ".github" / "workflows"
_VALIDATE = _WORKFLOWS_DIR / "validate.yml"
_GOVERNANCE = _WORKFLOWS_DIR / "governance.yml"

_PERMISSIONS_DEFAULT_DENY_RE = re.compile(r"(?m)^permissions:\s*\{\}\s*$")
_USES_RE = re.compile(r"^\s*(?:-\s+)?uses:\s*(\S+)")
_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
_TRIGGER_RE = re.compile(r"^  ([a-z_]+):")
# Cron work here is repository-specific (deploy, reconcile, PR triage, mutation
# baseline); a fork running any of it is waste at best and noise at worst.
_UPSTREAM_GUARD = "github.repository_owner == 'ocx-sh'"


def _workflow_files() -> list[Path]:
    return sorted(_WORKFLOWS_DIR.glob("*.yml"))


def _triggers(text: str) -> set[str]:
    """The event names in a workflow's `on:` block — the two-space mapping
    keys between `on:` and the next top-level key. Comment lines (the zizmor
    suppressions live in there) are indented but never match `^  <name>:`
    because they start with `#`."""
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if line.rstrip() == "on:")
    events: set[str] = set()
    for line in lines[start + 1 :]:
        if re.match(r"^\S", line):
            break
        if match := _TRIGGER_RE.match(line):
            events.add(match.group(1))
    return events


def _uses_refs(text: str) -> list[str]:
    return [match.group(1) for line in text.splitlines() if (match := _USES_RE.match(line))]


def _grant(job_text: str, permission: str) -> bool:
    """A real `permissions:` grant, not prose. Every assertion here scans raw
    job text, comments included, so a positive `in` check is satisfiable by a
    comment that merely *names* the grant — mutation-proved: deleting the real
    `contents: write` line left an earlier revision of this suite green,
    because the job's own comment explains it. Anchor on the six-space
    mapping key instead."""
    return re.search(rf"(?m)^\s{{6}}{re.escape(permission)}\s*(?:#.*)?$", job_text) is not None


def _runs(job_text: str, pattern: str) -> bool:
    """A `gh` command a `run:` block actually executes, not prose that quotes
    it — same mutation hazard as `_grant`. The lookahead excludes comment
    lines; the command may be bare or inside a `$(...)` capture."""
    return re.search(rf"(?m)^(?!\s*#).*\bgh {pattern}", job_text) is not None


def _run_lines(job_text: str) -> list[str]:
    """Every line of shell a job executes — the `run:` scalar itself plus, for
    a `run: |` block, every line indented past the `run:` key. Comments in the
    surrounding YAML are excluded by construction, which is what makes an
    `assert "${{" not in ...` over these lines mean something: the file's own
    prose quotes the expressions it is warning about."""
    lines = job_text.splitlines()
    collected: list[str] = []
    index = 0
    while index < len(lines):
        match = re.match(r"^(\s*)(?:-\s+)?run:(.*)$", lines[index])
        index += 1
        if match is None:
            continue
        indent = len(match.group(1))
        collected.append(match.group(2))
        while index < len(lines):
            body = lines[index]
            if body.strip() and len(body) - len(body.lstrip()) <= indent:
                break
            collected.append(body)
            index += 1
    return collected


def _job_names(text: str) -> list[str]:
    """Every job name — the two-space mapping keys after `jobs:`, which is the
    last top-level key in every workflow here (same assumption `_job_block`
    already makes about where a job block ends)."""
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if line.rstrip() == "jobs:")
    return [
        match.group(1)
        for line in lines[start + 1 :]
        if (match := re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line))
    ]


def _job_block(text: str, job: str) -> str:
    """One job's YAML text — from its `  <job>:` header (exactly two-space
    indent) to the next two-space job header or EOF."""
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if line.rstrip() == f"  {job}:")
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if re.match(r"^  \S", lines[index]):
            end = index
            break
    return "\n".join(lines[start:end])


# --- G-14 ------------------------------------------------------------------


def test_every_workflow_has_top_level_permissions_default_deny() -> None:
    """G-14: every `.github/workflows/*.yml` declares top-level
    `permissions: {}` (default-deny; jobs elevate per-job)."""
    workflows = _workflow_files()
    assert workflows, "expected at least one workflow to audit"
    for workflow in workflows:
        text = workflow.read_text(encoding="utf-8")
        assert _PERMISSIONS_DEFAULT_DENY_RE.search(text), (
            f"{workflow.name}: no top-level permissions: {{}}"
        )


def test_every_workflow_uses_is_sha_pinned() -> None:
    """G-14: every marketplace `uses:` across every workflow is pinned to a
    40-hex commit SHA. Local `./` composite actions and `docker://` refs are
    exempt — neither is a pinnable marketplace ref."""
    for workflow in _workflow_files():
        for ref in _uses_refs(workflow.read_text(encoding="utf-8")):
            if ref.startswith(("./", "docker://")):
                continue
            _, _, pin = ref.partition("@")
            assert _SHA_RE.fullmatch(pin), f"{workflow.name}: {ref!r} is not a 40-hex SHA pin"


# --- trigger split (skipped-check-run collision) ---------------------------


def test_no_workflow_declares_both_pr_triggers() -> None:
    """`pull_request` and `pull_request_target` both fire on the SAME PR head
    commit, so a workflow carrying both must discriminate them with a
    job-level `if: github.event_name == ...` — and a job skipped by such an
    `if:` STILL emits a check run, conclusion `skipped`, under its own name.
    GitHub counts a `skipped` conclusion as satisfying a required status check
    and resolves duplicate-named contexts to the most recent one, so the
    privileged run publishes a green-equivalent impostor of whatever required
    context the unprivileged half owns (live-observed on PR #70's head
    1d7a9b4e: two `schema-validate-pr` check runs, one `skipped`, one
    `success`). Keep the two triggers in separate files."""
    for workflow in _workflow_files():
        events = _triggers(workflow.read_text(encoding="utf-8"))
        assert not {"pull_request", "pull_request_target"} <= events, (
            f"{workflow.name}: declares both PR triggers - a trigger-discriminating"
            " job `if:` emits skipped check runs under the other half's context name"
        )


def test_required_pr_diff_context_lives_in_a_pull_request_only_workflow() -> None:
    """`schema-validate-pr` is on `main`'s required-context list and is the
    sole enforcement point for ND-4's reserved-brand gate. It must live in a
    workflow whose only trigger is `pull_request`, and no other workflow may
    define a job by that name."""
    assert _triggers(_VALIDATE.read_text(encoding="utf-8")) == {"pull_request"}
    others = [w for w in _workflow_files() if w != _VALIDATE]
    for workflow in others:
        assert "\n  schema-validate-pr:" not in workflow.read_text(encoding="utf-8")


def test_no_job_if_discriminates_on_the_event_name_in_the_pr_workflows() -> None:
    """The structural half of the fix: with one trigger per file there is
    nothing for a `github.event_name` guard to decide, and reintroducing one
    is how the skipped-check-run collision comes back. Matched on `if:` lines
    only — the file headers narrate the hazard and name the expression."""
    for workflow in (_VALIDATE, _GOVERNANCE):
        text = workflow.read_text(encoding="utf-8")
        assert not re.search(r"(?m)^\s+if:.*github\.event_name", text), (
            f"{workflow.name}: a job `if:` discriminates on github.event_name"
        )


# --- G-16 / FP-7 -----------------------------------------------------------


def test_pull_request_target_governance_job_never_checks_out_pr_head() -> None:
    """G-16/FP-7: `governance.yml`'s privileged `governance-gate` job runs
    under `pull_request_target`, checks out the base ref only (no `ref:` key),
    never resolves `github.event.pull_request.head`, and holds no PAT secret —
    the untrusted PR-head content never runs in the credentialed job."""
    text = _GOVERNANCE.read_text(encoding="utf-8")
    assert _triggers(text) == {"pull_request_target"}
    privileged = _job_block(text, "governance-gate")
    assert "actions/checkout@" in privileged
    # No `ref:` key — a checkout with no ref defaults to the base branch tip,
    # never PR head (the only way to check out head is an explicit `ref:`
    # resolving `pull_request.head`).
    assert not re.search(r"(?m)^\s*ref:\s", privileged)
    assert "secrets." not in privileged


def test_unprivileged_pr_head_job_holds_no_secrets() -> None:
    """G-16/FP-7 counterpart: `validate.yml`'s `schema-validate-pr` job — the
    one that checks out PR head — runs on the unprivileged `pull_request`
    trigger and references no secrets (GitHub strips them for fork PRs)."""
    text = _VALIDATE.read_text(encoding="utf-8")
    assert _triggers(text) == {"pull_request"}
    unprivileged = _job_block(text, "schema-validate-pr")
    assert "github.event.pull_request.head.sha" in unprivileged
    assert "secrets." not in unprivileged


# --- contents: write split -------------------------------------------------


def test_governance_gate_never_holds_contents_write() -> None:
    """`governance-gate` checks out the base ref, runs the pinned
    `ocx-indexbot`, and forwards `github.token` to a third-party action via
    `setup-bot`. It therefore holds `contents: read` and must never be
    "simplified" into holding the write token that arming auto-merge needs."""
    text = _GOVERNANCE.read_text(encoding="utf-8")
    privileged = _job_block(text, "governance-gate")
    assert _grant(privileged, "contents: read")
    assert not _grant(privileged, "contents: write")


def test_arm_auto_merge_checks_out_the_base_and_persists_no_credential() -> None:
    """`arm-auto-merge` is the only job holding `contents: write` — arming and
    withdrawing auto-merge are deferred writes to the base branch.

    **This test used to assert something strictly stronger, and it was given
    up on purpose.** The rule was absolute: this job ran no `uses:` step of
    any kind — no checkout, no `setup-bot` — so the token that can move the
    base branch lived in a job that executed no code at all, and there was
    nothing there for a supply-chain compromise to inhabit. That held while
    arming was a `gh pr merge` one-liner. It stopped being expressible the
    moment arming became `indexbot governance-gate --arm-only`, because
    running the bot needs a checkout and a setup step and both are `uses:`.
    What was genuinely surrendered: a job that can merge a pull request now
    executes base-authored repository code and this package's whole
    hash-locked dependency tree.

    What replaces it are the two properties the surrender did not touch, and
    both must hold precisely:

    (a) **The checkout is the BASE ref.** `pull_request_target`'s default
        checkout ref is the base branch tip, and the only way to reach PR head
        is an explicit `ref:` resolving `github.event.pull_request.head` — so
        the assertion is the absence of `ref:` anywhere in this FILE, not the
        absence of one spelling of it in this job. PR-author-controlled code
        must never run in a credentialed job (FP-7, G-16).
    (b) **The checkout persists no credential.** The default
        `persist-credentials: true` writes the token into `.git/config`,
        where every later step inherits it through plain `git` — dependency
        resolution included — with no `GITHUB_TOKEN` in sight to audit. This
        job is the one place in the tree where that default would be a WRITE
        token.

    The merge mechanics this test used to pin are now `adapters/github_api.py`
    in `ocx-sh/indexbot`: the arm bound to the gated revision
    (`tests/test_github_api.py::test_the_auto_merge_arm_names_the_gated_revision`,
    `::test_a_moved_head_does_not_fail_the_auto_merge_arm`), the
    already-mergeable CLEAN/UNSTABLE fallback squash still pinned to that head
    — `gh pr merge --match-head-commit`'s REST spelling —
    (`::test_an_already_mergeable_pull_request_is_squash_merged_instead`,
    `::test_the_fallback_merge_is_pinned_to_the_gated_revision`), and the
    absence of any branch-protection bypass, which the old `--admin` ban
    stood for (`::test_the_fallback_merge_still_raises_when_the_pull_request_is_not_mergeable`).
    """
    text = _GOVERNANCE.read_text(encoding="utf-8")
    arm = _job_block(text, "arm-auto-merge")
    assert _grant(arm, "contents: write")
    assert "actions/checkout@" in arm, (
        "arm-auto-merge no longer checks out - re-read (a) above before deleting (b)"
    )
    # (a) File-scoped, not job-scoped: a `ref:` in ANY job of a
    # `pull_request_target` workflow is the hazard (WF-05).
    assert not re.search(r"(?m)^\s*ref:\s", text), (
        "governance.yml sets `ref:` - a pull_request_target job may check out PR head"
    )
    # (b) The `contents: write` job must not leave its token in `.git/config`.
    assert re.search(r"(?m)^\s+persist-credentials: false\s*$", arm), (
        "arm-auto-merge's checkout persists a contents: write token into .git/config"
    )
    assert "secrets." not in arm


def test_arm_auto_merge_withdrawal_is_fail_closed() -> None:
    """The withdrawal must survive a governance-gate that ERRORS, and it must
    replay the gate's OWN disposition.

    This is the entire reason the two-job split still exists. It is no longer
    permission scoping — both jobs run the same pinned code, so a bot that
    could lie about `disposition` could arm on its own lie either way. It is
    that a gate which errors (a forge 5xx, a malformed base-ref root, a `uv`
    resolution failure) publishes an EMPTY `disposition`, which `--arm-only`
    can only ever read as "not success", i.e. a withdraw. A single job that
    dies mid-gate leaves an earlier arming standing on a stale evaluation; two
    jobs cannot. So this job must not inherit the default `success()` its
    `needs:` implies.

    `--disposition` must come from `needs.governance-gate.outputs.disposition`
    — governance-check's G-19 ownership-checked result — and never from the
    raw classify-pr label, which cannot see whether the PR author owns every
    touched root. `--head-sha` is the arm's optimistic-concurrency guard: an
    author push between the gate and the arm must not arm a revision nothing
    gated. Both reach the command through env vars, never `run:`
    interpolation (ADR-4 BD-4). And `governance-gate` itself must carry
    `--no-arm`: stopping short of the auto-merge write is what keeps that job
    at `contents: read`.

    The shell this used to pin — `gh pr view --json autoMergeRequest` read
    BEFORE `gh pr merge --disable-auto`, and unguarded by `||` so that "was
    never armed" could not be conflated with "the disable call was denied" —
    is now `adapters/github_api.GitHubAPI.withdraw_auto_merge` in
    `ocx-sh/indexbot`, covered by
    `tests/test_github_api.py::test_withdraw_auto_merge_is_a_noop_when_not_armed`
    (the read-first no-op) and
    `::test_withdraw_auto_merge_graphql_error_payload_raises` (a denied
    disable raises rather than passing silently). The empty-disposition branch
    itself is
    `tests/cli/test_governance_gate.py::test_arm_only_withdraws_on_an_empty_disposition`.
    """
    text = _GOVERNANCE.read_text(encoding="utf-8")
    arm = _job_block(text, "arm-auto-merge")
    assert re.search(r"(?m)^\s+if:.*!cancelled\(\)", arm), (
        "arm-auto-merge inherits needs: success() - an erroring gate skips the withdrawal"
    )
    assert "needs: governance-gate" in arm
    assert "DISPOSITION: ${{ needs.governance-gate.outputs.disposition }}" in arm
    assert "HEAD_SHA: ${{ github.event.pull_request.head.sha }}" in arm
    arm_run = "\n".join(_run_lines(arm))
    assert re.search(r"\bindexbot governance-gate\b.*--arm-only", arm_run)
    assert '--disposition "$DISPOSITION"' in arm_run
    assert '--head-sha "$HEAD_SHA"' in arm_run
    # `--no-arm` is what keeps the classifying job at `contents: read`.
    assert "--no-arm" in "\n".join(_run_lines(_job_block(text, "governance-gate")))
    # Serialized per PR: an arm job from an older head must never execute
    # after the withdrawal triggered by a newer one.
    assert re.search(r"(?m)^\s+group: arm-auto-merge-", arm)


# --- #67: the machine lane's deploy trigger --------------------------------


def test_deploy_on_merge_dispatches_render_deploy_without_any_write_token() -> None:
    """#67: an armed merge is performed with GITHUB_TOKEN, whose push starts
    no workflow run, so `render-deploy`'s `push` trigger never fires for the
    machine lane. `deploy-on-merge` outlives the merge and fires
    `workflow_dispatch` — a documented exception to that recursion guard —
    instead. It must stay the weakest job in the file: `actions: write` to
    press the button and `pull-requests: read` to see the merge, never
    `contents: write` (it must not be able to merge anything itself), and no
    `uses:`/secret at all — the posture `arm-auto-merge` had to give up when
    arming became an `indexbot` command, and that this job keeps because it
    still runs nothing but `gh`.

    The workflow name is matched quote-agnostically: `indexbot ci` renders it
    quoted today, and pinning the quoting would fail this control on a purely
    cosmetic re-render."""
    text = _GOVERNANCE.read_text(encoding="utf-8")
    job = _job_block(text, "deploy-on-merge")
    assert _grant(job, "actions: write")
    assert not _grant(job, "contents: write")
    assert not _uses_refs(job)
    assert "secrets." not in job
    assert _runs(job, r"workflow run \"?render-deploy\.yml\"? .*--ref main")
    # Only ever for a PR the ownership-checked gate cleared for the machine
    # lane — a human-lane PR merges under a human identity, which fires
    # `push` on its own.
    assert re.search(r"(?m)^\s+if:.*disposition == 'success'", job)


def test_deploy_on_merge_never_shares_arm_auto_merges_concurrency_group() -> None:
    """This job waits minutes; `arm-auto-merge` must not queue behind it. A
    shared group would park a withdrawal for a newly non-machine-lane head
    behind a poll for the previous one — the exact stale-arm window
    `arm-auto-merge`'s own serialization exists to close. Its own group, and
    `cancel-in-progress` so a `synchronize` supersedes the poll rather than
    stacking a second one."""
    job = _job_block(_GOVERNANCE.read_text(encoding="utf-8"), "deploy-on-merge")
    assert re.search(r"(?m)^\s+group: deploy-on-merge-", job)
    assert re.search(r"(?m)^\s+cancel-in-progress: true", job)


def test_deploy_poll_survives_a_transient_api_failure() -> None:
    """Fail-OPEN, the deliberate opposite of `arm-auto-merge`'s unguarded
    reads. `arm-auto-merge` runs BEFORE the merge and must go red rather than
    leave a stale arm standing; `deploy-on-merge` runs after, so an unguarded
    `gh` call under `set -e` turns a single 502 or secondary rate-limit — in
    up to 100 polls plus a dispatch — into a red X on an already-merged PR,
    the one outcome this file's own comments say must never happen (and far
    likelier than the timeout that path already softened to a warning). A
    failed poll read must leave the loop running, the dispatch must not abort
    the step, and no path in it may exit non-zero."""
    job = _job_block(_GOVERNANCE.read_text(encoding="utf-8"), "deploy-on-merge")
    assert re.search(r"(?m)^(?!\s*#).*\bgh pr view[^\n]*--json state[^\n]*\|\|", job), (
        "deploy-on-merge's poll read is unguarded - one transient API error aborts it under set -e"
    )
    assert re.search(r"(?m)^(?!\s*#).*\bif gh workflow run \"?render-deploy\.yml", job), (
        "the dispatch is unguarded - a rejected workflow_dispatch reddens an already-merged PR"
    )
    # `exit 0` is the loop's own success path; anything non-zero is a red X on
    # a PR that has already landed.
    assert not re.search(r"(?m)^(?!\s*#).*\bexit [1-9]", job), (
        "deploy-on-merge must never exit non-zero - the merge has already happened"
    )


def test_run_level_conclusion_flip_is_documented_in_the_header() -> None:
    """A cancelled JOB sets the whole RUN's conclusion, so a superseded
    `deploy-on-merge` poll makes an otherwise clean governance run conclude
    `cancelled` (live: run 30246486520 — gate success, arm success, poll
    cancelled). Nothing requires that conclusion today, but an undocumented
    flip is indistinguishable from a governance run that never withdrew a
    stale arm. Either the cancellation goes away or the header says the
    run-level conclusion is not an audit signal and names what to read
    instead."""
    text = _GOVERNANCE.read_text(encoding="utf-8")
    if not re.search(r"(?m)^\s+cancel-in-progress: true", text):
        return  # nothing cancels any more; the paragraph may retire with it
    header = text.split("\non:", 1)[0]
    assert re.search(r"(?im)^#.*\bRUN-level conclusion\b", header), (
        "governance.yml's header does not document the run-conclusion flip"
    )
    assert "30246486520" in header, "the flip is documented without its live evidence"
    assert "gh run view" in header, (
        "the header must name the per-job conclusions as the signal to read instead"
    )


# --- ND-4 reserved-brand carve-out (fork provenance) -----------------------


def test_reserved_namespace_flag_is_gated_on_a_same_repo_pull_request() -> None:
    """`--allow-reserved-namespace` unlocks ND-4's brand segments (`ocx`,
    `ocx-sh`, `ocx-contrib`, `ocx-rs`), which the operator's own
    `p/ocx/cli.json` and `p/ocx/mirror.json` roots need. Handing it to every
    `pull_request` run would let ANY fork PR claim `p/ocx/**` — publish under
    the index's own brand and be believed by every client resolving through
    this index — so it is granted only when the PR's head repository IS this
    repository.

    **The comparison is no longer in this file, and that is the point.** It
    used to be a `SAME_REPO_PR: ${{ github.event.pull_request.head.repo
    .full_name == github.repository }}` env var feeding a shell `if` that
    appended the flag to an array. It is now `cli/validate_pr._same_repo_pr`,
    which reads `pull_request.head.repo.full_name` out of `$GITHUB_EVENT_PATH`
    and compares it against `$GITHUB_REPOSITORY` — both written by the runner,
    neither by the PR author — and reads every shape that does not positively
    prove same-repo provenance as a fork. Covered in `ocx-sh/indexbot` by
    `tests/cli/test_validate_pr.py::test_a_fork_pull_request_may_not_claim_a_reserved_segment`,
    `::test_a_same_repo_github_pull_request_may_claim_a_reserved_segment`,
    `::test_an_unreadable_github_event_payload_is_treated_as_a_fork` and
    `::test_a_missing_or_malformed_event_file_is_treated_as_a_fork`.

    What is left for THIS side is the hazard that replaced it. The command
    sniffs its own provenance only while the pipeline does not override it:
    `--same-repo-pr` exists for a hand-rolled pipeline whose variables the bot
    cannot know, and one appearing in a generated job would hand the brand to
    every fork PR with no visible change to the gate at all. Neither override
    may be rendered here.

    Second half, ADR-4 BD-4: with every shell step gone, no `run:` line in
    either PR workflow may carry a `${{ }}` expression. Untrusted values reach
    a command through env vars or not at all, and the old `SAME_REPO_PR:` env
    var was that discipline's most load-bearing instance. Now that there is
    nothing left to interpolate, the absence itself is the assertion.
    """
    job = _job_block(_VALIDATE.read_text(encoding="utf-8"), "schema-validate-pr")
    # `_run_lines`, never the raw job text: the rendered file's own comments
    # NAME both override flags while explaining why neither is passed, so an
    # `in job` check would be satisfied by the prose - the same mutation
    # hazard `_grant` and `_runs` document.
    commands = "\n".join(_run_lines(job))

    assert re.search(r"\bindexbot validate-pr\b", commands)
    for override in ("--same-repo-pr", "--fork-pr"):
        assert override not in commands, (
            f"{override} overrides validate-pr's provenance sniff - a fork PR could claim"
            " a reserved brand segment"
        )
    for workflow in (_VALIDATE, _GOVERNANCE):
        for line in _run_lines(workflow.read_text(encoding="utf-8")):
            assert "${{" not in line, (
                f"{workflow.name}: `{line.strip()}` interpolates into a run: line (ADR-4 BD-4)"
            )


def test_the_pr_head_checkout_carries_the_base_history_the_diff_needs() -> None:
    """ND-4 gates CLAIMING a reserved segment, not UPDATING a root already
    committed under one, and `indexbot validate` can only tell those apart
    from each changed root's BASE-ref bytes — which means the job needs the
    merge base, not just the two diff endpoints. A shallow "optimization" here
    fails the required check on every PR whose branch point scrolled out of
    the fetch window: `validate-pr` resolves `origin/$GITHUB_BASE_REF` and a
    shallow clone has no such ref to find. It fails loudly rather than
    reporting an empty diff (`tests/adapters/test_local_git.py::
    test_changed_package_roots_raises_when_the_base_ref_is_unknown`), which is
    the fail-closed half — but a required check that is red on every announce
    is still an outage, so `fetch-depth: 0` stays asserted here.

    The rest of what this test used to pin is inside the command now. The
    base-ref tree under `$RUNNER_TEMP` is `cli/_wiring._run_validate_pr`'s
    `mkdtemp`, asserted to live outside the checkout by
    `tests/cli/test_wiring.py::test_validate_pr_is_wired_to_local_git_and_an_out_of_tree_base_port`
    — the PR-head tree is what `validate` byte-compares against its own
    canonical serialization, so a base-ref copy landing inside it would be
    validated as if it were part of the PR
    (`tests/cli/test_validate_pr.py::test_base_ref_bytes_land_in_the_base_tree_not_the_workspace`).
    The `git cat-file -e` probe before `git show` is
    `adapters/local_git.LocalGit.file_at`
    (`tests/adapters/test_local_git.py::test_file_at_returns_none_for_a_path_absent_at_that_ref`),
    and a root absent at the base ref being left unwritten — so `validate`
    reads it as a new claim, fail closed — is
    `tests/cli/test_validate_pr.py::test_a_root_absent_at_the_base_ref_is_simply_not_written`.
    """
    job = _job_block(_VALIDATE.read_text(encoding="utf-8"), "schema-validate-pr")
    assert "ref: ${{ github.event.pull_request.head.sha }}" in job
    assert "fetch-depth: 0" in job
    # A PR-head checkout must not leave even a read-scoped token in
    # `.git/config` for PR-authored tooling to pick up.
    assert re.search(r"(?m)^\s+persist-credentials: false\s*$", job)


def test_the_reserved_namespace_gate_lives_only_in_the_zero_secret_job() -> None:
    """The gate decides how PR-head content is *validated*, so it belongs in
    the unprivileged `pull_request` workflow — never in `governance.yml`,
    whose entire safety argument is that it runs no PR-head-derived logic.

    Widened past `--allow-reserved-namespace` when that flag stopped being
    rendered at all: an assertion that only names a string nothing emits any
    more is a control that has quietly stopped meaning anything. The gate is
    now `indexbot validate-pr` itself — the command that both selects the
    reserved segments and decides provenance — so no other workflow may run
    it, and no workflow anywhere may carry one of its override flags.

    Scanned over `run:` bodies rather than raw text, for the reason
    `test_reserved_namespace_flag_is_gated_on_a_same_repo_pull_request` gives:
    `governance.yml`'s header narrates the split and names the other half's
    job, and a raw `in` check would be satisfied by that prose."""
    for workflow in _workflow_files():
        commands = "\n".join(_run_lines(workflow.read_text(encoding="utf-8")))
        for override in ("--allow-reserved-namespace", "--same-repo-pr", "--fork-pr"):
            assert override not in commands, f"{workflow.name} carries {override}"
        if workflow == _VALIDATE:
            continue
        assert not re.search(r"\bindexbot validate-pr\b", commands), (
            f"{workflow.name} runs the reserved-namespace gate outside the zero-secret job"
        )


# --- cron is upstream-only -------------------------------------------------


def test_scheduled_jobs_carry_the_upstream_guard() -> None:
    """A fork inherits every `schedule:` in this tree and GitHub keeps firing
    it there, off the fork's own copy of the YAML: ocx-contrib/index (the
    announce bot's fork) ran `render-deploy` every 15 minutes and failed all
    33 times, because no fork holds the Cloudflare secrets, and `ci`,
    `reconcile` and `stale` burned fork minutes on work scoped to this
    repository. Every job a `schedule` event can reach therefore either
    carries the upstream owner guard or excludes the schedule event outright.
    Jobs with `needs:` are exempt: a skipped dependency skips them too."""
    for workflow in _workflow_files():
        text = workflow.read_text(encoding="utf-8")
        if "schedule" not in _triggers(text):
            continue
        for name in _job_names(text):
            job = _job_block(text, name)
            if re.search(r"(?m)^\s{4}needs:", job):
                continue
            condition = re.search(r"(?m)^\s{4}if:\s*(.+)$", job)
            assert condition and (
                _UPSTREAM_GUARD in condition.group(1)
                or "github.event_name != 'schedule'" in condition.group(1)
            ), f"{workflow.name}: job `{name}` runs on cron in every fork of this repo"


def test_the_upstream_guard_binds_the_owner_not_the_repository() -> None:
    """`github.repository_owner`, never `github.repository`: a repository
    rename would leave a `github.repository == ...` guard false on THIS repo,
    and the whole cron surface — deploys included — would go quietly dead
    with no failing check anywhere (the failure mode of issue #67, reached by
    a different route)."""
    for workflow in _workflow_files():
        for line in workflow.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("#") or "if:" not in line:
                continue
            assert "github.repository ==" not in line, (
                f"{workflow.name}: guard binds github.repository, not the owner"
            )


# --- the split is now GENERATED, and the gate is what keeps it -------------

_GENERATED = ("validate.yml", "governance.yml", "reconcile.yml", "pr-checks-label.yml", "stale.yml")


def test_every_governance_workflow_is_generated_and_says_so() -> None:
    """0.2.0 moved these five out of hand-authorship: `indexbot ci` renders
    them from `.github/index-policy.json`, and ci.yml's `verify-indexbot-ci`
    job fails on any hand-edit.

    Every assertion above this line is still the real check — a generator is
    not evidence, it is just where the bytes came from. What this test adds is
    that the bytes really do come from there, because the moment one of these
    files loses its header it also silently leaves the drift gate's scope:
    `indexbot ci --check` would rewrite it without complaint and no one would
    learn that the argument had been edited.
    """
    for name in _GENERATED:
        first_line = (_WORKFLOWS_DIR / name).read_text(encoding="utf-8").split("\n", 1)[0]
        assert parse_header_version(first_line) is not None, (
            f"{name} has no `indexbot ci` header — it is outside the drift gate"
        )


def test_the_hand_written_workflows_are_not_claimed_by_the_generator() -> None:
    """The converse, and the reason the header is per-file rather than a list
    somewhere: `ci.yml`, `render-deploy.yml` and `dependency-review.yml` are
    this deployment's own, and `catalog-ci.yml` belongs to the *other*
    generator. A header appearing on one of them would mean `indexbot ci`
    had started overwriting a file nobody asked it to own."""
    for workflow in _workflow_files():
        if workflow.name in _GENERATED:
            continue
        first_line = workflow.read_text(encoding="utf-8").split("\n", 1)[0]
        assert parse_header_version(first_line) is None, (
            f"{workflow.name} claims to be rendered by indexbot ci"
        )


def test_the_credentialed_job_hands_no_token_to_a_third_party_action() -> None:
    """`arm-auto-merge` runs under `pull_request_target` with `contents:
    write`, and a composite action cannot downscope the token its caller
    holds — so whatever `ci.setup` names receives a credential that can move
    the base branch and squash a pull request.

    Before the one-job-one-command rewrite this could not happen: that job ran
    no `uses:` step at all. It now needs uv, so the grant is unavoidable in
    principle and the control moved to WHAT the setup action does with it.
    `setup-bot` also installs Task and passes `repo-token: ${{ github.token }}`
    to `arduino/setup-task`; none of the generated jobs invoke Task, so this
    deployment points `ci.setup` at `setup-indexbot`, which installs uv and
    nothing else and names no token at all.

    Asserted here rather than in the package because `ci.setup` is deployment
    policy: `indexbot` renders whatever string this repository's
    `index-policy.json` gives it, and only this repository can know what that
    action does. The package-side rule (WF-06) governs the workflow; this
    governs the action it points at.
    """
    action = _REPO_ROOT / ".github" / "actions" / "setup-indexbot" / "action.yml"
    body = action.read_text(encoding="utf-8")
    assert "github.token" not in body
    assert "secrets." not in body
    assert "arduino/setup-task" not in body
    # And the credentialed job must actually be the one using it.
    armed = _job_block(_GOVERNANCE.read_text(encoding="utf-8"), "arm-auto-merge")
    assert "uses: ./.github/actions/setup-indexbot" in armed
    assert "setup-bot" not in armed
