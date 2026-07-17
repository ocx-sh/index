#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# demo-seed.sh — populate demo/p/ (gitignored, never the real p/) with
# throwaway demo packages for a local `task site:serve` design review
# (plan_site_redesign.md "Verification" item 3).
#
# Sources, both already shaped as a `p/<ns>/<pkg>.json` (+ optional CAS
# `o/sha256/**`) tree, copied byte-for-byte via seed_case():
#
#   1. bot/tests/golden/render/<case>/expected/dist/p/** — the 7 golden
#      render-pipeline test cases (active/no-desc/yanked-tag/multi-platform/
#      shared-digest/png-logo/nested-namespace coverage, see
#      bot/tests/core/test_render.py). `core/render.py` copies a package's
#      root JSON and reachable CAS objects into dist/p/** byte-for-byte
#      (`_package_dist_files`), so each case's `expected/dist/p/<ns>/<pkg>*`
#      subtree already IS a valid `p/` source tree.
#   2. scripts/demo-fixtures/p/** — hand-authored packages covering surfaces
#      no golden fixture exercises: status=deprecated + superseded_by, a
#      readme with headings/code-fence/GFM-table, 4-platform observation
#      objects differing across tags, and variant tags + a full
#      latest/major/minor/patch alias chain sharing one digest. Not bot
#      golden fixtures (no assertions in bot/tests/ depend on them) — kept
#      separate so extending demo coverage never touches the bot's 100%
#      branch-coverage test suite.
#
# Caveat: none of this is `schema/fixtures/valid/` -- content digests use
# readability letters (e.g. "rrrr...") outside the schema's [a-f0-9] hex
# range, so seeded data fails `task schema:validate:rendered` / `task
# verify`. Fine for `indexbot render` + visual review (neither re-validates
# digest hex against the schema). demo/ is gitignored and never read by
# `task verify`'s pipeline (see taskfile.yml), so this never needs manual
# cleanup before a gate run.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
readonly SCRIPT_DIR REPO_ROOT

readonly P_DIR="${REPO_ROOT}/demo/p"
readonly GOLDEN_DIR="${REPO_ROOT}/bot/tests/golden/render"
readonly FIXTURES_DIR="${REPO_ROOT}/scripts/demo-fixtures/p"

# Copies one source's `p/<ns>/<pkg>.json` (+ optional CAS `o/sha256/**`)
# subtree into $P_DIR, skipping (deterministically, by discovery order) any
# package id already seeded by an earlier source -- also what makes a
# repeat `demo-seed.sh` run over leftover $P_DIR content idempotent (no
# error, just a "skipping duplicate" log line per already-seeded package).
seed_case() {
  local source_p="$1"
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
  done < <(find "$source_p" -mindepth 2 -maxdepth 2 -type f -name '*.json')
}

main() {
  local case_dir dist_p
  for case_dir in "$GOLDEN_DIR"/*/; do
    dist_p="${case_dir}expected/dist/p"
    if [[ -d "$dist_p" ]]; then
      seed_case "$dist_p"
    fi
  done

  if [[ -d "$FIXTURES_DIR" ]]; then
    seed_case "$FIXTURES_DIR"
  fi
}

main "$@"
