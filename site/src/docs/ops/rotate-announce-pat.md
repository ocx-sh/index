---
title: Rotate the Announce PAT
---

# Rotate the Announce PAT

Every namespace that announces via `repository_dispatch` (see
[Announce a Package](../how-to/announce-a-package)) authenticates with its
own fine-grained personal access token, scoped to `contents:read` +
`actions:dispatch` on `ocx-sh/index` — never a single shared org secret
across publishers. Rotating it is a publisher-side operation; `ocx-sh/index`
maintainers hold no copy of it.

## When to Rotate

- On a schedule (recommended: annually, or per your org's credential
  hygiene policy — fine-grained PATs support a maximum 1-year expiry).
- Immediately, if the token may have leaked (exposed in a log, a fork's CI
  run, a misconfigured secret scope).
- On personnel change, if the token was created under an individual
  account rather than a bot/machine account.

## Procedure

1. **Generate a new token.** In the publisher org/account that owns the
   namespace, create a new fine-grained PAT scoped to:
   - Repository access: `ocx-sh/index` only.
   - Permissions: `Contents: Read-only`, and the permission covering
     `repository_dispatch` triggers (`Actions: Read and write` in GitHub's
     fine-grained PAT UI covers dispatch triggering).
   - Expiry: set explicitly; do not use "no expiration".

2. **Store it as a secret in your own CI**, not in `ocx-sh/index` — the
   dispatch call always originates from the publisher's side. This doc uses
   `ANNOUNCE_PAT` as a placeholder secret name; use whatever your CI
   convention is.

3. **Update the CI step** that fires the announce dispatch (see
   [Announce a Package](../how-to/announce-a-package)) to reference the new
   secret. Trigger one announce run manually to confirm the new token
   works before revoking the old one.

4. **Revoke the old token** in GitHub's personal-access-token settings
   once the new one is confirmed working. Do not leave both live longer
   than the cutover window.

## Scope Discipline

- One PAT per registered namespace — a publisher that owns multiple
  namespaces does not need to share a single token across them, but a
  namespace's token MUST NOT be broader than `contents:read` +
  `actions:dispatch` on `ocx-sh/index`. It cannot write to the index
  directly; only the internal `index-write` GitHub Environment credential,
  held by `announce.yml`/`reconcile.yml`, can do that.
- If a namespace is deprecated or transferred (see
  [Namespace Policy](../reference/namespace-policy)), revoke its announce
  PAT rather than leaving it live with nothing to announce against.
