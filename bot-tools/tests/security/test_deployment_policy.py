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

from pathlib import Path

from ocx_indexbot.cli import _wiring
from ocx_indexbot.core.policy import INDEX_POLICY_PATH, parse_index_policy

_REPO_ROOT = Path(__file__).resolve().parents[3]
_WORKFLOWS_DIR = _REPO_ROOT / ".github" / "workflows"


def _shipped_registry_hosts() -> frozenset[str]:
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
    assert _shipped_registry_hosts() == frozenset({"ghcr.io", "ocx.sh"})


def test_g03_shipped_policy_is_servable_by_an_adapter() -> None:
    """The other half of the same guard, against the real file rather than a
    fabricated one: every host this index allowlists has a `RegistryPort` that
    can actually fetch its bytes. Allowlisting what cannot be served produces
    roots that validate and then fail every download."""
    assert _shipped_registry_hosts() <= _wiring.REGISTRY_ADAPTER_HOSTS


# --- G-08 / G-17 (RETIRED — absence tests) ---------------------------------


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
