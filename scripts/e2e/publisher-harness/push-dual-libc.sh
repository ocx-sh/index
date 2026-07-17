#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# push-dual-libc.sh -- hand-crafts and pushes a minimal two-platform OCI
# image index to $REGISTRY/$REPO:$TAG (env, set by push-package.yml). Both
# platforms are amd64/linux; they differ only in `os.features` (["glibc"]
# vs ["musl"]) -- a stand-in "dual-libc" artifact for the announce-revamp
# E2E sandbox, not a real runnable image. Config blob is shared between
# variants; only the layer content (and therefore each manifest's digest)
# differs. Layer content includes $TAG, so re-pushing the SAME tag is a
# no-op (identical digests, oras just re-pushes blobs/manifests the
# registry already has) while a NEW tag produces genuinely new digests --
# Phase 5 dispatches new tags through this to exercise indexbot's
# new-observation path.

: "${REGISTRY:?REGISTRY env var required}"
: "${REPO:?REPO env var required}"
: "${TAG:?TAG env var required}"

readonly TARGET="${REGISTRY}/${REPO}"

# Set by push_variant() for build_index() to read -- deliberately not
# `local`, this is this script's return channel for two scalars per variant.
GLIBC_DIGEST=""
GLIBC_SIZE=""
MUSL_DIGEST=""
MUSL_SIZE=""

# Global (not `local` to main): the EXIT trap fires after main() has already
# returned and popped its locals, so a `local workdir` would be unbound by
# the time the trap reads it under `set -u`.
WORKDIR=""
trap 'rm -rf "${WORKDIR}"' EXIT

push_variant() {
  local variant="$1" config_digest="$2" config_size="$3"
  local layer_file="layer-${variant}.bin"
  local manifest_file="manifest-${variant}.json"
  local layer_digest layer_size manifest_digest manifest_size

  # Plain text, not an actual tar, despite the layer.v1.tar mediaType below --
  # fine here, nothing ever extracts this dummy artifact.
  printf '%s payload %s\n' "${variant}" "${TAG}" >"${layer_file}"
  layer_digest=$(sha256sum "${layer_file}" | cut -d' ' -f1)
  layer_size=$(wc -c <"${layer_file}")
  oras blob push "${TARGET}@sha256:${layer_digest}" "${layer_file}"

  jq -n \
    --arg config_digest "sha256:${config_digest}" \
    --argjson config_size "${config_size}" \
    --arg layer_digest "sha256:${layer_digest}" \
    --argjson layer_size "${layer_size}" \
    '{
      schemaVersion: 2,
      mediaType: "application/vnd.oci.image.manifest.v1+json",
      config: {mediaType: "application/vnd.oci.image.config.v1+json", digest: $config_digest, size: $config_size},
      layers: [{mediaType: "application/vnd.oci.image.layer.v1.tar", digest: $layer_digest, size: $layer_size}]
    }' >"${manifest_file}"
  manifest_digest=$(sha256sum "${manifest_file}" | cut -d' ' -f1)
  manifest_size=$(wc -c <"${manifest_file}")
  oras manifest push --media-type application/vnd.oci.image.manifest.v1+json \
    "${TARGET}@sha256:${manifest_digest}" "${manifest_file}"

  case "${variant}" in
    glibc) GLIBC_DIGEST="${manifest_digest}"; GLIBC_SIZE="${manifest_size}" ;;
    musl) MUSL_DIGEST="${manifest_digest}"; MUSL_SIZE="${manifest_size}" ;;
  esac
}

build_and_push_index() {
  jq -n \
    --arg glibc_digest "sha256:${GLIBC_DIGEST}" --argjson glibc_size "${GLIBC_SIZE}" \
    --arg musl_digest "sha256:${MUSL_DIGEST}" --argjson musl_size "${MUSL_SIZE}" \
    --arg source "https://github.com/michael-herwig/ocx-e2e-publisher" \
    '{
      schemaVersion: 2,
      mediaType: "application/vnd.oci.image.index.v1+json",
      manifests: [
        {mediaType: "application/vnd.oci.image.manifest.v1+json", digest: $glibc_digest, size: $glibc_size,
         platform: {architecture: "amd64", os: "linux", "os.features": ["glibc"]}},
        {mediaType: "application/vnd.oci.image.manifest.v1+json", digest: $musl_digest, size: $musl_size,
         platform: {architecture: "amd64", os: "linux", "os.features": ["musl"]}}
      ],
      annotations: {"org.opencontainers.image.source": $source}
    }' >index.json
  oras manifest push --media-type application/vnd.oci.image.index.v1+json \
    "${TARGET}:${TAG}" index.json
}

main() {
  WORKDIR=$(mktemp -d)
  cd "${WORKDIR}"

  local config_digest config_size
  printf '{"architecture":"amd64","os":"linux","config":{},"rootfs":{"type":"layers","diff_ids":[]}}' >config.json
  config_digest=$(sha256sum config.json | cut -d' ' -f1)
  config_size=$(wc -c <config.json)
  oras blob push "${TARGET}@sha256:${config_digest}" config.json

  push_variant glibc "${config_digest}" "${config_size}"
  push_variant musl "${config_digest}" "${config_size}"
  build_and_push_index

  echo "push-dual-libc: pushed ${TARGET}:${TAG} (glibc=sha256:${GLIBC_DIGEST}, musl=sha256:${MUSL_DIGEST})"
}

main "$@"
