#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# smoke-test.sh — post-deploy smoke test for the OCX public index.
#
# Usage: scripts/smoke-test.sh [BASE_URL] [--allow-empty] [--root NS/PKG]
#
#   BASE_URL        Index base URL (default: https://index.ocx.sh)
#   --allow-empty   Exit 0 when no /p/ root is discoverable (pre-seed state,
#                    before Phase 4's 44 seeds land). Scoped ONLY to the
#                    digest-chain section — all other checks (including
#                    data/catalog/catalog.json, which @ocx-sh/catalog's
#                    view-model emitter always emits at build time, even
#                    pre-seed as "packages": []) always run and always
#                    contribute to the exit code, --allow-empty or not.
#   --root NS/PKG   Explicit sample package id to digest-chain-verify
#                    (default: auto-discovered from the local p/ tree)
#
# Checks: config.json (200, ETag, Cache-Control cache-rule guard,
# format_version), conditional GET (If-None-Match -> 304), c/index.json
# (200, ETag) with its own conditional GET (If-None-Match -> 304), a sample
# root's digest chain (root tags[].content -> image index object ->
# recomputed sha256) plus its /p/** response carrying
# Content-Security-Policy: sandbox (W3 — the only thing standing between a
# mirrored hostile o/sha256/<hex>.svg and stored XSS on this origin; same
# pre-seed gating as the rest of the digest-chain section, since there is no
# /p/ URL to probe before Phase 4 seeds land), data/catalog/catalog.json
# (200, valid JSON, has a
# "packages" key — @ocx-sh/catalog's view-model emitter always emits this
# tree at build time, even pre-seed as "packages": [], so a non-200/
# invalid-shape here is always a real failure, never tolerated by
# --allow-empty), catalog "/" (200, text/html), "/docs/"
# (200). Every fetch is wrapped in a bounded retry (3 attempts, 5s apart) to
# absorb CDN warm-up, plus a run-wide ~2 min window in which a 404 is retried
# as "deploy not propagated to the edge yet" rather than "asset absent".
#
# Exit codes (independent of indexbot's sysexits contract in
# adr_index_bot_and_workflow_security.md BD-2 — this is a bash ops tool, not
# the Python bot):
#   0  all checks passed (or pre-seed digest-chain gap tolerated via --allow-empty)
#   1  HTTP fetch returned an unexpected status
#   2  Cache-Rule guard violated (long max-age on a *.json response)
#   3  JSON parse / schema-shape failure (malformed JSON, format_version mismatch)
#   4  digest-chain integrity failure (computed sha256 != claimed digest)
#   5  no /p/ root discoverable and --allow-empty was not passed

readonly EXIT_OK=0
readonly EXIT_HTTP=1
readonly EXIT_CACHE=2
readonly EXIT_SCHEMA=3
readonly EXIT_DIGEST=4
readonly EXIT_NO_ROOT=5

readonly MAX_ATTEMPTS=3
readonly RETRY_SLEEP=5
readonly MAX_CACHE_SECONDS=60

# How far into the run a 404 may still mean "not propagated yet" rather than
# "absent". Anchored to script start, which in CI is seconds after the deploy
# job finished, so it measures Cloudflare Pages propagation -- the thing that
# actually races here. One budget shared by every fetch (bash $SECONDS), so a
# wholly-missing site costs ~2 min in total, not ~2 min per asset.
readonly NOT_FOUND_DEADLINE=120

# Basic ns/pkg shape guard for --root / discovered values before they are
# spliced into a URL. NOT the authoritative package-id grammar — that regex
# is owned by adr_namespace_policy.md ND-3 and lives in the bot
# (core/validate_payload.py PACKAGE_ID_RE). This is a cheap defense-in-depth
# check, not a duplicate of that contract.
readonly ROOT_PKG_RE='^[a-z0-9]([a-z0-9-]*[a-z0-9])?/[a-z0-9][a-z0-9._-]*$'

readonly -a CURL_BASE_OPTS=(-sS -L --connect-timeout 10 --max-time 20 -A "ocx-index-smoke-test/1.0")

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

BASE_URL="https://index.ocx.sh"
ALLOW_EMPTY=0
ROOT_PKG=""
CONFIG_ETAG=""
C_INDEX_ETAG=""
WORKDIR=""

RESULTS=()
OVERALL_EXIT=$EXIT_OK

usage() {
  cat <<'EOF'
Usage: smoke-test.sh [BASE_URL] [--allow-empty] [--root NS/PKG]

  BASE_URL        Index base URL (default: https://index.ocx.sh)
  --allow-empty   Exit 0 when no /p/ root is discoverable (pre-seed state)
  --root NS/PKG   Explicit sample package id to digest-chain-verify
                  (default: auto-discovered from the local p/ tree)
EOF
}

log() { printf '[smoke] %s\n' "$*" >&2; }

record() { # name status detail
  RESULTS+=("$1|$2|$3")
  log "$2: $1 -- $3"
}

pass() { record "$1" "PASS" "$2"; }
skip() { record "$1" "SKIP" "$2"; }

fail() { # name detail exit_code
  record "$1" "FAIL" "$2"
  local code="$3"
  if ((code > OVERALL_EXIT)); then
    OVERALL_EXIT=$code
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

header_value() { # headers_file name
  # ponytail: grep exits 1 on no match; pipefail would propagate that through
  # set -e on the caller's assignment line without this trailing `|| true`.
  grep -i "^${2}:" "$1" 2>/dev/null | tail -n1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r\n' || true
}

# Bounded retry around every fetch, for CDN warm-up right after deploy. Two
# retryable cases, each with its own bound; anything else is definitive and
# returns immediately.
#
#   000 / 5xx  transient — MAX_ATTEMPTS attempts, RETRY_SLEEP apart.
#   404        an asset added by *this* deploy that has not reached the edge
#              yet. Retried until NOT_FOUND_DEADLINE seconds into the run,
#              then reported as the 404 it is. Observed on run 30150305262:
#              /p/<ns>/<pkg>.json 404'd ~1 min after deploy on the very first
#              run that had a p/ root to check, and served 200 later — the
#              deploy was fine, the check raced it.
#
# No check in this script ever expects a 404, so retrying it weakens no
# assertion: a genuinely absent asset still fails, just later. Retries go to
# the canonical URL, no cache-buster, because a negative-cached 404 is not the
# failure mode here: Cloudflare does not cache JSON by default (.json is not
# in its default cached-extension list), so the 3 min negative-cache TTL it
# applies to 404/410 never reaches these paths. That default is the
# load-bearing part and it is Cloudflare's, not ours — the repo's "never
# enable CDN caching for *.json on the index zone" rule (README.md,
# CLAUDE.md, .claude/rules/product-context.md) says we must not override it,
# but that rule is a dashboard convention with nothing enforcing it in code;
# check_config's cache-rule guard is the only automated tripwire, and it
# watches config.json alone. If a Cache Rule ever does land on *.json, fix the
# rule — cache-busting here would only hide it behind a URL no client uses.
# ponytail: fixed sleep, no backoff curve — bump if warm-up proves longer.
fetch() { # url body_file headers_file [curl-args...]
  local url="$1" body="$2" headers="$3"
  shift 3
  local attempt=0 status
  while :; do
    attempt=$((attempt + 1))
    status=$(curl "${CURL_BASE_OPTS[@]}" -o "$body" -D "$headers" -w '%{http_code}' "$@" "$url") || status=""
    status=${status:-000}
    if [[ "$status" != "000" && "$status" != 5* && "$status" != "404" ]]; then
      printf '%s' "$status"
      return 0
    fi
    log "attempt ${attempt} for ${url} returned status=${status} (${SECONDS}s into the run)"
    if [[ "$status" == "404" ]]; then
      ((SECONDS < NOT_FOUND_DEADLINE)) || break
    else
      ((attempt < MAX_ATTEMPTS)) || break
    fi
    sleep "$RETRY_SLEEP"
  done
  printf '%s' "$status"
}

check_config() {
  local body="${WORKDIR}/config.body" headers="${WORKDIR}/config.headers" status
  status=$(fetch "${BASE_URL}/config.json" "$body" "$headers")
  if [[ "$status" != "200" ]]; then
    fail "config.json" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
    skip "config.json ETag" "config.json fetch did not return 200"
    skip "config.json cache-rule" "config.json fetch did not return 200"
    skip "config.json format_version" "config.json fetch did not return 200"
    return
  fi
  pass "config.json" "HTTP 200"

  CONFIG_ETAG=$(header_value "$headers" "etag")
  if [[ -z "$CONFIG_ETAG" ]]; then
    fail "config.json ETag" "no ETag header present" "$EXIT_HTTP"
  else
    pass "config.json ETag" "$CONFIG_ETAG"
  fi

  local cache_control max_age
  cache_control=$(header_value "$headers" "cache-control")
  if [[ "$cache_control" =~ max-age=([0-9]+) ]]; then
    max_age="${BASH_REMATCH[1]}"
    if ((max_age > MAX_CACHE_SECONDS)); then
      fail "config.json cache-rule" "Cache-Control max-age=${max_age} exceeds ${MAX_CACHE_SECONDS}s guard" "$EXIT_CACHE"
    else
      pass "config.json cache-rule" "max-age=${max_age} (<= ${MAX_CACHE_SECONDS}s)"
    fi
  else
    pass "config.json cache-rule" "no max-age directive (Cache-Control: ${cache_control:-<absent>})"
  fi

  if jq -e '.format_version == 1 and .name_segments == 2' "$body" >/dev/null 2>&1; then
    pass "config.json format_version" "format_version == 1, name_segments == 2"
  else
    fail "config.json format_version" "expected format_version == 1 and name_segments == 2" "$EXIT_SCHEMA"
  fi
}

check_conditional_get() {
  if [[ -z "$CONFIG_ETAG" ]]; then
    skip "conditional GET" "no ETag from config.json check"
    return
  fi
  local body="${WORKDIR}/config-cond.body" headers="${WORKDIR}/config-cond.headers" status attempt
  # A 200 here right after a deploy can be edge-propagation flap (the colo
  # served two deployments between our two requests — observed on the first
  # live render-deploy run). fetch() only retries 000/5xx, so retry the
  # 200-instead-of-304 case explicitly, re-reading the current ETag each time.
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    status=$(fetch "${BASE_URL}/config.json" "$body" "$headers" -H "If-None-Match: ${CONFIG_ETAG}")
    if [[ "$status" == "304" ]]; then
      pass "conditional GET" "If-None-Match -> 304"
      return
    fi
    if [[ "$status" == "200" && $attempt -lt $MAX_ATTEMPTS ]]; then
      CONFIG_ETAG=$(header_value "$headers" "etag")
      log "conditional GET attempt ${attempt}/${MAX_ATTEMPTS}: got 200 (propagation flap?), retrying with current ETag ${CONFIG_ETAG}"
      sleep "$RETRY_SLEEP"
      continue
    fi
    break
  done
  fail "conditional GET" "expected 304, got ${status}" "$EXIT_HTTP"
}

check_c_index() {
  local body="${WORKDIR}/c-index.body" headers="${WORKDIR}/c-index.headers" status
  status=$(fetch "${BASE_URL}/c/index.json" "$body" "$headers")
  if [[ "$status" != "200" ]]; then
    fail "c/index.json" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
    skip "c/index.json ETag" "c/index.json fetch did not return 200"
    return
  fi
  pass "c/index.json" "HTTP 200"

  C_INDEX_ETAG=$(header_value "$headers" "etag")
  if [[ -z "$C_INDEX_ETAG" ]]; then
    fail "c/index.json ETag" "no ETag header present" "$EXIT_HTTP"
  else
    pass "c/index.json ETag" "$C_INDEX_ETAG"
  fi
}

check_c_index_conditional_get() {
  if [[ -z "$C_INDEX_ETAG" ]]; then
    skip "conditional GET (c/index.json)" "no ETag from c/index.json check"
    return
  fi
  local body="${WORKDIR}/c-index-cond.body" headers="${WORKDIR}/c-index-cond.headers" status attempt
  # Same edge-propagation-flap handling as check_conditional_get (commit
  # 73c5220): a 200 here right after a deploy can mean the colo served two
  # deployments between our two requests, so retry the 200-instead-of-304
  # case explicitly, re-reading the current ETag each time.
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    status=$(fetch "${BASE_URL}/c/index.json" "$body" "$headers" -H "If-None-Match: ${C_INDEX_ETAG}")
    if [[ "$status" == "304" ]]; then
      pass "conditional GET (c/index.json)" "If-None-Match -> 304"
      return
    fi
    if [[ "$status" == "200" && $attempt -lt $MAX_ATTEMPTS ]]; then
      C_INDEX_ETAG=$(header_value "$headers" "etag")
      log "conditional GET (c/index.json) attempt ${attempt}/${MAX_ATTEMPTS}: got 200 (propagation flap?), retrying with current ETag ${C_INDEX_ETAG}"
      sleep "$RETRY_SLEEP"
      continue
    fi
    break
  done
  fail "conditional GET (c/index.json)" "expected 304, got ${status}" "$EXIT_HTTP"
}

check_catalog_json() {
  local body="${WORKDIR}/catalog-json.body" headers="${WORKDIR}/catalog-json.headers" status
  status=$(fetch "${BASE_URL}/data/catalog/catalog.json" "$body" "$headers")
  if [[ "$status" != "200" ]]; then
    # render ALWAYS emits this tree, even pre-seed ("packages": []) -- a
    # non-200 here is never a pre-seed artifact, so it is never tolerated by
    # --allow-empty (unlike the digest-chain section below, which genuinely
    # has no output before Phase 4 seeds land).
    fail "data/catalog/catalog.json" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
    skip "data/catalog/catalog.json shape" "data/catalog/catalog.json fetch did not return 200"
    return
  fi
  pass "data/catalog/catalog.json" "HTTP 200"

  if ! jq -e . "$body" >/dev/null 2>&1; then
    fail "data/catalog/catalog.json shape" "invalid JSON" "$EXIT_SCHEMA"
    return
  fi
  if jq -e 'has("packages")' "$body" >/dev/null 2>&1; then
    pass "data/catalog/catalog.json shape" "has \"packages\" key"
  else
    fail "data/catalog/catalog.json shape" "valid JSON but missing \"packages\" key" "$EXIT_SCHEMA"
  fi
}

discover_root() {
  if [[ -n "$ROOT_PKG" ]]; then
    return 0
  fi
  # ponytail: discovery reads the local git-tracked p/ tree (this script runs
  # from a repo checkout in CI) — there is no remote catalog-manifest
  # endpoint to enumerate packages yet, and the live Pages placeholder
  # currently 200s on every path (SPA fallback), which makes blind remote
  # probing for "does /p/ exist" unsafe. Add remote discovery via
  # /data/catalog/index.json once WP2-F's render pipeline ships it.
  if [[ -d "${REPO_ROOT}/p" ]]; then
    local sample
    sample=$(find "${REPO_ROOT}/p" -mindepth 2 -maxdepth 2 -type f -name '*.json' 2>/dev/null | sort | head -n1)
    if [[ -n "$sample" ]]; then
      ROOT_PKG=${sample#"${REPO_ROOT}"/p/}
      ROOT_PKG=${ROOT_PKG%.json}
    fi
  fi
}

check_digest_chain() {
  discover_root
  if [[ -z "$ROOT_PKG" ]]; then
    skip "digest-chain" "no /p/ root discoverable (pre-seed state)"
    log "===================================================================="
    log "NO /p/ ROOT DISCOVERABLE — pre-seed state (Phase 4 seeds not landed)"
    log "===================================================================="
    if [[ "$ALLOW_EMPTY" -ne 1 ]]; then
      fail "digest-chain (pre-seed gate)" "no root found and --allow-empty not passed" "$EXIT_NO_ROOT"
    fi
    return
  fi

  if [[ ! "$ROOT_PKG" =~ $ROOT_PKG_RE ]]; then
    fail "sample root (${ROOT_PKG})" "package id fails basic ns/pkg shape check" "$EXIT_SCHEMA"
    return
  fi

  local body="${WORKDIR}/root.body" headers="${WORKDIR}/root.headers" status
  status=$(fetch "${BASE_URL}/p/${ROOT_PKG}.json" "$body" "$headers")
  if [[ "$status" != "200" ]]; then
    fail "sample root (${ROOT_PKG})" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
    return
  fi
  pass "sample root (${ROOT_PKG})" "HTTP 200"

  # W3: /p/${ROOT_PKG}.json is itself a /p/** response — reuse its already-
  # fetched headers rather than a second request. `_headers`'s block is
  # exact-value "sandbox" (mirror.ts renderHeaders), not a prefix a browser
  # would still honor as sandboxing if truncated, so this is an exact match.
  local csp
  csp=$(header_value "$headers" "content-security-policy")
  if [[ "$csp" == "sandbox" ]]; then
    pass "sample root (${ROOT_PKG}) CSP" "Content-Security-Policy: sandbox"
  else
    fail "sample root (${ROOT_PKG}) CSP" "expected Content-Security-Policy: sandbox on /p/**, got: ${csp:-<absent>}" "$EXIT_HTTP"
  fi

  if ! jq -e . "$body" >/dev/null 2>&1; then
    fail "sample root (${ROOT_PKG}) parse" "invalid JSON" "$EXIT_SCHEMA"
    return
  fi
  pass "sample root (${ROOT_PKG}) parse" "valid JSON"

  local digests
  digests=$(jq -r '(.tags // {}) | to_entries[].value.content' "$body" | sort -u)
  if [[ -z "$digests" ]]; then
    pass "digest-chain (${ROOT_PKG})" "no tags to verify"
    return
  fi

  local digest hex obj_body obj_headers obj_status computed all_ok=1
  while IFS= read -r digest; do
    if [[ -z "$digest" ]]; then
      continue
    fi
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      fail "digest-chain (${ROOT_PKG}) ${digest}" "malformed content digest" "$EXIT_SCHEMA"
      all_ok=0
      continue
    fi
    hex=${digest#sha256:}
    obj_body="${WORKDIR}/obj-${hex}.body"
    obj_headers="${WORKDIR}/obj-${hex}.headers"
    obj_status=$(fetch "${BASE_URL}/p/${ROOT_PKG}/o/sha256/${hex}.json" "$obj_body" "$obj_headers")
    if [[ "$obj_status" != "200" ]]; then
      fail "digest-chain (${ROOT_PKG}) ${digest}" "image index HTTP ${obj_status}" "$EXIT_HTTP"
      all_ok=0
      continue
    fi
    computed=$(sha256_of "$obj_body")
    if [[ "$computed" != "$hex" ]]; then
      fail "digest-chain (${ROOT_PKG}) ${digest}" "sha256 mismatch: computed ${computed}" "$EXIT_DIGEST"
      all_ok=0
    fi
  done <<<"$digests"

  if [[ "$all_ok" -eq 1 ]]; then
    pass "digest-chain (${ROOT_PKG})" "all image indices verified"
  fi
}

check_catalog() {
  local body="${WORKDIR}/catalog.body" headers="${WORKDIR}/catalog.headers" status ctype
  status=$(fetch "${BASE_URL}/" "$body" "$headers")
  if [[ "$status" != "200" ]]; then
    fail "catalog /" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
    return
  fi
  ctype=$(header_value "$headers" "content-type")
  if [[ "$ctype" == text/html* ]]; then
    pass "catalog /" "HTTP 200, Content-Type: ${ctype}"
  else
    fail "catalog /" "expected text/html, got Content-Type: ${ctype:-<absent>}" "$EXIT_HTTP"
  fi
}

check_docs() {
  local body="${WORKDIR}/docs.body" headers="${WORKDIR}/docs.headers" status
  status=$(fetch "${BASE_URL}/docs/" "$body" "$headers")
  if [[ "$status" == "200" ]]; then
    pass "docs /docs/" "HTTP 200"
  else
    fail "docs /docs/" "expected HTTP 200, got ${status}" "$EXIT_HTTP"
  fi
}

print_summary() {
  local r name status detail
  printf '\n%-40s %-6s %s\n' "CHECK" "STATUS" "DETAIL"
  printf '%s\n' "------------------------------------------------------------------------"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r name status detail <<<"$r"
    printf '%-40s %-6s %s\n' "$name" "$status" "$detail"
  done
  echo
  if [[ "$OVERALL_EXIT" -eq 0 ]]; then
    log "smoke test OK (exit 0)"
  else
    log "smoke test FAILED (exit ${OVERALL_EXIT})"
  fi
}

parse_args() {
  while (($#)); do
    case "$1" in
      --allow-empty)
        ALLOW_EMPTY=1
        shift
        ;;
      --root)
        if [[ $# -lt 2 ]]; then
          echo "smoke-test.sh: --root requires a value" >&2
          exit "$EXIT_HTTP"
        fi
        ROOT_PKG="$2"
        shift 2
        ;;
      --root=*)
        ROOT_PKG="${1#*=}"
        shift
        ;;
      -h | --help)
        usage
        exit "$EXIT_OK"
        ;;
      --*)
        echo "smoke-test.sh: unknown option: $1" >&2
        usage >&2
        exit "$EXIT_HTTP"
        ;;
      *)
        BASE_URL="$1"
        shift
        ;;
    esac
  done
  BASE_URL="${BASE_URL%/}"
}

main() {
  parse_args "$@"

  if ! command -v curl >/dev/null 2>&1; then
    echo "smoke-test.sh: curl is required" >&2
    exit "$EXIT_HTTP"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "smoke-test.sh: jq is required" >&2
    exit "$EXIT_HTTP"
  fi

  WORKDIR=$(mktemp -d)
  trap 'rm -rf "$WORKDIR"' EXIT

  log "target: ${BASE_URL} (allow-empty=${ALLOW_EMPTY})"

  check_config
  check_conditional_get
  check_c_index
  check_c_index_conditional_get
  check_catalog_json
  check_digest_chain
  check_catalog
  check_docs

  print_summary
  exit "$OVERALL_EXIT"
}

main "$@"
