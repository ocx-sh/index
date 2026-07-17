# Decision Log — 2026-07-16 Design Discussion

<!--
Narrative record, not an ADR: chronological question → alternatives → conclusion
for the design discussion that produced ADR-1 through ADR-4. Each thread below
closes into exactly one owning ADR; the ADRs carry the normative schema/contract
text, this log carries the "why we ended up there" reasoning and the path not
taken.
-->

## Metadata

**Date:** 2026-07-16
**Participants:** Michael Herwig (owner) + Claude design swarm
**Scope:** Locked-observation index format, canonical tags, file granularity,
aliasing, `__ocx.desc`, `config.json` shape, CAS digest verification, namespace
policy, catalog/docs stack, bot/CI security posture.
**Plan:** `plan_index_v1` (`.claude/state/plans/plan_index_v1.md`, gitignored —
named here, not linked)

## Context

The 2026-07-16 session picked up bootstrap-phase design (six research artifacts,
three explorer reports, three plan-agent slices already on the table) and had to
settle the shape of the locked-observation index format before Phase 1
(schemas, bot scaffold) could start. A concurrently open ocx issue,
[ocx#215](https://github.com/ocx-sh/ocx/issues/215), forced the first and most
consequential question: what does a *lock* record when multi-platform OCI
pushes are non-atomic? Everything else in this log follows from, or was
resolved alongside, that answer.

## 1. What does the index actually lock?

**Question raised.** The public index was going to embed locked version data
per package — one platform-manifest set observed at announce time, per tag.
[ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076)
named the underlying inconsistency directly: multi-platform pushes are
non-atomic (per-platform read-modify-write image-index rewrites make index
digests churn during publish; rolling tags repoint by design). `ocx.lock` and
dependency locks already lock platform manifests. Did the index need to lock
the image-index digest, the platform-manifest digest set, or both?

**Alternatives weighed.**
- Lock the image-index digest — mirrors the naive "pin the multi-arch tag"
  intuition, but image indexes float by nature (platforms get added, rolling
  tags advance), so locking their digest bakes publish-time churn into the
  lock.
- Lock the set of `platform → manifest digest` pairs — platform manifests are
  pushed once, by digest, before any index rewrite; they are the stable
  primitive across the whole push.

**Conclusion.** Lock unit = the platform manifest, never the image index —
applied uniformly across the public index's observation objects, ocx's
index-lock, and `ocx.lock`. This resolves the inconsistency the issue named:
dependency locks and `ocx.lock` already locked manifests; the index-digest
locking that remained is migrated to the same unit rather than kept as a
second, inconsistent locking primitive.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 2. Canonical tags: from misread to opt-in flag

**Question raised.** An early pass toward the locked-observation format read
"canonical tag" as a build-tag concept (a human-assigned release tag).
[ocx#215](https://github.com/ocx-sh/ocx/issues/215#issuecomment-4996388076)
corrected this: a canonical tag is a digest-named tag (`sha256.<hex>`)
pointing at exactly the manifest its name encodes — it exists to pin a
manifest against GC, with naive untagged-child cleanup on GHCR being the
realistic failure case it guards against. Once the terminology was corrected,
the question became whether the index (or ocx more broadly) should *require*
canonical tags on every published platform manifest.

**Alternatives weighed.**
- Ecosystem-wide requirement — every publisher must tag every published
  platform manifest with its canonical tag.
- Opt-in publisher choice — canonical tagging available but not mandated.

**Conclusion.** Rejected as a required contract. It shifts burden onto every
publisher for failure modes that are rare and mostly self-inflicted (an index
push discarding an existing platform entry is a publisher bug; a build-tag
overwrite is a convention violation; aggressive retention tooling is
self-inflicted) — and index-side reconcile already detects dangling or
mutated digests regardless of whether canonical tags exist. Landed initially
as an opt-in `ocx package push --canonical-tag` flag on the ocx side: cheap
insurance, publisher's choice, out of this repo's scope but recorded as an
ocx follow-up. **Superseded 2026-07-17:** the ocx-side flag flipped to
default ON with an explicit `--no-canonical-tag` opt-out — still a pure
registry-side deletion safety net this index remains agnostic to, not a
change to this repo's scope. See ADR-1 Fork 4/D8.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 3. File granularity: one JSON per package, or split?

**Question raised.** The inherited design (`adr_public_index_registry_indirection.md`
D1/D12) sketched one small JSON file per package. That does not hold once
every observed tag needs its own platform-manifest observation: a single
per-package file would grow with tag history and churn its entire contents on
every commit, defeating CDN caching for content that rarely changes.

**Alternatives weighed.**
- Single flat per-package JSON, as originally sketched — simple, but couples
  a tiny amount of frequently-changing root state (which tag points where) to
  a growing amount of rarely-changing observation content (what a given
  observation actually contains).
- A root+CAS split — a tiny-forever mutable root file plus immutable,
  content-addressed observation objects.

**Conclusion.** Split chosen: `/p/<ns>/<pkg>.json` stays a tiny, mutable root
(name, owners, status, and a `tags` map from tag name to content digest);
`/p/<ns>/<pkg>/o/sha256/<hex>.json` holds immutable observation objects
addressed by content digest, with desc blobs alongside at
`/p/<ns>/<pkg>/o/sha256/<hex>.{md,svg,png}`. Path composition mirrors OCI's
own repository/digest addressing — REST-style, not a bespoke scheme. The root
stays small forever regardless of tag-history depth; CAS objects cache
indefinitely and are shared across tags with identical content (see §4).

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 4. Aliases field: proposed, rejected

**Question raised.** Should the root schema carry an explicit `aliases`
field recording that, say, `3.28`, `3`, and `latest` all resolve to the same
release?

**Alternatives weighed.**
- Explicit `aliases` array — requires a client reading the wire format to
  already understand ocx's cascade-tag convention (which tags are canonical,
  which are derived) to interpret which entries alias which.
- No aliases field; every tag listed on equal footing, aliasing left
  implicit.

**Conclusion.** Rejected by the owner. Every observed tag is listed in the
root's `tags` map, each pinned to its own content digest
(`{content, observed, yanked?}`); aliasing is emergent whenever two tags'
`content` digests are equal. No separate field, and no cascade-convention
knowledge is required to interpret the wire format — a client can determine
"these tags are the same release" from digest equality alone.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 5. `__ocx.desc` fate: retirement proposed, rejected

**Question raised.** With per-tag observation objects now holding real
content, should the floating `__ocx.desc` package-description tag be retired
in favor of baking description/keywords directly into manifest annotations?

**Alternatives weighed.**
- Retire `__ocx.desc`; move description/keywords into manifest annotations —
  simpler mental model (one source of truth per manifest) but makes
  description content image-specific and immutable per manifest.
- Keep `__ocx.desc` as a separate floating package-level tag.

**Conclusion.** Rejected by the owner. A package's description is
package-level, editable metadata — it should not require a new manifest push
to update, and should not be tied to any one platform manifest's immutable
content. `__ocx.desc` stays; the bot copies its content into the index CAS
(root's `desc {digest, title, description, keywords[], readme?, logo?}`
field — nullable, since `__ocx.desc` may be absent) whenever the tag's digest
changes. `keywords` are sourced separately, from the `sh.ocx.keywords`
manifest annotation.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 6. `config.json`: packages prefix dropped

**Question raised.** The inherited design (`adr_public_index_registry_indirection.md`
D12) sketched `config.json` as `format_version` + `endpoints`, later narrowed
in working drafts to `format_version` + a `packages` path-prefix key. Once the
URL-template idea behind that prefix was dropped — `/p/` paths are fixed and
out-of-band from `config.json`, not parametrized — the `packages` key had
nothing left to point at.

**Alternatives weighed.**
- Keep `packages` prefix + a `note` field, as sketched in working drafts.
- Drop everything except a format marker.

**Conclusion.** Both `packages` and `note` dropped. `config.json` is
`{"format_version": 1}` and nothing else. The field is named
`format_version`, not `version` — `version` is overloaded across the domain
(package versions, schema versions live alongside it), and OCI's own
`schemaVersion` field sets precedent for the more specific name.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md).

## 7. Package-local CAS + digest verification across publishers

**Question raised.** With observation objects and desc blobs content-addressed
under each package's own path, what stops one package's entry from pointing
at digests that were never actually observed at its own repository — whether
by bot bug or malicious PR?

**Alternatives weighed.** The discussion did not treat this as a single
either/or choice; it walked the full write→read path and assigned a check to
each stage rather than relying on any one layer alone.

**Conclusion.** Four independent layers, each closing a different gap:

1. The bot derives every digest from the entry's own repository by
   construction — it never accepts a digest from caller-supplied payload.
2. `validate` re-derives digests via a repository-scoped manifest HEAD before
   accepting a change, independent of what the bot claims.
3. The ocx client verifies the full content-digest chain at resolution time
   (root tag → content digest → observation object → manifest digest → OCI
   CAS).
4. Nightly reconcile is the backstop: it re-derives every entry from registry
   truth on a schedule and catches anything that slipped past the first
   three layers.

**Owning ADR:** ADR-1, [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)
(chain mechanics); ADR-4, [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
(bot/reconcile implementation).

## 8. Namespace model: vendor identity, not publisher

**Question raised.** `research_namespace_policy.md` weighed upstream-org
namespacing (`ocx.sh/kitware/cmake`) against publisher namespacing
(`ocx.sh/ocx-contrib/cmake`) for the 44 seed packages, given that the
inherited D6 ownership check (manifest identifier equals index name) is
satisfied by whoever pushes the manifest — not necessarily by the vendor
whose name appears in the namespace.

**Alternatives weighed.**
- Upstream/vendor identity (Option A) — recognizable to users, but D6 alone
  does not verify that the named vendor (e.g. Kitware) consented to the use
  of its name; real trademark/impersonation exposure.
- Publisher identity (Option B, e.g. `ocx-contrib`) — D6-honest, since the
  physical repository owner and the logical namespace owner are the same
  identity, but less discoverable and requires users to trust the curator
  rather than recognize the vendor. Research recommended this option.

**Conclusion.** Owner chose vendor identity over publisher identity — the
opposite of the research recommendation — clarifying that a namespace
represents vendor/business/project identity, not the hosting or publishing
entity. This is paired with a mandatory upstream-attribution field
(`upstream {org, repository_url?, disclaimer?}`) on the root object, which
directly addresses the trademark-exposure risk the research flagged for this
option. Separately, a privileged root/bare-name tier — the Docker Hub
`library` model, where curator-controlled packages ship without any
namespace prefix — was rejected: every package always has a two-segment
`<namespace>/<package>` name, so no tier gets opaque, un-auditable admission.
Namespace fit (does this namespace plausibly belong to this claimant) is
validated by a human reviewer at first-claim PR time.

**Owning ADR:** ADR-2, [`adr_namespace_policy.md`](./adr_namespace_policy.md).

## 9. Catalog/docs: VitePress reuse over mdBook

**Question raised.** Where does the human-facing catalog and documentation
site live, and what renders it? `research_docs_site.md` surveyed the space
and recommended a tool.

**Alternatives weighed.**
- mdBook — the research's recommendation: a single statically-linked binary,
  zero new language toolchain, thematic fit with crates.io/Cargo's own
  documentation tooling. Astro Starlight was also considered in research and
  set aside there as "a real option but spends a JS/Astro toolchain token
  this repo doesn't have."
- Reuse of the VitePress theme already built and paid for in the sibling
  ocx/website repo.

**Conclusion.** VitePress theme reuse chosen — this reverses the research's
mdBook recommendation in favor of the theme already built and already
familiar next door: the JS/Node toolchain token research wanted to avoid for
a fresh build is already spent by the sibling website repo, so reusing it
here is not a new cost. Docs live at `index.ocx.sh/docs`; the catalog lives
at the `index.ocx.sh` root. Both are explicitly outside the wire contract,
free to evolve, on a single Cloudflare Pages project alongside the
machine-facing index files.

**Owning ADR:** ADR-3, [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md).

## 10. Bot + CI posture

**Question raised.** The index bot is the sole write path into a public
package index, and its trigger surface (announce dispatch) is reachable by
third-party publisher input. What architecture and security posture does
that demand?

**Alternatives weighed.** Grounded in `research_python_bot_security.md`,
`research_python_bot_stack.md`, and `research_python_coverage_gate.md`: how
strict a coverage gate to enforce, how thin a runtime dependency footprint to
keep, and how to split trust between workflow jobs that see PR-head code and
jobs that write with elevated credentials.

**Conclusion.** A hard 100% branch-coverage gate (`fail_under=100`) on the
bot; a stdlib-only credential process (no third-party libraries touch
secrets); a privileged/unprivileged workflow split (the schema-validate job
runs unprivileged and never checks out PR-head code under
`pull_request_target`; the governance-gate job is the privileged one,
API-only); and a sysexits-style exit-code contract that workflows key off
directly — `0` success, `1` validation failure, `65` anomaly requiring a
human (never auto-healed), `75` transient failure with backoff exhausted.

**Owning ADR:** ADR-4, [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md).

## Resulting artifacts

- ADR-1 — [`adr_locked_observation_index_format.md`](./adr_locked_observation_index_format.md)
  (locked-observation index format: lock unit, root+CAS split, verifiability
  chain, emergent aliasing, `__ocx.desc`, `config.json`, canonical tags,
  digest verification)
- ADR-2 — [`adr_namespace_policy.md`](./adr_namespace_policy.md)
  (namespace model, reserved names, claim/dispute policy, upstream
  attribution)
- ADR-3 — [`adr_catalog_docs_colocation.md`](./adr_catalog_docs_colocation.md)
  (VitePress catalog + docs colocation on `index.ocx.sh`)
- ADR-4 — [`adr_index_bot_and_workflow_security.md`](./adr_index_bot_and_workflow_security.md)
  (bot architecture, exit-code contract, CI/workflow security posture)
- Plan — `plan_index_v1` (`.claude/state/plans/plan_index_v1.md`, gitignored)
  records these four ADRs as Phase 0 deliverables and carries the phase
  sequencing that depends on them.

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-16 | Michael + Claude | Initial record from design discussion (2026-07-16) |
| 2026-07-17 | Michael Herwig + Claude design swarm | Amendment: §2's canonical-tag conclusion noted as superseded — ocx-side flag flipped from opt-in to default-on with `--no-canonical-tag` opt-out (ocx#215 follow-up); see ADR-1 Fork 4/D8 |
