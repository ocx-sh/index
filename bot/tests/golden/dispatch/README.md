# Golden dispatch objects

Real OCI image indices, byte-exact, one per file, stored at
`sha256/<hex>.json` where `<hex>` is the sha256 of the file's own bytes --
the same CAS convention as `p/<ns>/<pkg>/o/sha256/<hex>.json` in a real
index tree (`adr_oci_index_only_dispatch.md` D1).

Both consumers read `expected_platforms.json`, not each other's code, for
"which descriptors count as platform-selection candidates": ocx's
`dispatch_conformance.rs` (WP-A6b) and the bot's `test_serializer_golden.py`.
That file also records where every byte in this directory came from.

## Never hand-edit

Editing a fixture directly changes its sha256, which breaks the CAS
invariant the filename encodes. Regenerate via a fresh capture (or, for
`attestation_descriptor`, by re-deriving from the same source manifests
named below) and update `expected_platforms.json` in the same commit.

## Vectors

| File (`sha256/<hex>`) | What it is | Provenance |
|---|---|---|
| `22af3b60…65a7cc3` | single-platform image index (linux/amd64 only) | The `linux/amd64` descriptor is real, copied from `ghcr.io/michael-herwig/ocx-e2e-hello:1.0.2` (see below). Wrapped alone in a fresh index with `artifactType` set and no `annotations` -- the exact shape `merge_platform_into_index` produces when wrapping a bare manifest for a first, single-platform push (`crates/ocx_lib/src/oci/client.rs:276-298`, `:294`). |
| `bce4d35f…9194f8c` | multi-platform image index: `linux/amd64`, `linux/arm64`, `darwin/arm64` | `linux/amd64` and `linux/arm64` descriptors: real, from the same `ocx-e2e-hello:1.0.2` capture. `darwin/arm64` descriptor: real, copied from `docker.io/docker/buildx-bin:latest` (registry-1.docker.io), a genuine multi-OS buildx-produced index -- digest/size/mediaType are the registry's own for that platform. |
| `2f1b78d3…d436f69d614` | index carrying an attestation descriptor (`platform: {"os":"unknown","architecture":"unknown"}`) **and** a descriptor with **no `platform` key at all**, plus `annotations` and `artifactType` | Load-bearing for ocx defect N-2 (`oci/index.rs:388`, `None => oci::Platform::any()` lets a platform-less descriptor satisfy every requirement) and N-15 (`Platform::from_image_index`'s `?` aborting `ocx index list --platforms`). The `linux/arm64` leaf and its `unknown/unknown` attestation-manifest sibling are both real, copied from `docker.io/moby/buildkit:latest`, a real `docker buildx build --provenance=true` output. The third descriptor is that same repository's real `linux/ppc64le` leaf (digest/size/mediaType unchanged) with its `platform` key **removed** -- no public registry response was found carrying a platform-less descriptor in the same fetch as an attestation one, so this one field removal is a deliberate construction, not a captured byte sequence; every value that remains is real. `annotations`/`artifactType` are the real values from the `ocx-e2e-hello:1.0.2` capture, reused here so this vector also exercises ADR R4 (stored verbatim, never rendered; `artifactType` is never inspected by the admission gate per OQ2). |
| `50e02438…3926ccb5ee1` | index carrying `annotations` and `artifactType`, fully real and byte-unmodified | `GET https://ghcr.io/v2/michael-herwig/ocx-e2e-hello/manifests/1.0.2` with `Accept: application/vnd.oci.image.index.v1+json`. Response `Docker-Content-Digest: sha256:50e02438d1d8e4968ad9a663d29185638931b2771e7e4f68cc9923926ccb5ee1` matches this file's own filename -- not just parsed and re-verified, the literal response body. Captured 2026-07-25. |

## Real captures this directory draws from

- `ghcr.io/michael-herwig/ocx-e2e-hello` tags `1.0.1`/`1.0`/`1`/`1.0.2`/`latest`
  all resolve to the same real, ocx-published two-platform index
  (`linux/amd64` + `linux/arm64`); `1.0.2`'s response is vector
  `50e02438…3926ccb5ee1` verbatim.
- `docker.io/docker/buildx-bin:latest` -- real multi-OS buildx index (source
  of the `darwin/arm64` descriptor).
- `docker.io/moby/buildkit:latest` -- real buildx index with provenance
  attestations (source of the `linux/arm64` leaf, its `unknown/unknown`
  attestation sibling, and the `linux/ppc64le` leaf reused platform-less).

## `expected_platforms.json`

One entry per vector: the digest, the file path, and the exact
`(platform, digest)` list a correct `select_best`/`_catalog_platforms`
implementation derives -- i.e. every descriptor that carries a `platform`
key whose `(os, architecture)` is not `("unknown", "unknown")`. For the
attestation vector this is a single entry (`linux/arm64`); neither the
attestation descriptor nor the platform-less one appears.
