# Handoff: M-1 Republish — Registry Reality, Population Model, Open Decisions

Registry-scope handoff for the Phase 5 "M-1 handoff notes" item in
`plan_index_v1` (`.claude/state/plans/plan_index_v1.md`, gitignored — named here, not
linked). Supersedes that plan bullet's registry-scope content with what the Phase 4
seeding pilot (2026-07-16/17, branch `fix/registry-reality`) actually found: Phase 4
is blocked on M-1, not merely sequenced after it — `p/` cannot be seeded against the
registry as it exists today.

> **Owner decision (2026-07-17), supersedes the batch-seeding procedure below:**
> the index will NOT be batch-seeded via `seed-import`. Population happens the way
> the system is designed to run in steady state: (1) ocx/ocx-mirror get the
> prerequisite changes, (2) mirrors are patched and republished to public
> `ghcr.io/ocx-contrib/*`, (3) each package is then **announced gradually over
> time** through the `repository_dispatch` announce mechanism (bot opens the PR,
> G-04 human review at first claim). `seed-import` remains available as manual
> tooling only. Tracking issue:
> [ocx-sh/ocx-mirror#18](https://github.com/ocx-sh/ocx-mirror/issues/18). The
> "Index-Side Seeding Procedure" section below is retained as reference for
> manual use, not as the population plan.

## Metadata

**Date:** 2026-07-17
**Scope:** Registry migration (M-1) — current physical-storage state, what M-1 must
deliver, the index-side seeding procedure once it does, and the decisions still open
for the owner.
**Links:** [adr_locked_observation_index_format.md](./adr_locked_observation_index_format.md)
(ADR-1), [adr_namespace_policy.md](./adr_namespace_policy.md) (ADR-2, incl.
[Amendment A1](./adr_namespace_policy.md#amendment-a1-2026-07-17-first-party-use-of-brand-segments)),
[adr_index_bot_and_workflow_security.md](./adr_index_bot_and_workflow_security.md)
(ADR-4), [handover_from_ocx.md](./handover_from_ocx.md), plan Phase 4 ("Seeds ×44").

## Verified Current State

**Physical storage today: the legacy `ocx.sh` registry, not `ghcr.io/ocx-contrib`.**
`ghcr.io/ocx-contrib/*` repositories do not exist publicly. Mirror bots currently push
to the legacy self-hosted registry behind `ocx.sh/v2` (`handover_from_ocx.md`'s "42
public packages currently served from self-hosted Artifactory behind `ocx.sh/v2`
(nginx)"); the mirror bots' own config shape names that target explicitly
(`target: {registry: ocx.sh, repository: <name>}`). `ghcr.io/ocx-contrib/<pkg>` is the
one-way-door **destination** (`handover_from_ocx.md` One-Way Door #3, D6/D8 of
[adr_public_index_registry_indirection.md](./adr_public_index_registry_indirection.md)),
not the current state — the republish that gets bytes there is exactly what M-1 is.

**Probe method.** The same two-step anonymous-pull mechanism `adapters/ghcr.py`'s
`GhcrRegistry` implements: request an anonymous pull token
(`GET https://ghcr.io/token?service=ghcr.io&scope=repository:<path>:pull`, the
endpoint `_fetch_token` targets), then `GET /v2/<path>/tags/list`. Against
`ghcr.io/ocx-contrib/<pkg>` paths this returns **403 DENIED** at the token step, not
the `200` (or even a `404`) a genuinely public repository returns. A positive control —
the identical two-step probe against a known-public `ghcr.io` repository outside
`ocx-contrib` — returns `200`, confirming the probe mechanism itself is sound and the
403 reflects `ocx-contrib`'s repositories being absent or private, not a probe bug.
This refines [research_ghcr_constraints.md](./research_ghcr_constraints.md) §1, which
had only observed `403` for anonymous **push/delete**-scope requests; the pilot found
the same `403 DENIED` also on an anonymous **pull**-scope request against a
missing/private repository — untested in the original research because
`ocx-contrib` wasn't populated at the time.

**Consequence for the bot, not a bug:** `core/validate_entry.py`'s
`REPOSITORY_HOST_ALLOWLIST` is `{"ghcr.io"}` only (G-03). `check_repository_allowlisted`
rejects any `oci://ocx.sh/...` repository value before any network call. `seed-import`
therefore cannot ingest a legacy-registry repository at all, today, by design — this is
G-03 (anti-squat/anti-exfil guard) doing exactly what it is supposed to do. The fix is
M-1's republish, not loosening the allowlist.

## What M-1 Must Do (ocx-mirror scope, human-gated)

1. Republish every seed package's bytes to `ghcr.io/ocx-contrib/<pkg>`, batched by
   namespace with bounded concurrency (`handover_from_ocx.md` Migration Gates).
2. Publish with **public** visibility per repository — the anonymous-pull probe above
   is the seeding procedure's own precondition (`check_repository_allowlisted` +
   `observe()` both require anonymous reads to succeed).
3. Embed the current canonical `ocx.sh/<namespace>/<package>` identifier in each
   published manifest (D6 of `adr_public_index_registry_indirection.md`: "index entry
   name must equal the identifier embedded in the manifest at the claimed physical
   repo → registry write access = ownership proof"; migration plan step 3's "clean
   republish, no dual-identifier compat"). The convention `adapters/ghcr.py`'s `probe_ownership`
   currently assumes — a `sh.ocx.name` manifest annotation carrying that identifier —
   is flagged **unconfirmed** against `ocx-mirror`'s actual publish behavior (ADR-4
   Risk 2, G-15's disposition table); confirm it against real `ocx-mirror` output as
   part of M-1, not after.
4. Gate = a recorded tag×platform parity matrix vs. the legacy registry plus an
   `ocx install <logical>` smoke pull per package. **`curl` returning `200` is
   explicitly not the gate** (`handover_from_ocx.md` Migration Gates, M-1).

Per-package, M-1 completion is what unblocks that package's index-side seeding below —
this can proceed package-by-package or namespace-by-namespace; it does not have to be
all-44-or-nothing, and the batch plan below assumes it will not be.

## Index-Side Seeding Procedure (once M-1 lands, per package)

`seed-import`'s `--mirror-yml` reader now understands two shapes: the original flat
`repository: oci://<host>/<path>` key, and the nested `target: {registry:,
repository:}` mapping real `ocx-contrib` mirror bots actually emit
(`cli/seed_import.py`'s `_resolve_repository`). If `mirror.yml` names a
`target.registry` that isn't on `REPOSITORY_HOST_ALLOWLIST` — the legacy `ocx.sh`
registry, pending M-1 — `_resolve_repository` hard-fails rather than guessing a
`ghcr.io/ocx-contrib/<pkg>` URI. `--repository` is the explicit escape hatch: it wins
over `mirror.yml` entirely, for seeding a package whose own `mirror.yml` still names
the pre-M-1 target.

Per package:

1. Obtain `CATALOG.md` (`---`-delimited frontmatter: `title`, `description`, optional
   comma-separated `keywords`, then the readme body), an optional `.svg`/`.png` logo,
   and `mirror.yml` (either shape above).
2. Run:
   ```
   uv run --project bot -- indexbot seed-import \
     --catalog-md <path>/CATALOG.md --mirror-yml <path>/mirror.yml [--logo <path>] \
     --owner-github <login> --owner-github-id <numeric-id> \
     [--namespace <ns> --package <pkg>] \
     [--repository oci://ghcr.io/ocx-contrib/<pkg>] \
     [--upstream-org <org> --upstream-repository-url <url> --upstream-disclaimer <text>]
   ```
   Pass `--repository` explicitly whenever `mirror.yml` still names the legacy
   `target.registry: ocx.sh` for that package (the normal case for a batch seeded
   ahead of that package's own mirror-bot config catching up to a completed M-1
   republish). `--owner-github`/`--owner-github-id` are required — `github_id` is
   mandatory per ADR-2 ND-8, not optional. `--upstream-*` populates ND-9's attribution
   object; required by ADR-2 review (G-04) for every non-first-party seed, omitted for
   first-party OCX packages. First-party packages under a reserved Brand segment
   (`ocx/cli`, `ocx/mirror`) additionally need `--allow-reserved-namespace`
   (`core/validate_entry.py`'s `RESERVED_BRAND_SEGMENTS` carve-out) — gated on
   [Amendment A1](./adr_namespace_policy.md#amendment-a1-2026-07-17-first-party-use-of-brand-segments)
   being accepted first (see Open Decisions below); passing the flag before
   acceptance is a mechanism, not a policy approval — reviewers must still reject the
   PR under ND-4 until the amendment lands.
3. `uv run --project bot -- indexbot validate p/<ns>/<pkg>.json` — online by default
   (omit `--offline`), so this also runs the G-15 network checks
   (`core/registry_checks.py`: digest-in-scope, ownership probe) against the
   now-public repository.
4. `task render:build` — full render pipeline (wrapper Markdown, `config.json`, `/p/`
   wire mirror, `/data/catalog/**`).
5. `task schema:validate:rendered` — schema-validates the rendered output tree
   (`config.json` against `schema/config.schema.json`; every rendered root against
   `schema/root.schema.json`; every CAS object against
   `schema/observation-object.schema.json`).
6. Open one PR per thematic batch (plan Phase 4: ~9 packages per batch, 5 batches;
   batch 5 = first-party + misc — start there, since it is the batch blocked on
   Amendment A1 rather than on M-1 alone, and surfaces that blocker earliest).
7. G-04 human review, mandatory — every seed is a `new-package` claim (added
   `p/*.json` path), never auto-merge. Reviewer validates vendor-identity fit (ND-1)
   per entry, on top of the mechanical gate `classify-pr`/`governance-check` already
   enforce.

## Bot Fixes Landing With This PR

Three changes to `indexbot` land in this PR — the first two are fixes for bugs the
pilot surfaced, the third is a seeding-flow addition that shipped alongside them:

1. **`adapters/ghcr.py`: unhandled 403 crash.** `GhcrRegistry._send` retried a `401`
   once (token refresh) and routed `429`/`5xx` through `core/backoff.py`'s
   `is_retryable_status` (which is `429` or `5xx` only, by design — `403` is neither);
   `_fetch_token` called `response.raise_for_status()` unconditionally. A `403`
   response from either the token endpoint or a `/v2/` call (verified state above) — a
   permanent, never-retryable condition — raised a bare `httpx.HTTPStatusError` that
   propagated up through `list_tags`/`get_manifest` → `core/observe.py`'s `observe()` →
   `seed-import`'s `run()`: an unhandled Python exception, not one of the bot's defined
   exit codes (`0`/`1`/`65`/`75`). Fixed: both call sites now raise `ValidationError`
   on a `403` (distinct from the `401`-retry dance, which can still succeed once a
   token is attached, and from `TransientError`, which implies retrying later might
   help), with a message naming the repository and stating it must exist and grant
   anonymous `:pull` before the bot can observe it.
2. **`--allow-reserved-namespace` tooling override.** Implements the enforcement half
   of ADR-2 [Amendment A1](./adr_namespace_policy.md#amendment-a1-2026-07-17-first-party-use-of-brand-segments):
   `check_namespace_not_reserved(package_id, *, allow_reserved: bool = False)` now
   narrows the blocked set to `RESERVED_NAMESPACE_SEGMENTS - RESERVED_BRAND_SEGMENTS`
   when `allow_reserved=True`; `RESERVED_BRAND_SEGMENTS` is exactly the four Brand
   values (`ocx`, `ocx-sh`, `ocx-contrib`, `ocx-rs`) — control-path and generic
   segments are never in the carve-out regardless of the flag. `--allow-reserved-namespace`
   is added to both `seed-import` and `validate`, **default-off** (`store_true`,
   default `False` — ND-4's unconditional reservation is what runs unless a caller
   opts in explicitly), and logs to stderr whenever used. This is the mechanism only;
   the policy question — whether a given brand claim should be *allowed* — is still
   G-04 human review plus Amendment A1's acceptance, neither of which the flag itself
   grants.
3. **`--mirror-yml`'s nested `target:` shape + `--repository` override.** Not part of
   the pilot's original bug list but landed alongside the two fixes above and directly
   relevant to seeding: `_parse_mirror_yml` now reads one level of nesting (real
   `ocx-contrib` mirrors emit `target: {registry:, repository:}`, not the flat
   `repository:` key `seed-import` originally assumed only). `_resolve_repository`
   hard-fails if `target.registry` isn't on `REPOSITORY_HOST_ALLOWLIST` rather than
   guessing the post-M-1 URI; `--repository` is the explicit override for seeding
   ahead of a package's own `mirror.yml` catching up. See "Index-Side Seeding
   Procedure" below for the resulting per-package flow.

## Open Decisions for the Owner

1. **M-1 execution timing.** Human-gated, `ocx-mirror` scope, entirely outside this
   repo. Index-side seeding (batches above) cannot start for a given package before
   that package's M-1 gate (tag×platform parity + smoke pull) passes.
2. **Amendment A1 sign-off.** [adr_namespace_policy.md § Amendment A1](./adr_namespace_policy.md#amendment-a1-2026-07-17-first-party-use-of-brand-segments)
   is PROPOSED, not accepted. `--allow-reserved-namespace` is a mechanism, not a policy
   decision — passing it today would technically let `ocx/cli`/`ocx/mirror` pass
   `check_namespace_not_reserved`, but doing so ahead of owner sign-off contradicts the
   amendment it implements; no batch in the seeding plan should pass it until the owner
   accepts A1, and G-04 review should reject any PR that does.
3. **Owner identity on seed roots.** Every seed's `owners[]` entry requires a numeric
   `github_id`, mandatory per ADR-2 ND-8. Proposal, **not verified against a live
   GitHub API call in this document** — the owner should confirm before it is used
   across 44 `--owner-github`/`--owner-github-id` invocations: GitHub login
   `michael-herwig`, id `3511590`, as the initial claiming owner for every seed root.

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-17 | Claude (docs) | Initial handoff — Phase 4 pilot findings, M-1 requirements, seeding procedure, open decisions. |
