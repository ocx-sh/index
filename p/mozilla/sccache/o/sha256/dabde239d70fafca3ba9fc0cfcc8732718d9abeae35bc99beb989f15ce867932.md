# sccache

sccache is a ccache-like compiler wrapper from Mozilla. It caches compilation
results and avoids recompiling when an input is unchanged, speeding up repeated
builds. Caches can live on the local disk or in remote storage — including
several cloud object stores — so the cache can be shared across machines and CI
runners.

## What's included

- **sccache** — the compiler-caching wrapper CLI (`--show-stats`, `--start-server`, `--stop-server`, `--zero-stats`, …)

## Links

- [sccache Documentation](https://github.com/mozilla/sccache#readme)
- [sccache on GitHub](https://github.com/mozilla/sccache)
