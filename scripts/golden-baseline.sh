#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# golden-baseline.sh — golden-baseline machinery for the upcoming
# catalog-package extraction's identity gate: freezes a sha256 manifest of
# the normalized site/.vitepress/dist tree the render pipeline produces
# from the gitignored demo/ fixture set, so a later package-built dist can
# be diffed against a known-good reference.
#
# Usage:
#   scripts/golden-baseline.sh generate [--update]
#   scripts/golden-baseline.sh verify
#
#   generate [--update]  Run the render pipeline once against demo/,
#                         normalize the resulting dist tree, and compare
#                         its sha256 manifest to the committed baseline
#                         (scripts/golden-baseline.manifest). Any diff
#                         exits 65 unless --update is passed, in which case
#                         the committed manifest is rewritten instead.
#   verify                Build-determinism check: run the render pipeline
#                         twice from a clean state and assert the two
#                         normalized dist trees hash identically. Exit 65
#                         on any nondeterministic path.
#
# Normalization rules (normalize_tree(), below): NONE are applied. Three
# consecutive from-scratch builds of the demo fixture tree (`task
# demo:clean && demo:seed && render:build RENDER_INDEX_DIR=demo`) produced
# byte-identical dist trees across all 218 files, including:
#   - data/catalog/catalog.json's `generated` field: NOT wall-clock -- it's
#     a lexicographic max() over source tag timestamps
#     (bot/src/indexbot/core/render.py `_generated_timestamp`; that module
#     imports no `datetime` by design, precisely so render stays
#     idempotent) -- so no strip/canonicalize step is needed.
#   - Vite content-hashed asset filenames (vite#13071 candidate): did not
#     drift across the 3 builds observed here.
# normalize_tree() is kept as a real (currently identity-copy) step rather
# than removed, so a rule can be added the moment `verify` observes a
# genuine diff, without restructuring the manifest pipeline below it.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
readonly SCRIPT_DIR REPO_ROOT
cd "$REPO_ROOT"

readonly DIST_DIR="${REPO_ROOT}/site/.vitepress/dist"
readonly DIST_LABEL="site/.vitepress/dist"
readonly GOLDEN_DIR="${REPO_ROOT}/.golden-baseline"
readonly MANIFEST_FILE="${REPO_ROOT}/scripts/golden-baseline.manifest"
readonly EXIT_DIFF=65

usage() {
  cat <<'EOF'
Usage: golden-baseline.sh generate [--update]
       golden-baseline.sh verify
EOF
}

run_pipeline() {
  task demo:clean
  task demo:seed
  task render:build RENDER_INDEX_DIR=demo
}

# Copies the just-built dist tree into $1, applying normalization rules.
# Currently an identity copy -- see the header comment for why.
normalize_tree() {
  local dest_dir="$1"
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  cp -a "${DIST_DIR}/." "${dest_dir}/"
}

# Sorted "sha256  site/.vitepress/dist/<relpath>" lines for every file
# under $1 (the normalized copy).
compute_manifest() {
  local src_dir="$1"
  local path rel hash
  local -a entries=()
  while IFS= read -r -d '' path; do
    rel="${path#"${src_dir}"/}"
    hash=$(sha256sum -- "$path" | cut -d' ' -f1)
    entries+=("${hash}  ${DIST_LABEL}/${rel}")
  done < <(find "$src_dir" -type f -print0)
  if ((${#entries[@]} == 0)); then
    echo "golden-baseline: ${src_dir} contains zero files -- refusing to emit an empty manifest" >&2
    exit "$EXIT_DIFF"
  fi
  # Sort by field 2 (path), not the whole line -- sorting by hash would put
  # a changed file's line at an unrelated position and turn a one-file diff
  # into noise instead of a tight per-path diff.
  printf '%s\n' "${entries[@]}" | LC_ALL=C sort -k2
}

# Header recording the site/ tree this manifest derives from, so a later
# regeneration can never silently mask a regression (no way to tell "the
# manifest was current" from "the manifest was rebaselined over a real
# diff" without it).
manifest_header() {
  local site_tree commit_sha
  site_tree=$(git rev-parse HEAD:site)
  commit_sha=$(git rev-parse HEAD)
  cat <<EOF
# golden-baseline manifest -- sha256 of every file in the normalized
# ${DIST_LABEL} tree. Regenerate with: scripts/golden-baseline.sh generate --update
# site tree: ${site_tree}
# commit: ${commit_sha}
EOF
}

# manifest_header() hashes the COMMITTED site/ tree (HEAD:site) but the
# pipeline it accompanies builds the WORKING tree -- a dirty site/ would
# bake a header that lies about what was actually built. Only `generate`
# ever writes or is compared against that header, so only it guards; the
# `verify` double-build check never touches git state.
check_site_clean() {
  local dirty
  dirty=$(git status --porcelain -- site)
  if [[ -n "$dirty" ]]; then
    echo "golden-baseline generate: site/ has uncommitted changes -- the manifest header would record HEAD:site while the pipeline builds the working tree. Commit or stash site/ changes first:" >&2
    echo "$dirty" >&2
    exit "$EXIT_DIFF"
  fi
}

# Runs the pipeline once, normalizes into $1, prints the manifest body (no
# header) to stdout. task/pipeline progress noise goes to stderr so a
# caller capturing this via command substitution gets a clean manifest.
build_and_normalize_manifest() {
  local dest_dir="$1"
  run_pipeline 1>&2
  normalize_tree "$dest_dir"
  compute_manifest "$dest_dir"
}

generate_cmd() {
  local update=0 arg
  for arg in "$@"; do
    case "$arg" in
      --update) update=1 ;;
      *)
        echo "golden-baseline.sh generate: unknown argument '$arg'" >&2
        exit 2
        ;;
    esac
  done

  check_site_clean

  local body file_count
  body=$(build_and_normalize_manifest "${GOLDEN_DIR}/normalized")
  file_count=$(printf '%s\n' "$body" | wc -l)

  if ((update)); then
    { manifest_header; printf '%s\n' "$body"; } >"$MANIFEST_FILE"
    echo "golden-baseline generate: manifest updated (${MANIFEST_FILE}, ${file_count} files)"
    return 0
  fi

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "golden-baseline generate: no committed manifest at ${MANIFEST_FILE} -- run 'generate --update' first" >&2
    exit "$EXIT_DIFF"
  fi

  local old_body
  # grep exits 1 on "no non-comment lines matched" (empty manifest body) --
  # deliberately absorbed, an empty old_body just means "everything differs"
  # below, not a script error.
  old_body=$(grep -v '^#' "$MANIFEST_FILE" || true)

  if [[ "$old_body" == "$body" ]]; then
    echo "golden-baseline generate: OK, dist tree matches committed manifest (${file_count} files)"
    return 0
  fi

  echo "golden-baseline generate: dist tree DIFFERS from committed manifest:" >&2
  diff <(printf '%s\n' "$old_body") <(printf '%s\n' "$body") >&2 || true
  exit "$EXIT_DIFF"
}

verify_cmd() {
  local manifest_a manifest_b file_count
  manifest_a=$(build_and_normalize_manifest "${GOLDEN_DIR}/verify-a")
  manifest_b=$(build_and_normalize_manifest "${GOLDEN_DIR}/verify-b")

  if [[ "$manifest_a" == "$manifest_b" ]]; then
    file_count=$(printf '%s\n' "$manifest_a" | wc -l)
    echo "golden-baseline verify: OK, double build deterministic (${file_count} files)"
    return 0
  fi

  echo "golden-baseline verify: NONDETERMINISTIC paths detected:" >&2
  diff <(printf '%s\n' "$manifest_a") <(printf '%s\n' "$manifest_b") >&2 || true
  exit "$EXIT_DIFF"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    generate)
      shift
      generate_cmd "$@"
      ;;
    verify)
      shift
      verify_cmd "$@"
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
