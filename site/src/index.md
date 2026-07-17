---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "OCX Index"
  text: "The public package index for OCX"
  tagline: Sparse HTTP index mapping ocx.sh/<namespace>/<package> to physical OCI registries — static JSON over HTTPS, no server, no database.
  actions:
    - theme: brand
      text: Read the Docs
      link: /docs/
    - theme: alt
      text: GitHub
      link: https://github.com/ocx-sh/index

# Feature-card icons are inline SVG strings (VitePress's default theme
# renders a plain-string `icon` via v-html — see
# node_modules/vitepress/dist/client/theme-default/components/VPFeature.vue)
# — hand-drawn/CC0-style geometric glyphs authored for this repo, not pulled
# from an icon library or a remote host (WP2-R; the alternative R2-hosted
# licensed-asset pipeline ocx-sh/ocx's website uses is documented, not used,
# here — see adr_catalog_docs_colocation.md).
features:
  - title: Sparse HTTP Index
    details: Static JSON over HTTPS — no server, no database. The crates.io sparse-index model.
    icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="24" height="24"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="14" y2="12"/><line x1="4" y1="18" x2="18" y2="18"/></svg>'

  - title: Content-Addressed
    details: Every observation, readme, and logo is stored and verified by SHA-256 digest — a full digest chain from root to registry blob.
    icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="24" height="24"><line x1="9" y1="4" x2="7" y2="20"/><line x1="17" y1="4" x2="15" y2="20"/><line x1="5" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="19" y2="15"/></svg>'

  - title: Vendor-Identity Namespaces
    details: Packages are namespaced under the real upstream vendor, reviewed at claim time, with attribution recorded on every entry.
    icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="24" height="24"><polygon points="3,4 14,4 21,12 14,20 3,20"/><circle cx="8" cy="12" r="1.5" fill="currentColor" stroke="none"/></svg>'

  - title: Wire-Stable Contract
    details: "/config.json and /p/** are a one-way door — additive only, format_version gates anything else."
    icon: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="24" height="24"><rect x="5" y="11" width="14" height="9" rx="1"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/><circle cx="12" cy="15" r="1.5" fill="currentColor" stroke="none"/></svg>'
---
