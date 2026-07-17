#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# setup-sandbox.sh -- idempotent, stage-based provisioning for the
# announce-revamp E2E sandbox (Phase 0). Builds a disposable, all-public
# mirror of this repo's publish/announce/reconcile machinery so the real
# `ocx-sh/index` repo is never touched by end-to-end testing:
#
#   michael-herwig/ocx-index-e2e   -- sandbox index (copy of this repo's main)
#   ocx-contrib/ocx-index-e2e      -- fork of the sandbox (plays the publisher's fork)
#   michael-herwig/ocx-e2e-publisher -- harness: pushes a dummy package to GHCR
#
# Usage: setup-sandbox.sh [stage...]
#   No args runs every stage, in order. Each stage is independently
#   idempotent -- safe to re-run the whole script or a single stage.
#
# Stages: repos content harness seed protect smoke (see usage() below).

OWNER="michael-herwig"
ORG="ocx-contrib"
SANDBOX="ocx-index-e2e"
PUBLISHER="ocx-e2e-publisher"
PKG="ocx-e2e-dummy"
NS="e2e-lab"
PKG_LOGICAL="dummy"
TAG="${E2E_TAG:-1.0.0}"
readonly OWNER ORG SANDBOX PUBLISHER PKG NS PKG_LOGICAL TAG

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
readonly SCRIPT_DIR REPO_ROOT

readonly ALL_STAGES=(repos content harness seed protect smoke)

# Shared cleanup registry: stages that mktemp their own scratch space append
# here instead of setting their own EXIT trap -- a per-function trap would
# clobber any trap set by a later stage in the same invocation (traps don't
# stack in bash).
CLEANUP_PATHS=()
cleanup() {
  local path
  for path in "${CLEANUP_PATHS[@]:-}"; do
    [[ -n "${path}" ]] && rm -rf "${path}"
  done
}
trap cleanup EXIT

usage() {
  cat <<EOF
Usage: $(basename "$0") [stage...]

Stages (run in this order when no args given):
  repos     create the sandbox + publisher repos (fork happens in 'content' --
            GitHub refuses to fork an empty repo)
  content   push this repo's main to the sandbox, fork it, disable render-deploy there
  harness   publish + dispatch the publisher harness (pushes dual-libc package)
  seed      (stub) generate p/${NS}/${PKG_LOGICAL}.json + CAS objects -- stage 2
  protect   branch protection + auto-merge + Actions permissions on sandbox
  smoke     verify anonymous GHCR pull of ghcr.io/${OWNER}/${PKG}

Every stage checks its target state before acting -- re-running is always safe.
EOF
}

repo_exists() {
  gh api "repos/$1" >/dev/null 2>&1
}

# Polls until a workflow file shows up in the Actions API for a repo (there
# is a short registration lag right after a push introduces it).
wait_for_workflow_registered() {
  local repo="$1" workflow="$2" attempt
  for attempt in $(seq 1 10); do
    if gh api "repos/${repo}/actions/workflows/${workflow}" >/dev/null 2>&1; then
      return 0
    fi
    echo "waiting for ${workflow} to register in ${repo} (attempt ${attempt}/10)..." >&2
    sleep 2
  done
  return 1
}

stage_repos() {
  echo "== stage: repos =="

  if repo_exists "${OWNER}/${SANDBOX}"; then
    echo "repos: ${OWNER}/${SANDBOX} already exists, skipping create"
  else
    gh repo create "${OWNER}/${SANDBOX}" --public \
      --description "OCX index E2E sandbox (disposable mirror, never the real index)"
  fi

  if repo_exists "${OWNER}/${PUBLISHER}"; then
    echo "repos: ${OWNER}/${PUBLISHER} already exists, skipping create"
  else
    gh repo create "${OWNER}/${PUBLISHER}" --public \
      --description "OCX E2E publisher harness -- pushes a dummy dual-libc package to GHCR"
  fi
}

stage_content() {
  echo "== stage: content =="
  # SSH, not HTTPS: $GITHUB_TOKEN is an OAuth App token without the
  # `workflow` scope, so an HTTPS git push touching .github/workflows/**
  # is rejected ("refusing to allow an OAuth App to create or update
  # workflow ... without workflow scope") -- confirmed against live GitHub.
  # SSH key auth (the account's own registered key, `admin:public_key`
  # scope) authenticates as the full user, no OAuth scope concept, no
  # restriction. Requires the account's key to already be registered with
  # GitHub (`gh ssh-key list`).
  local sandbox_url="git@github.com:${OWNER}/${SANDBOX}.git"

  # --force acceptable in THIS stage only: sandbox main is disposable scratch
  # content until the `seed` stage (Phase 0 stage 2) lands real p/ data --
  # never force-push once real history exists here.
  git -C "${REPO_ROOT}" push --force "${sandbox_url}" main:main
  echo "content: pushed main -> ${OWNER}/${SANDBOX}#main"

  # Fork here, not in `repos`: GitHub refuses to fork an empty repository
  # (confirmed against live GitHub) -- the sandbox must already have the
  # content pushed above before a fork of it can exist.
  if repo_exists "${ORG}/${SANDBOX}"; then
    echo "content: ${ORG}/${SANDBOX} (fork) already exists, skipping fork"
  else
    gh repo fork "${OWNER}/${SANDBOX}" --org "${ORG}" --default-branch-only
  fi

  if wait_for_workflow_registered "${OWNER}/${SANDBOX}" "render-deploy.yml"; then
    local state
    state=$(gh api "repos/${OWNER}/${SANDBOX}/actions/workflows/render-deploy.yml" --jq '.state')
    if [[ "${state}" == "active" ]]; then
      gh workflow disable render-deploy.yml -R "${OWNER}/${SANDBOX}"
      echo "content: disabled render-deploy.yml (sandbox has no Cloudflare secrets)"
    else
      echo "content: render-deploy.yml already disabled, skipping"
    fi
  else
    echo "content: render-deploy.yml not visible yet -- re-run the 'content' stage to retry the disable" >&2
  fi
}

stage_harness() {
  echo "== stage: harness =="
  # SSH, not HTTPS -- same OAuth `workflow`-scope restriction as
  # stage_content (this repo's own content includes
  # .github/workflows/push-package.yml).
  local publisher_url="git@github.com:${OWNER}/${PUBLISHER}.git"
  local workdir
  workdir=$(mktemp -d)
  CLEANUP_PATHS+=("${workdir}")

  cp -r "${SCRIPT_DIR}/publisher-harness/." "${workdir}/"
  git -C "${workdir}" init -q -b main
  git -C "${workdir}" add -A
  git -C "${workdir}" commit -q -m "harness: publisher content for ${PKG} dual-libc push"
  # --force acceptable: this repo's entire content IS
  # scripts/e2e/publisher-harness/, re-authored fresh from source every run.
  git -C "${workdir}" push --force "${publisher_url}" main:main
  echo "harness: pushed publisher-harness/ -> ${OWNER}/${PUBLISHER}#main"

  # Same race guard as stage_content: the workflow file was just introduced
  # by the push above, and dispatching before it registers 404s.
  wait_for_workflow_registered "${OWNER}/${PUBLISHER}" "push-package.yml" ||
    echo "harness: push-package.yml registration check timed out, dispatching anyway" >&2

  echo "harness: dispatching push-package.yml (tag=${TAG})"
  gh workflow run push-package.yml -R "${OWNER}/${PUBLISHER}" -f "tag=${TAG}"

  # ponytail: gh workflow run doesn't return a run id -- poll for the latest
  # run of this workflow. Fine at this scale (one dispatch per invocation).
  local run_id="" attempt
  for attempt in $(seq 1 15); do
    run_id=$(gh run list -R "${OWNER}/${PUBLISHER}" --workflow=push-package.yml \
      --limit 1 --json databaseId --jq '.[0].databaseId // empty')
    [[ -n "${run_id}" ]] && break
    echo "waiting for the dispatched run to register (attempt ${attempt}/15)..." >&2
    sleep 2
  done
  if [[ -z "${run_id}" ]]; then
    echo "harness: could not find the dispatched run after 30s" >&2
    exit 1
  fi

  echo "harness: watching run ${run_id}"
  gh run watch "${run_id}" -R "${OWNER}/${PUBLISHER}" --exit-status
}

stage_seed() {
  echo "== stage: seed =="
  echo "seed stage not yet implemented (stage 2)"
}

stage_protect() {
  echo "== stage: protect =="

  # enforce_admins stays false (reviewed + rejected as a should-fix): `seed`
  # and content re-syncs push directly to sandbox main as an admin.
  # enforce_admins=true would block every such direct push, since required
  # checks can never be green on a push that isn't a PR.
  gh api -X PUT "repos/${OWNER}/${SANDBOX}/branches/main/protection" \
    -H "Accept: application/vnd.github+json" \
    -F "required_status_checks[strict]=true" \
    -f "required_status_checks[contexts][]=schema-validate-pr" \
    -f "required_status_checks[contexts][]=governance/review-required" \
    -F "enforce_admins=false" \
    -F "required_pull_request_reviews=null" \
    -F "restrictions=null" \
    >/dev/null
  echo "protect: branch protection set on ${OWNER}/${SANDBOX}#main"

  gh repo edit "${OWNER}/${SANDBOX}" --enable-auto-merge --enable-squash-merge
  echo "protect: auto-merge + squash-merge enabled on ${OWNER}/${SANDBOX}"

  # default_workflow_permissions=read (fail-safe default -- every real
  # workflow declares its own explicit `permissions:` block anyway) and
  # can_approve_pull_request_reviews=false (nothing here approves PRs;
  # auto-merge enable, above, isn't gated by this setting).
  gh api -X PUT "repos/${OWNER}/${SANDBOX}/actions/permissions/workflow" \
    -H "Accept: application/vnd.github+json" \
    -f "default_workflow_permissions=read" \
    -F "can_approve_pull_request_reviews=false" \
    >/dev/null
  echo "protect: Actions workflow permissions set to read + no PR-review approval"
}

stage_smoke() {
  echo "== stage: smoke =="
  local settings_url="https://github.com/users/${OWNER}/packages/container/${PKG}/settings"
  local token manifest_file

  token=$(curl -fsS "https://ghcr.io/token?scope=repository:${OWNER}/${PKG}:pull" | jq -r '.token')

  manifest_file=$(mktemp)
  CLEANUP_PATHS+=("${manifest_file}")

  local status
  status=$(curl -sS -o "${manifest_file}" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://ghcr.io/v2/${OWNER}/${PKG}/manifests/${TAG}")

  if [[ "${status}" != "200" ]]; then
    echo "smoke: anonymous pull of ${OWNER}/${PKG}:${TAG} failed (HTTP ${status})" >&2
    echo "smoke: package is likely still private -- flip visibility at ${settings_url}" >&2
    exit 1
  fi

  local manifest_count
  manifest_count=$(jq '.manifests | length' "${manifest_file}")
  if [[ "${manifest_count}" != "2" ]]; then
    echo "smoke: expected 2 manifests in the image index, found ${manifest_count}" >&2
    exit 1
  fi

  if ! jq -e '[.manifests[].platform."os.features"[0]] | sort == ["glibc", "musl"]' "${manifest_file}" >/dev/null; then
    echo "smoke: expected one glibc + one musl os.features manifest, got:" >&2
    jq -c '[.manifests[].platform."os.features"]' "${manifest_file}" >&2
    exit 1
  fi
  echo "smoke: anonymous pull OK -- image index has ${manifest_count} manifests (glibc + musl)"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local -a requested=("$@")
  if [[ ${#requested[@]} -eq 0 ]]; then
    requested=("${ALL_STAGES[@]}")
  fi

  local stage
  for stage in "${requested[@]}"; do
    case "${stage}" in
      repos) stage_repos ;;
      content) stage_content ;;
      harness) stage_harness ;;
      seed) stage_seed ;;
      protect) stage_protect ;;
      smoke) stage_smoke ;;
      *)
        echo "unknown stage: ${stage}" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

main "$@"
