# Packer (legacy)

> **Deprecated.** This package has moved to `hashicorp/packer`. See below
> for migration steps.

## Migration

Update your manifest to point at the new namespace:

```sh
ocx remove mitchellh/packer
ocx add hashicorp/packer
```

## Supported Platforms

| Platform      | Status      |
| -------------- | ----------- |
| linux/amd64    | supported   |
| darwin/arm64   | supported   |
| windows/amd64  | best-effort |

## History

This package predates the `hashicorp` namespace migration and is retained
for archival installs only -- no further releases will be published here.
