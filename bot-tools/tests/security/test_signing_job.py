"""C-502: the catalog signing job of `render-deploy.yml`.

Static line scans plus real execution of the pieces that decide things: the
`guard` step (run under bash with a stub `gh`), `scripts/sign-catalog.sh`
(run with a stub `ocx` that records its argv), `scripts/bunny-upload.mjs
--list` (the Bunny phase order), and a dry-run of every job-level `if:`.
Stdlib only, like the rest of this suite.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[3]
_WORKFLOW = _REPO_ROOT / ".github" / "workflows" / "render-deploy.yml"
_SIGN_SCRIPT = _REPO_ROOT / "scripts" / "sign-catalog.sh"
_UPLOAD = _REPO_ROOT / "scripts" / "bunny-upload.mjs"
_SMOKE = _REPO_ROOT / "scripts" / "smoke-test.sh"
_PIN_FILE = _REPO_ROOT / "scripts" / "ocx-sign.pin"
_WEEKLY = "17 4 * * 1"


def _text() -> str:
    return _WORKFLOW.read_text(encoding="utf-8")


def _job(name: str) -> str:
    lines = _text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.rstrip() == f"  {name}:")
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  \S", lines[i])), len(lines))
    return "\n".join(lines[start:end])


def _code(block: str) -> str:
    return "\n".join(line for line in block.splitlines() if not line.lstrip().startswith("#"))


def _field(block: str, key: str) -> str:
    match = re.search(rf"(?m)^    {key}:\s*(.+)$", block)
    assert match, f"no job-level {key}"
    return match.group(1).strip()


# --- the sign job's shape ---------------------------------------------------


def test_sign_job_is_the_only_holder_of_the_oidc_token() -> None:
    assert "id-token: write" in _code(_job("sign"))
    for name in re.findall(r"(?m)^  ([A-Za-z0-9_-]+):\s*$", _text().split("\njobs:\n", 1)[1]):
        if name != "sign":
            assert "id-token" not in _code(_job(name)), f"{name} must not hold the OIDC token"
    assert "id-token" not in _code(_text().split("\njobs:\n", 1)[0])


def test_sign_job_holds_no_secret_and_only_two_permissions() -> None:
    code = _code(_job("sign"))
    assert "secrets." not in code
    perms = re.search(r"(?m)^    permissions:\n((?:      \S.*\n)+)", code + "\n")
    assert perms
    assert sorted(line.strip() for line in perms.group(1).splitlines()) == [
        "contents: read",
        "id-token: write",
    ]
    assert "sign-catalog.sh dist" in code
    assert "cache: false" in code  # no cache restore into the job that holds the OIDC token


def test_sign_job_never_runs_on_a_pull_request() -> None:
    text = _text()
    on_block = _code(text.split("\npermissions:", 1)[0])
    assert "pull_request" not in on_block
    assert "refs/heads/main" in _field(_job("sign"), "if")


def test_signed_tree_is_what_both_deploy_jobs_ship() -> None:
    for name in ("deploy", "deploy-index-bunny"):
        job = _job(name)
        assert re.search(r"(?m)^    needs:.*\bsign\b", job), f"{name} must need sign"
        assert "name: index-tree-signed" in job, f"{name} must download the signed tree"
        assert "name: index-tree\n" not in job
    assert "name: index-tree-signed" in _job("sign")  # uploaded by sign


def test_deploy_job_no_longer_renders() -> None:
    code = _code(_job("deploy"))
    assert "render:build" not in code
    assert "setup-bot" not in code
    assert "render:build" in _code(_job("render"))
    assert "secrets." not in _code(_job("render"))


def test_second_cron_is_weekly_and_guard_names_it() -> None:
    text = _text()
    assert f"- cron: '{_WEEKLY}'" in text
    assert f"RESIGN_CRON: '{_WEEKLY}'" in _job("guard")


# --- dry run of the job-level `if:` expressions -----------------------------


class _Ctx(dict):
    def __getattr__(self, key: str):
        value = self[key]
        return _Ctx(value) if isinstance(value, dict) else value


def _eval(expr: str, ctx: dict) -> bool:
    py = expr.replace("&&", " and ").replace("||", " or ")
    py = re.sub(r"!=", "!=", py)
    py = re.sub(r"\b(github|needs)\.([A-Za-z_.]+)", lambda m: f"_{m.group(1)}.{m.group(2)}", py)
    return bool(eval(py, {"__builtins__": {}}, {"_github": _Ctx(ctx["github"]), "_needs": _Ctx(ctx["needs"])}))  # noqa: S307


def _ctx(event: str, ref: str, should_deploy: str, schedule: str = "") -> dict:
    return {
        "github": {
            "event_name": event,
            "ref": ref,
            "repository_owner": "ocx-sh",
            "event": {"schedule": schedule},
        },
        "needs": {"guard": {"outputs": {"should_deploy": should_deploy}}},
    }


@pytest.mark.parametrize(
    ("event", "ref", "should_deploy", "expect"),
    [
        ("push", "refs/heads/main", "true", True),
        ("schedule", "refs/heads/main", "true", True),
        ("schedule", "refs/heads/main", "false", False),
        ("workflow_dispatch", "refs/heads/main", "true", True),
        ("workflow_dispatch", "refs/heads/feature", "true", False),
        ("pull_request", "refs/pull/1/merge", "true", False),
    ],
)
def test_sign_if_dry_run(event: str, ref: str, should_deploy: str, expect: bool) -> None:
    assert _eval(_field(_job("sign"), "if"), _ctx(event, ref, should_deploy)) is expect


# --- the guard step, executed -------------------------------------------------


def _guard_script() -> str:
    lines = _job("guard").splitlines()
    start = next(i for i, line in enumerate(lines) if re.match(r"^\s+run: \|$", line))
    indent = len(lines[start]) - len(lines[start].lstrip()) + 2
    body = []
    for line in lines[start + 1 :]:
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            break
        body.append(line[indent:])
    return "\n".join(body)


def _run_guard(tmp_path: Path, event: str, schedule: str, last: str, head: str = "abc") -> str:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(f"#!/bin/sh\necho '{last}'\n")
    gh.chmod(0o755)
    out = tmp_path / "out"
    out.write_text("")
    env = {
        **os.environ,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "EVENT": event,
        "SCHEDULE": schedule,
        "RESIGN_CRON": _WEEKLY,
        "HEAD_SHA": head,
        "REPO": "ocx-sh/index",
        "GITHUB_OUTPUT": str(out),
    }
    subprocess.run(["bash", "-c", _guard_script()], env=env, check=True, capture_output=True)
    return out.read_text().strip()


@pytest.mark.parametrize(
    ("event", "schedule", "last", "expect"),
    [
        ("schedule", "*/15 * * * *", "abc", "should_deploy=false"),  # unchanged main: tick skips
        ("schedule", "*/15 * * * *", "old", "should_deploy=true"),
        (
            "schedule",
            _WEEKLY,
            "abc",
            "should_deploy=true",
        ),  # weekly re-sign runs with main unchanged
        ("push", "", "abc", "should_deploy=true"),
        ("workflow_dispatch", "", "abc", "should_deploy=true"),
    ],
)
def test_guard_cron_bypass(tmp_path: Path, event: str, schedule: str, last: str, expect: str) -> None:
    assert _run_guard(tmp_path, event, schedule, last) == expect


# --- sign-catalog.sh ----------------------------------------------------------

_GOOD_PIN = "ghcr.io/ocx-sh/dev/cli@sha256:" + "ab" * 32


def _stub(tmp_path: Path) -> tuple[Path, Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    log = tmp_path / "argv"
    ocx = bin_dir / "ocx"
    ocx.write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > "{log}"\n')
    ocx.chmod(0o755)
    return bin_dir, log


def _sign(tmp_path: Path, pin: str, *args: str, extra_env: dict | None = None):
    bin_dir, log = _stub(tmp_path)
    pin_file = tmp_path / "pin"
    pin_file.write_text(f"# comment\n{pin}\n")
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "OCX_SIGN_PIN_FILE": str(pin_file)}
    env.update(extra_env or {})
    (tmp_path / "dist" / "c").mkdir(parents=True, exist_ok=True)
    (tmp_path / "dist" / "c" / "index.json").write_text("{}")
    result = subprocess.run(
        ["bash", str(_SIGN_SCRIPT), str(tmp_path / "dist"), *args],
        env=env,
        capture_output=True,
        text=True,
    )
    return result, log


def test_sign_script_runs_the_contract_invocation(tmp_path: Path) -> None:
    result, log = _sign(tmp_path, _GOOD_PIN)
    assert result.returncode == 0, result.stderr
    assert log.read_text().splitlines() == [
        "package",
        "exec",
        _GOOD_PIN,
        "--",
        "ocx",
        "index",
        "sign",
        str(tmp_path / "dist"),
        "--registry",
        "ocx.sh",
        "--expires-in-days",
        "30",
        "--no-tty",
    ]


def test_sign_script_registry_days_and_extra_args_are_overridable(tmp_path: Path) -> None:
    result, log = _sign(
        tmp_path,
        _GOOD_PIN,
        "--key",
        "k.pem",
        extra_env={"SIGN_REGISTRY": "e2e.example", "SIGN_EXPIRES_DAYS": "0"},
    )
    assert result.returncode == 0, result.stderr
    argv = log.read_text().splitlines()
    assert argv[-7:] == ["--registry", "e2e.example", "--expires-in-days", "0", "--no-tty", "--key", "k.pem"]


@pytest.mark.parametrize(
    "pin",
    [
        "ghcr.io/ocx-sh/dev/cli:latest",
        "ghcr.io/ocx-sh/dev/cli@sha256:abc",
        "ghcr.io/ocx-sh/dev/cli@sha256:" + "0" * 64,  # the unset-pin sentinel
        "",
    ],
)
def test_sign_script_refuses_an_unusable_pin_before_running_ocx(tmp_path: Path, pin: str) -> None:
    result, log = _sign(tmp_path, pin)
    assert result.returncode != 0
    assert not log.exists()


def test_sign_script_refuses_a_dir_without_a_catalog(tmp_path: Path) -> None:
    result, _ = _sign(tmp_path, _GOOD_PIN)
    assert result.returncode == 0  # dist/c exists in the helper
    shutil.rmtree(tmp_path / "dist" / "c")
    bin_dir, _ = _stub(tmp_path)
    again = subprocess.run(
        ["bash", str(_SIGN_SCRIPT), str(tmp_path / "dist")],
        env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "OCX_SIGN_PIN_FILE": str(tmp_path / "pin")},
        capture_output=True,
    )
    assert again.returncode != 0


def test_committed_pin_file_is_well_formed() -> None:
    lines = [ln for ln in _PIN_FILE.read_text().splitlines() if ln.strip() and not ln.startswith("#")]
    assert len(lines) == 1
    assert re.fullmatch(r"ghcr\.io/ocx-sh/dev/cli@sha256:[0-9a-f]{64}", lines[0])


def test_workflow_never_echoes_a_secret_into_the_log() -> None:
    for line in _code(_text()).splitlines():
        assert not re.search(r"\becho\b.*secrets\.", line)


# --- Bunny phase order --------------------------------------------------------


@pytest.mark.skipif(shutil.which("node") is None, reason="node is a runner prerequisite of this script")
def test_bunny_lists_signature_after_catalog_and_both_after_packages(tmp_path: Path) -> None:
    for rel in (
        "config.json",
        "c/index.json",
        "c/index.json.sigstore.json",
        "p/ns/pkg.json",
        "p/ns/pkg/o/sha256/aa.json",
        "site.html",
    ):
        f = tmp_path / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("{}")
    env = {k: v for k, v in os.environ.items() if k != "BUNNY_EDGE_STORAGE_KEY"}
    out = subprocess.run(
        ["node", str(_UPLOAD), "--list", str(tmp_path)], env=env, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    order = [line.split("\t")[1] for line in out]
    assert "site.html" not in order
    assert order.index("p/ns/pkg/o/sha256/aa.json") < order.index("p/ns/pkg.json")
    assert order.index("p/ns/pkg.json") < order.index("c/index.json")
    assert order.index("c/index.json") < order.index("c/index.json.sigstore.json")
    assert order.index("config.json") > order.index("p/ns/pkg.json")


# --- smoke --------------------------------------------------------------------


def test_smoke_has_a_signed_mode_that_checks_signature_and_enforce() -> None:
    text = _SMOKE.read_text()
    assert "--signed" in text
    assert "c/index.json.sigstore.json" in text
    assert "index_signature" in text and "enforce" in text
    assert "--signed" in _code(_job("smoke"))
