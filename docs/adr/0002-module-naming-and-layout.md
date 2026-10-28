# 0002: Crate → target naming and file layout

- **Status:** Accepted
- **Date:** 2026-10-27

## Decision

- **Repo/package:** `GPUA`. **Modules** mirror crates in PascalCase: `gpui` → `GPUI`, `gpui_macos` → `GPUIMacOS`, `gpui_ios` → `GPUIiOS`, `gpui_wgpu` → `GPUIWGPU`, `sum_tree` → `SumTree`, `http_client` → `HTTPClient`.
- **Collision-driven exceptions:** `collections` → `GPUICollections` (apple/swift-collections ships a `Collections` module) and `util` → `ZedUtil` (`Util` is too generic and `GPUIUtil` is taken by `gpui_util`).
- **Files:** keep upstream `snake_case` stems. `mod.rs` → `<dir>/<dir>.swift`. Basename collisions within a target are resolved by prefixing parent directory names (SwiftPM rejects duplicate basenames in one target). The shallowest file keeps the plain name.
- **Tests:** inline `#[cfg(test)]` → `Tests/<T>Tests/<same path>`. `crates/<c>/tests/*` → `Tests/<T>Tests/tests/*`.
- **Platform targets** compile on every OS. Each file is wrapped in its `#if` guard (`porting.json` → `guard`), and `GPUIPlatform` selects the backend with `.when(platforms:)`.
- **Skipped crates:** `gpui_tokio` (skip), `reqwest_client` (replaced by URLSession in `HTTPClient`), `http_client_tls` (skip), `util_macros` (skip), `cargo-gpui`/`perf` (deferred).
- **New target:** `GPUIAndroid` (Swift-only), shaped like `gpui_linux`/`gpui_ios`.

## Consequences

`Scripts/port.py map` is the single source of truth, and nobody hand-computes paths. Module names are stable public API, so renaming after 1.0 is a breaking change.
