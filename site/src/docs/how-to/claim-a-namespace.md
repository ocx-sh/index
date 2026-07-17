---
title: Claim a Namespace
---

# Claim a Namespace

Claiming a namespace is opening the PR that adds the **first**
`p/<namespace>/<package>.json` entry under it. There is no separate
reservation step — the first accepted claim PR is the claim.

## 1. Pick a Namespace and Package Name

Read [Namespace Policy](../reference/namespace-policy) first. In short: the
namespace names a real identity (an organisation, business, or project),
not a hosting location; it must fit the charset (`^[a-z0-9](?:-?[a-z0-9])*$`,
1–39 chars) and must not be on the reserved-segments list; the package
segment follows the OCI repository-component grammar, ≤100 chars.

## 2. Write the Entry

Add `p/<namespace>/<package>.json` conforming to
[`root.schema.json`](https://index.ocx.sh/schema/root.schema.json) (field
table: [Entry Schema](../reference/entry-schema)). At first claim you
typically populate:

- `name` — `ocx.sh/<namespace>/<package>`, matching the file's own path
- `repository` — `oci://<host>/<repo path>` of the physical mirror
- `owners` — at least one `{github, github_id}` pair
- `status` — `active`
- `deprecated_message` — `null`
- `created` — today's date
- `upstream` — required if the namespace names a real third-party vendor;
  omit only for OCX's own first-party namespaces
- `desc` — `null` until the bot's first announce/reconcile copies
  `__ocx.desc`, if the physical registry publishes one
- `tags` — `{}` if you are claiming ahead of the first announce, or
  populated by `indexbot seed-import` if this is a batch seed import

Open the PR. Do not hand-write `tags[*].content`/`observed` values — those
are bot-regenerated fields; a claim PR that also wants an initial tag set
populated should let an announce (or `seed-import`, for batch seeding) do
that work, not encode digests by hand.

## 3. Automated Checks

Two jobs run against the PR:

- **`schema-validate`** (unprivileged, runs against your PR's own content):
  JSON Schema conformance via `check-jsonschema`, plus semantic checks —
  `name` matches the path-derived logical name (G-02), `repository` host is
  allowlisted (G-03), neither namespace nor package segment is on the
  reserved list, digest fields (if any) are well-formed.
- **`governance-gate`** (privileged, API-diff only, never checks out your
  PR's code): classifies the PR. A new `p/*.json` file always gets the
  `new-package` label (G-04) and a red `governance/review-required` status —
  this never auto-resolves, regardless of how green `schema-validate` is.

## 4. Human Review

A maintainer reviews the PR for:

- **Namespace identity fit** — does the claimed namespace plausibly belong
  to the entity it names? This is not automatable and is the reviewer's
  primary judgment call.
- **`upstream` attribution present** where the namespace names a real
  third-party vendor, with a `disclaimer` if the mirror is unaffiliated.
- **`owners[].github_id`** present (mandatory) alongside the login.
- General entry sanity — `repository` actually points at the intended
  physical mirror, `status` is `active` for a new claim.

New-package PRs are never auto-merged, no matter how green the automated
checks are — a human approval is required every time.

## After Merge

The namespace is now claimed and immutable — there is no rename primitive.
Trigger your first [announce](./announce-a-package) to populate `tags` from
live registry state (or rely on the nightly reconcile to pick it up).
