---
title: Changelog
---

# Changelog

`format_version`-keyed history of the wire format served at
[`/config.json`](./wire-format#config-json). Every entry here documents a
change to the URL shapes or field semantics in [Wire Format](./wire-format)
and [Entry Schema](./entry-schema); it does not track this documentation
site or `/data/catalog/**`, neither of which is wire contract.

## `format_version` 1 — 2026-07-17

Initial locked-observation wire format.

- `/config.json` — `{"format_version": 1}`, nothing else.
- `/p/<namespace>/<package>.json` — package root: human-governed fields
  (`name`, `repository`, `owners`, `status`, `deprecated_message`,
  `created`, `upstream`) plus bot-regenerated `desc` (nullable) and `tags`
  (map from every observed tag to `{content, observed, yanked?}`).
- `/p/<namespace>/<package>/o/sha256/<hex>.json` — immutable, package-local
  CAS observation objects: `platforms[{platform, digest}]`, no timestamps.
- Lock unit is the platform manifest digest, never the image-index digest.
- No `aliases` field — aliasing is emergent from equal `content` digests.
- Yank is a per-tag-row fact (`tags[tag].yanked`), not a package-level
  status; observation objects are never deleted, only pruned by
  render-time reachability when no tag references them.

Additive, same `format_version`:

- `/c/index.json` — enumeration index: a sorted map from every published
  bare `<namespace>/<package>` name to the exact-bytes digest of its package
  root, for whole-catalog sync via conditional GET + digest diff. A fourth
  frozen URL shape; names and digests only, never metadata. See
  [Wire Format](./wire-format#c-index-json-—-enumeration-index).
- `/p/<namespace>/<package>.json` gains an optional `superseded_by` field:
  bare `<namespace>/<package>` naming a successor package, human-governed,
  omitted or `null` when unset. Existing consumers already ignore unknown
  fields per the additive-evolution rule, so this costs nothing to add.

No prior `format_version` was ever served to a real client, so this entry
carries no migration notes. Two deltas exist against the placeholder
`config.json`/flat-pointer shape that predated it (`config.json` dropped a
`packages` prefix and `note` field; `/p/<ns>/<pkg>.json` changed from a flat
pointer to the root+CAS split) — both cost nothing, since no `ocx` client
had shipped against either yet. See
[`adr_locked_observation_index_format.md` D10](https://github.com/ocx-sh/index/blob/main/.claude/artifacts/adr_locked_observation_index_format.md#d10--wire-deltas-vs-the-current-live-placeholder)
for the full record.
