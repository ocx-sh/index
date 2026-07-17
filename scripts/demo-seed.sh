#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# demo-seed.sh — populate p/ with throwaway demo packages for a local
# `task site:serve` design review (plan_site_redesign.md "Verification"
# item 3).
#
# Source: bot/tests/golden/render/<case>/expected/dist/p/** — the 7 golden
# render-pipeline test cases (active/no-desc/yanked-tag/multi-platform/
# shared-digest/png-logo/nested-namespace coverage, see
# bot/tests/core/test_render.py). `core/render.py` copies a package's root
# JSON and reachable CAS objects into dist/p/** byte-for-byte
# (`_package_dist_files`), so each case's `expected/dist/p/<ns>/<pkg>*`
# subtree already IS a valid `p/` source tree — no separate "source" fixture
# exists or is needed, only the rendered-output copy.
#
# Caveat: these are unit-test fixtures, not `schema/fixtures/valid/` --
# content digests use readability letters (e.g. "rrrr...") outside the
# schema's [a-f0-9] hex range, so seeded data fails
# `task schema:validate:rendered` / `task verify`. Fine for `indexbot
# render` + visual review (neither re-validates digest hex against the
# schema); always `task demo:clean` before running `task verify`. Never
# commit p/'s seeded contents.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
readonly SCRIPT_DIR REPO_ROOT

readonly P_DIR="${REPO_ROOT}/p"
readonly GOLDEN_DIR="${REPO_ROOT}/bot/tests/golden/render"

refuse_if_dirty() {
  if git -C "$REPO_ROOT" status --porcelain -- p/ | grep -q '^??'; then
    echo "demo-seed.sh: p/ already has untracked files -- refusing to clobber real work. Run 'task demo:clean' first (or clean up manually) and retry." >&2
    exit 1
  fi
}

# Copies one golden case's `expected/dist/p` subtree into $P_DIR, skipping
# (deterministically, by discovery order) any package id already seeded by
# an earlier case.
seed_case() {
  local case_dist_p="$1"
  local root_file namespace package target_dir cas_dir
  while IFS= read -r root_file; do
    namespace=$(basename "$(dirname "$root_file")")
    package=$(basename "$root_file" .json)
    target_dir="${P_DIR}/${namespace}"
    if [[ -e "${target_dir}/${package}.json" ]]; then
      echo "demo-seed.sh: skipping duplicate package ${namespace}/${package} (already seeded)" >&2
      continue
    fi
    mkdir -p "$target_dir"
    cp "$root_file" "${target_dir}/${package}.json"
    cas_dir="$(dirname "$root_file")/${package}"
    if [[ -d "$cas_dir" ]]; then
      cp -r "$cas_dir" "${target_dir}/${package}"
    fi
    echo "demo-seed.sh: seeded ${namespace}/${package}"
  done < <(find "$case_dist_p" -mindepth 2 -maxdepth 2 -type f -name '*.json')
}

main() {
  refuse_if_dirty

  local case_dir dist_p
  for case_dir in "$GOLDEN_DIR"/*/; do
    dist_p="${case_dir}expected/dist/p"
    if [[ -d "$dist_p" ]]; then
      seed_case "$dist_p"
    fi
  done
}

main "$@"
