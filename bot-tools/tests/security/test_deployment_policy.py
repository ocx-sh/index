"""This deployment's own half of the governance suite.

`ocx-indexbot` ships the invariants that hold for *any* index — its
`indexbot workflows-check` subcommand and its own test suite. What could not
travel with the package is everything that asserts on THIS repository's
committed files: the exact registry-host policy the public index ships, and
the absence of surfaces that were retired here.

Contract wording: ADR-4 (`adr_index_bot_and_workflow_security.md`)
Governance-Contract table + Amendment A1, ADR-6 (`adr_fork_pr_announce.md`)
FP-8. The package-side map of which assertion went where is
`docs/reference/workflow-invariants.md` in `ocx-sh/indexbot`.

Runs against the installed `ocx_indexbot`, deliberately: the shipped parser
and the shipped adapter list are the authorities, and a restated copy here
would pass while the real thing disagreed.
"""

from __future__ import annotations

import json
from pathlib import Path

from ocx_indexbot.cli import _wiring
from ocx_indexbot.core.maintainers import parse_maintainers
from ocx_indexbot.core.policy import INDEX_POLICY_PATH, IndexPolicy, parse_index_policy
from ocx_indexbot.core.validate_entry import parse_package_root, serialize_package_root
from ocx_indexbot.core.workflow_invariants import resolves_at_runtime

_REPO_ROOT = Path(__file__).resolve().parents[3]
_WORKFLOWS_DIR = _REPO_ROOT / ".github" / "workflows"


def _shipped_policy() -> IndexPolicy:
    """This repo's committed `.github/index-policy.json`, parsed by the same
    code the bot runs — never a second implementation of the grammar."""
    return parse_index_policy((_REPO_ROOT / INDEX_POLICY_PATH).read_bytes())


def _workflow_files() -> list[Path]:
    return sorted(_WORKFLOWS_DIR.glob("*.yml"))


# --- G-03: the shipped allowlist -------------------------------------------


def test_g03_shipped_policy_is_exactly_the_two_ocx_operated_hosts() -> None:
    """G-03's effective policy for THIS index. The allowlist is a
    per-deployment input; this repo IS the public index, and its policy is
    exactly `{"ghcr.io", "ocx.sh"}` — `ghcr.io` for every third-party mirror,
    `ocx.sh` for the operator's own first-party repositories (`ocx/cli`,
    `ocx/mirror`, `regclient/regsync`), which must have index roots or a
    default-index client 404s terminally on them.

    Any pull request that widens the committed file fails here, which is the
    reviewed-diff half of "extend only via reviewed PR" made mechanical.
    """
    assert _shipped_policy().registry_hosts == frozenset({"ghcr.io", "ocx.sh"})


def test_g03_shipped_policy_is_servable_by_an_adapter() -> None:
    """The other half of the same guard, against the real file rather than a
    fabricated one: every host this index allowlists has a `RegistryPort` that
    can actually fetch its bytes. Allowlisting what cannot be served produces
    roots that validate and then fail every download."""
    assert _shipped_policy().registry_hosts <= _wiring.REGISTRY_ADAPTER_HOSTS


# --- the deployment's own identity -----------------------------------------


def test_this_index_declares_the_ocx_identity_it_publishes_under() -> None:
    """0.2.0 moved the prefix and the depth out of the package and into this
    file. Nothing in the bot defaults to `ocx.sh` any more, so this repository
    is the only remaining place that says the public index publishes
    `ocx.sh/<namespace>/<package>` — and every rendered `config.json`, every
    `root.name` check and every `p/**` path shape follows from it."""
    policy = _shipped_policy()
    assert policy.name == "ocx.sh"
    assert policy.name_segments == 2


def test_the_ocx_brand_segments_stay_reserved() -> None:
    """These four moved out of the package with everything else deployment-
    specific, which means an edit deleting them here would silently open
    `p/ocx/**` to any fork PR — the claim `validate.yml` withholds
    `--allow-reserved-namespace` from fork PRs precisely to prevent."""
    assert _shipped_policy().reserved_namespaces == frozenset(
        {"ocx", "ocx-sh", "ocx-contrib", "ocx-rs"}
    )


def test_this_deployment_keeps_the_owners_merge_policy() -> None:
    """`always` would drop G-19 — the author-owns-every-touched-root check —
    on a public index anyone may open a PR against. `never` would strand the
    announce lane behind a human forever. Neither is a change to make without
    the diff being read."""
    assert _shipped_policy().auto_merge == "owners"


def test_the_generated_workflows_are_pinned_to_this_repositorys_own_owner() -> None:
    """Every generated schedule guards on `ci.owner`, and a fork inherits
    every schedule in a workflow file. A wrong value here silently disables
    the guard upstream and enables it in every fork."""
    assert _shipped_policy().ci.owner == "ocx-sh"


# --- G-08 / G-17 (RETIRED — absence tests) ---------------------------------


def test_this_deployment_pins_the_bot_its_privileged_job_runs() -> None:
    """`ci.run` is the command every generated job invokes, `arm-auto-merge`
    under `pull_request_target` with `contents: write` included. Without
    `--frozen`, `uv run` re-locks against `pyproject.toml` before running —
    and re-locking a git source moves the commit — so the version executing
    with a token that can merge a pull request would be chosen at job start
    rather than by a reviewed lockfile diff.

    `indexbot ci` refuses to render a floating `ci.run` (WF-08's render-time
    twin), so this is belt-and-braces against the render being bypassed. It
    is pinned HERE, next to the registry allowlist, for the same reason that
    one is: which bot this deployment runs is this deployment's policy, and
    the package can only refuse the shapes it recognises.
    """
    run = _shipped_policy().ci.run
    assert "--frozen" in run.split() or "--locked" in run.split(), run
    assert not resolves_at_runtime(run), run


def test_g08_no_repository_dispatch_announce_workflow() -> None:
    """G-08 RETIRED under the fork-PR lane (ADR-4 Amendment A1): the
    `repository_dispatch` doorbell workflow is gone and stays gone."""
    assert not (_WORKFLOWS_DIR / "announce.yml").exists()


def test_g17_no_announce_pat_surface() -> None:
    """G-17 RETIRED (ADR-4 Amendment A1 / ADR-6 FP-8): no namespace-scoped
    announce PAT in any workflow; the failed-check spam-label + stale-close
    path exists instead."""
    for workflow in _workflow_files():
        text = workflow.read_text(encoding="utf-8")
        assert "ANNOUNCE_PAT" not in text
        assert "secrets.ANNOUNCE" not in text
    assert (_WORKFLOWS_DIR / "pr-checks-label.yml").exists()  # FP-8 failed-check label path
    assert (_WORKFLOWS_DIR / "stale.yml").exists()  # FP-8 stale-close path


# --- the migrated owners[] tree --------------------------------------------


def test_every_committed_root_carries_the_canonical_owner_spelling() -> None:
    """This deployment finished the 0.5.0 `owners[]` migration
    (`adr_forge_neutral_owners.md` D1/D2), and the committed tree is where
    that is true or not.

    Two claims per root, both against the shipped codec rather than a
    restatement of it: it parses (so the two spellings, which the parser
    refuses to let disagree, agree), and re-serializing it reproduces the
    committed bytes exactly. The second is what a hand-edit trips — the
    `validate` lane makes the same byte comparison, but only over a pull
    request's own changed roots, so nothing else looks at the whole tree.
    """
    roots = sorted(_REPO_ROOT.glob("p/*/*.json"))
    assert roots, "no package roots found — the glob or the tree moved"

    for path in roots:
        raw = path.read_bytes()
        root = parse_package_root(raw)
        assert serialize_package_root(root) == raw, path
        assert root.owners, path
        # `login`/`id` are what `model.Owner` carries; the derived legacy pair
        # is asserted on the wire bytes, since the dataclass cannot hold it.
        assert all(owner.login and owner.id > 0 for owner in root.owners), path
        for entry in json.loads(raw)["owners"]:
            assert entry["login"] == entry["github"], path
            assert entry["id"] == entry["github_id"], path


def test_the_committed_maintainers_file_parses_and_names_a_reviewer() -> None:
    """G-20's input, in this deployment's own spelling. `parse_maintainers`
    accepts either, so a file left on the pre-0.5.0 keys would pass a
    "does it parse" check while this repo's own migration was half-done."""
    raw = (_REPO_ROOT / ".github" / "maintainers.yml").read_bytes()

    maintainers = parse_maintainers(raw)

    assert maintainers, "no maintainers — the human lane would request nobody"
    assert all(m.login and m.id > 0 for m in maintainers)
    entries = [
        line.strip()
        for line in raw.decode("utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ][1:]
    assert entries, "no entries below the `maintainers:` key"
    assert not [line for line in entries if line.startswith(("- github:", "github_id:"))], entries
