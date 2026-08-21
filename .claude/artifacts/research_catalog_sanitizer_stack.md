# Research — Build-Time Sanitization Stack for Third-Party README/SVG Content

Date: 2026-08-21 · Axis: technology · For: `@ocx-sh/catalog` extraction (hex-plan run)
Worker: sonnet researcher; synthesis: session orchestrator.

## Recommendation

**DOMPurify 3.x (pin ≥3.3.2, never 2.x) + jsdom** as the single sanitizer for both
README HTML (`USE_PROFILES: {html: true}`) and SVG logos (`{svg: true}`).
Invoke once, as post-processing on the **final rendered HTML string** (markdown-it
gives no mid-pipeline seam; hooking renderer rules leaves plugin-injected HTML
unseen). Never inline third-party SVG into the DOM — `<img src>` only, always,
as a sanitizer-bug-independent second layer.

Rejected:
- **sanitize-html** — three 2026 CVEs, one critical 9.3 (CVE-2026-44990 `xmp`
  bypass; CVE-2026-53606 `javascript:` URIs via `action`/`formaction`/`data`/
  `poster`; CVE-2026-40186 entity-encoded XSS). Smaller maintenance surface.
- **rehype-sanitize** — best-in-class GitHub-fidelity default schema, but
  hast-tree model; VitePress is markdown-it, not remark/rehype
  (vuejs/vitepress#4615 unresolved). Would drag a parallel parser stack in.
- **Rasterize SVG → PNG** — YAGNI; only revisit if CSS-driven logo recoloring
  becomes a design need.

## Implementation notes

- DOMPurify is not bulletproof either: CVE-2026-0540 / CVE-2025-15599
  (`SAFE_FOR_XML` regex bypass via `noscript`/`xmp`/`noembed`/`noframes`/
  `iframe` rawtext elements) — 2.x branch never patched, hence the ≥3.3.2 pin.
  The differentiator is Cure53 patch velocity, not immunity → defense in depth.
- GFM fidelity tax: task-list checkboxes need manual
  `ADD_TAGS`/`ADD_ATTR` (`<input type=checkbox disabled>`) — DOMPurify has no
  GFM awareness.
- Shiki dual-theme mode emits inline `style="--shiki-light:…;--shiki-dark:…"`
  on `pre`/`span`. A blanket `style` strip silently kills highlighting; add a
  `uponSanitizeAttribute` hook regex-restricting `style` values instead.
  Derive the allowlist from one real `md.render()` sample, not guesswork.
- jsdom over linkedom: cold low-QPS build path; DOMPurify's suite tests
  against jsdom.

## Finding against OUR wire layout (orchestrator synthesis)

Sanitized-or-not, an SVG served at a directly navigable `image/svg+xml` URL
executes scripts on direct navigation. Our CAS desc blobs are served **verbatim
by contract** at `/p/<…>/o/sha256/<hex>.svg` — bytes cannot be sanitized
without forging digests. Mitigation therefore lives at the *serving* layer:
`_headers` rule (CSP `sandbox` / script-less) on CAS paths of every
catalog/mirror deploy. Carried into the extraction plan as a work item; also a
candidate amendment to BD-4 hygiene docs before Phase-4 seed data lands.

## Sources

- rehypejs/rehype-sanitize (schema + sanitize-before-highlight guidance)
- npm: dompurify · cure53/DOMPurify · npmtrends dompurify-vs-sanitize-html
- CVEs: CVE-2026-44990 (SentinelOne), CVE-2026-53606 (GitLab advisories),
  CVE-2026-40186 (Snyk), GHSA-v2wj-7wpq-c8vv / GHSA-v8jm-5vwx-cfxm (DOMPurify)
- vuejs/vitepress#4615 (markdown-it is fixed engine)
- W3C webappsec archive 2014Apr/0035 (SVG-in-`<img>` script inertness)
- vercel-labs/markdown-sanitizers — adjacent LLM-exfil threat model, not this
  surface; worth tracking
