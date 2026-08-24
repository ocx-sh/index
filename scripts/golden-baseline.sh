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
# plan_catalog_extraction WP-11 (dogfood switchover): `generate`'s
# comparison is NOT plain string equality any more -- see
# `compare_manifests`/`is_index_mirror_path` below. Every committed
# manifest path is still required exactly (missing or content-differing
# is always a failure); a build path absent from the manifest is tolerated
# ONLY under "${DIST_LABEL}/index/<label>/" for a label this repo's own
# catalog.config.json sources actually produce -- the per-source wire
# mirror `@ocx-sh/catalog` writes (C-006), verified separately (byte-copy
# of its own source) rather than by this check. This is deliberately not a
# subset check in the other direction.
#
# "${DIST_LABEL}/_headers" -- the Cloudflare Pages CSP/sandbox headers file,
# also new C-006 output -- is a plain committed manifest path like any
# other, NOT tolerated as an extra: it is a pure function of
# catalog.config.json's sources, so it belongs on the exact-match side of
# this gate. Security review W3 (post-WP-11): an earlier version of this
# script exempted it the same way as the index-mirror tree, which meant its
# disappearance from a build -- silently dropping the `/p/*`
# Content-Security-Policy: sandbox` header -- produced no failure here. Never
# reintroduce that exemption.
#
# Normalization rules (normalize_tree(), below): NONE are applied. Three
# consecutive from-scratch builds of the demo fixture tree (`task
# demo:clean && demo:seed && render:build RENDER_INDEX_DIR=demo`) produced
# byte-identical dist trees across all 218 files, including:
#   - data/catalog/catalog.json's `generated` field: NOT wall-clock -- it's
#     a lexicographic max() over source tag timestamps
#     (ocx-indexbot's core/render.py `_generated_timestamp`; that module
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

# Populated by compute_expected_index_labels(), called from generate_cmd
# (NOT from inside build_and_normalize_manifest -- that runs in a `$(...)`
# subshell via its callers, and appends made there never survive back to
# this shell) once demo/p/** exists on disk. is_index_mirror_path() reads
# this, so nothing may call it beforehand.
EXPECTED_INDEX_LABELS=()

usage() {
  cat <<'EOF'
Usage: golden-baseline.sh generate [--update]
       golden-baseline.sh verify
EOF
}

run_pipeline() {
  task demo:clean
  task demo:seed
  # CATALOG_DEV= (CLI beats .env.local) pins the released renderer -- the
  # committed manifest must never record a sibling build.
  task render:build RENDER_INDEX_DIR=demo CATALOG_DEV=
}

# Copies the just-built dist tree into $1, applying normalization rules.
# Currently an identity copy -- see the header comment for why.
normalize_tree() {
  local dest_dir="$1"
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  cp -a "${DIST_DIR}/." "${dest_dir}/"
}

# Every /index/<label>/ prefix catalog.config.json's sources[] can actually
# produce (C-006), so is_index_mirror_path exempts exactly those -- not a
# blanket "${DIST_LABEL}/index/"* wildcard (WP-11 security review B-1b: that
# wildcard would silently pass ANY attacker-chosen segment under dist/index/
# as "expected mirror output", including one that collides with a claimable
# `index/<ns>` namespace, e.g. dist/index/index/... vs a package literally
# named `index`). A source's label is explicit (`sources[].label`) or, when
# absent, derived by the TS source layer from the root-name prefix of the
# packages it finds; this mirrors that derivation off the SAME committed
# package roots the pipeline just built from (demo/p/**, since run_pipeline()
# always builds the demo tree) rather than re-deriving it for url/git sources
# this repo's own config never configures.
compute_expected_index_labels() {
  local config="${REPO_ROOT}/catalog.config.json"
  local n i label path root_file name
  n=$(jq '.sources | length' "$config")
  for ((i = 0; i < n; i++)); do
    label=$(jq -r ".sources[$i].label // empty" "$config")
    if [[ -n "$label" ]]; then
      EXPECTED_INDEX_LABELS+=("$label")
      continue
    fi
    path=$(jq -r ".sources[$i].path // empty" "$config")
    if [[ -z "$path" ]]; then
      echo "golden-baseline: catalog.config.json sources[$i] has neither" \
        "label nor path -- compute_expected_index_labels() only derives" \
        "labels for path sources (this repo's config has no others today);" \
        "extend this function before adding one." >&2
      exit "$EXIT_DIFF"
    fi
    while IFS= read -r -d '' root_file; do
      name=$(jq -r '.name' "$root_file")
      EXPECTED_INDEX_LABELS+=("${name%%/*}")
    done < <(find "${REPO_ROOT}/demo/p" -mindepth 2 -maxdepth 2 -name '*.json' -print0 2>/dev/null)
  done
}

# True iff $1 (one "hash  path" manifest line) names a path under
# "${DIST_LABEL}/index/<label>/" for a label compute_expected_index_labels()
# populated -- the per-source wire mirror `@ocx-sh/catalog` writes
# (plan_catalog_extraction WP-11, C-006). Expected additive output, verified
# separately (byte-copy of its own source) rather than by this check.
is_index_mirror_path() {
  local path="$1" label
  # S3: ${arr[@]+"${arr[@]}"} (not bare "${arr[@]}") -- a zero-element array
  # expands to nothing here instead of an "unbound variable" error under
  # set -u on bash 3.2 (macOS system bash; fixed in bash 4.4, which is what
  # this repo's CI runners ship).
  for label in "${EXPECTED_INDEX_LABELS[@]+"${EXPECTED_INDEX_LABELS[@]}"}"; do
    case "$path" in
      "${DIST_LABEL}/index/${label}/"*) return 0 ;;
    esac
  done
  return 1
}

# Every additive-output check compare_manifests/generate_cmd's --update
# filter tolerate an unmatched build path for. Currently just the
# index-mirror tree -- see is_index_mirror_path's doc for why "${DIST_LABEL}/_headers"
# is deliberately NOT here (W3).
is_expected_extra_path() {
  is_index_mirror_path "$1"
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
  local site_tree commit_sha catalog_version catalog_spec
  site_tree=$(git rev-parse HEAD:site)
  commit_sha=$(git rev-parse HEAD)
  # W-2: the dist tree is just as much a function of WHICH @ocx-sh/catalog
  # built it as of site/ -- record the INSTALLED version (what actually
  # built the tree; bun.lock pins it and the dirty-tree guard below covers
  # bun.lock) alongside the committed dependency spec, so a regenerated
  # manifest can't silently mask "the package changed" the way an
  # unrecorded upgrade would.
  catalog_version=$(jq -r '.version' node_modules/@ocx-sh/catalog/package.json)
  catalog_spec=$(jq -r '.dependencies["@ocx-sh/catalog"]' package.json)
  cat <<EOF
# golden-baseline manifest -- sha256 of every file in the normalized
# ${DIST_LABEL} tree. Regenerate with: scripts/golden-baseline.sh generate --update
# site tree: ${site_tree}
# commit: ${commit_sha}
# @ocx-sh/catalog: ${catalog_version} (${catalog_spec})
EOF
}

# manifest_header() hashes the COMMITTED site/ tree (HEAD:site) but the
# pipeline it accompanies builds the WORKING tree -- a dirty site/ would
# bake a header that lies about what was actually built. Only `generate`
# ever writes or is compared against that header, so only it guards; the
# `verify` double-build check never touches git state.
#
# W-2: also covers catalog.config.json/package.json/bun.lock -- the dist
# tree depends on all three (sources/labels config, and which
# `@ocx-sh/catalog` version bun.lock resolves), not just site/; a dirty one
# of those would build against working-tree state the header doesn't
# record either.
check_site_clean() {
  local dirty
  dirty=$(git status --porcelain -- site catalog.config.json package.json bun.lock)
  if [[ -n "$dirty" ]]; then
    echo "golden-baseline generate: uncommitted changes under site/, catalog.config.json, package.json, or bun.lock -- the manifest header would record HEAD state while the pipeline builds the working tree. Commit or stash first:" >&2
    echo "$dirty" >&2
    exit "$EXIT_DIFF"
  fi
}

# Compares $1 (committed manifest body, never contains index-mirror lines
# -- see below) against $2 (current build's FULL manifest body, index-
# mirror lines included). Every line in $1 must appear byte-identically in
# $2 -- a missing or content-differing baseline path is always a failure.
# A line present in $2 but absent from $1 is tolerated ONLY when
# `is_expected_extra_path` accepts it; anything else is an unexpected extra
# file and still fails. This is deliberately NOT a subset check: every
# baseline path is still required exactly, only the direction that would
# hide a real regression (missing/changed) is strict, while the one
# genuinely-expected additive shape (the per-source mirror tree) is
# named and excluded explicitly rather than accepted by a blanket
# loosening. Prints a labeled diff to stderr and returns 1 on any other
# mismatch.
compare_manifests() {
  local old_body="$1" new_body="$2"
  local -A new_by_path=()
  local line path
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="${line#*  }"
    new_by_path["$path"]="$line"
  done <<<"$new_body"

  local ok=1
  local -a missing=() changed=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="${line#*  }"
    if [[ -z "${new_by_path[$path]+set}" ]]; then
      missing+=("$line")
      ok=0
    elif [[ "${new_by_path[$path]}" != "$line" ]]; then
      # Both sides named -- a hash mismatch, not an absence, so show what
      # the build actually produced alongside what the baseline pins
      # (S-1: printing only the baseline line hides the diagnosis).
      changed+=("baseline: ${line}" "built:    ${new_by_path[$path]}")
      ok=0
    fi
    unset "new_by_path[$path]"
  done <<<"$old_body"

  local -a unexpected=()
  for path in "${!new_by_path[@]}"; do
    if ! is_expected_extra_path "$path"; then
      unexpected+=("${new_by_path[$path]}")
      ok=0
    fi
  done

  if ((ok)); then
    return 0
  fi

  echo "golden-baseline generate: dist tree DIFFERS from committed manifest:" >&2
  if ((${#missing[@]})); then
    echo "  missing from the build entirely:" >&2
    printf '    %s\n' "${missing[@]}" | LC_ALL=C sort >&2
  fi
  if ((${#changed[@]})); then
    echo "  content changed (same path, different hash):" >&2
    printf '    %s\n' "${changed[@]}" >&2
  fi
  if ((${#unexpected[@]})); then
    echo "  unexpected extra files (not in the manifest, not under a declared ${DIST_LABEL}/index/<label>/):" >&2
    printf '    %s\n' "${unexpected[@]}" | LC_ALL=C sort >&2
  fi
  return 1
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
  # Bash bug fix (found running this for real): body=$(...) runs
  # build_and_normalize_manifest in a SUBSHELL -- calling
  # compute_expected_index_labels() from inside it (as this used to) throws
  # away every append the moment the subshell exits, leaving
  # EXPECTED_INDEX_LABELS permanently empty here and is_index_mirror_path
  # unable to exempt anything. demo/p/** is a real file on disk by now
  # (run_pipeline already wrote it), so computing labels here, in THIS
  # (parent) shell, is both correct and sufficient.
  compute_expected_index_labels
  file_count=$(printf '%s\n' "$body" | wc -l)

  if ((update)); then
    # Index-mirror lines never enter the committed manifest -- expected
    # additive output (`is_index_mirror_path`'s own doc), not baseline
    # state; writing them here would make a later run compare the mirror
    # tree back against itself and mask a real regression in it instead of
    # verifying it (it's a byte-copy of its own source, a different
    # guarantee than this identity check). "${DIST_LABEL}/_headers" is NOT
    # filtered out here -- it belongs in the committed manifest (W3).
    local body_for_manifest="" manifest_file_count line path
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      path="${line#*  }"
      is_expected_extra_path "$path" && continue
      body_for_manifest+="${line}"$'\n'
    done <<<"$body"
    if [[ -z "$body_for_manifest" ]]; then
      # W-1: every line in $body was a mirror line (e.g. every source
      # gained a label) -- mirrors compute_manifest()'s own empty-tree
      # refusal so `generate` can't overwrite the manifest with nothing
      # and have the NEXT run vacuously pass against an empty baseline.
      echo "golden-baseline generate: every built file is under a declared index-mirror path -- refusing to write an empty manifest to ${MANIFEST_FILE}" >&2
      exit "$EXIT_DIFF"
    fi
    manifest_file_count=$(printf '%s' "$body_for_manifest" | wc -l)
    { manifest_header; printf '%s' "$body_for_manifest"; } >"$MANIFEST_FILE"
    echo "golden-baseline generate: manifest updated (${MANIFEST_FILE}, ${manifest_file_count} files, ${file_count} in the full build)"
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

  if compare_manifests "$old_body" "$body"; then
    echo "golden-baseline generate: OK, dist tree matches committed manifest (${file_count} files built, additive index-mirror paths excluded from that count's baseline)"
    return 0
  fi

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
