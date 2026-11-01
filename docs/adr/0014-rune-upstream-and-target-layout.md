# 0014: Multi-Upstream Integration of Rune (`anomalyco/rune`) and 1:1 SwiftPM Target Layout

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

[Rune](https://github.com/anomalyco/rune) (`anomalyco/rune`, MIT license) is a GPU-rendered declarative Rust UI toolkit built around a keyed element tree, Taffy layout, analytic spring motion (`rune-motion`), an uber-quad WebGPU/Metal renderer (`rune`), CPU reference rasterization (`rune-ref`), shader effects and lighting (`rune-fx`, `rune-light`), native Mermaid diagram rendering (`rune-mermaid`), live tuning knobs (`rune-knobs`), semantic themable components + Markdown (`rune-kit`), and the OpenCode design system (`rune-theme-opencode`).

GPUA already operates a multi-upstream file-for-file architecture (`upstreams` in `porting.json`, enforced by `Scripts/port.py`), with `Glass-HQ/gpui` and `DioxusLabs/taffy` ported across all six native platform families (macOS, iOS / visionOS, Linux, Windows, Android, and WebAssembly/WebGPU) and zero external SwiftPM dependencies. Because Rune shares the same foundational subsystems — Taffy flexbox/grid/block layout, WebGPU (`CWebGPU`) + Metal, CoreText / DirectWrite / FreeType+HarfBuzz, and native OS windowing bridges (`CLinuxSys`, `CWinSys`, `CAndroidSys`, `CWebSys`) — hosting the 1:1 Swift port of Rune inside GPUA lets Swift apps import either `GPUI` or `Rune` / `RuneKit` (or both) from one zero-dependency SwiftPM package while sharing layout and C/GPU system targets.

## Decision

1. **Third Pinned Upstream in `porting.json`**:
   - Register `rune` under `upstreams.rune` in `porting.json`, pinned to `https://github.com/anomalyco/rune.git` at commit `5f6d53ddae78956bec5a2999469ad5c1b6eccc70` in `.upstream/rune`.
   - `Scripts/port.py fetch`, `map`, `scaffold`, `status`, `todo`, `check`, and `stale` manage `.upstream/rune` identically to `.upstream/gpui` and `.upstream/taffy`.

2. **Standalone 1:1 Crate-to-Target Mapping (`Sources/Rune*` & `Tests/Rune*Tests`)**:
   - Map all 14 Rune library, support, effect, component, and theme crates 1:1 to SwiftPM targets with exact upstream dependency edges:
     - `procwatch` (`crates/procwatch`) → `Procwatch`
     - `rune-staging` (`crates/rune-staging`) → `RuneStaging` (depends on `CWebGPU`)
     - `rune-register` (`crates/rune-register`) → `RuneRegister` (explicit Swift registration replacing `linkme`, matching ADR-0007)
     - `rune-motion` (`crates/rune-motion`) → `RuneMotion`
     - `rune-perf` (`crates/rune-perf`) → `RunePerf` (depends on `Procwatch`)
     - `rune-mac` (`crates/rune-mac`) → `RuneMac` (`#if os(macOS)`)
     - `rune-light` (`crates/rune-light`) → `RuneLight` (depends on `RuneStaging`, `CWebGPU`; copies `shaders/*.wgsl`)
     - `rune-fx` (`crates/rune-fx`) → `RuneFX` (depends on `RuneMotion`, `RuneStaging`, `CWebGPU`; copies `shaders/*.wgsl`)
     - `rune` (`crates/rune`) → `Rune` (depends on `RuneMotion`, `RuneStaging`, `Procwatch`, `Taffy`, `CWebGPU`, and conditional `CLinuxSys` / `CWinSys` / `CAndroidSys` / `CWebSys`; copies WGSL shaders)
     - `rune-ref` (`crates/rune-ref`) → `RuneRef` (depends on `Rune`)
     - `rune-knobs` (`crates/rune-knobs`) → `RuneKnobs` (depends on `Rune`)
     - `rune-mermaid` (`crates/rune-mermaid`) → `RuneMermaid` (depends on `Rune`)
     - `rune-kit` (`crates/rune-kit`) → `RuneKit` (depends on `Rune`, `RuneMotion`, `RuneMermaid`)
     - `rune-theme-opencode` (`themes/opencode`) → `RuneThemeOpenCode` (depends on `Rune`, `RuneKit`)
   - Expose public SwiftPM library products for `Rune`, `RuneKit`, `RuneMotion`, `RuneFX`, `RuneLight`, `RuneMermaid`, `RuneKnobs`, and `RuneThemeOpenCode`.
   - Exclude library-internal Cargo `[[example]]` / `[[bench]]` directories (`"exclude": ["examples"]` / `["benches", "examples"]`, matching `taffy` in `porting.json`) because Cargo `[[example]]` binaries depend on `[dev-dependencies]` that would invert the library DAG.
   - Record the 26 top-level `examples/*` standalone binary crates as `"deferred"` (to be brought up in a `RuneExamples` runner target once `Rune` and `RuneKit` core land) and Rust-only build/hot-patch tools (`tools/rune-dev-guard`, `spikes/hot-patch`) as `"skip"`.

3. **Shared `Taffy` and Platform System Bridges**:
   - `Rune` reuses GPUA's pure-Swift `Taffy` target (extending `Taffy` with any `0.15` API additions needed by Rune while preserving 100% of GPUI's layout conformance suite) and reuses `CWebGPU`, `CLinuxSys`, `CWinSys`, `CAndroidSys`, and `CWebSys` with zero external SwiftPM package dependencies.

4. **Phased Bottom-Up Porting & Test Parity Gate**:
   - **Phase R0 (Scaffolding)**: Pin `anomalyco/rune`, scaffold all 1,368 mapped Swift source/test stubs and WGSL/PNG assets, and verify all 6 CI jobs stay green.
   - **Phase R1 (Support & Motion)**: Port `Procwatch`, `RuneStaging`, `RuneRegister`, `RuneMotion`, and `RunePerf` with full unit/integration test parity.
   - **Phase R2 (Core & Reference Renderer)**: Port `Rune`, `RuneMac`, and `RuneRef` (keyed tree, Taffy integration, text, uber-quad WebGPU/Metal renderer, headless test harness).
   - **Phase R3 (Effects, Diagrams & Knobs)**: Port `RuneLight`, `RuneFX`, `RuneKnobs`, and `RuneMermaid`.
   - **Phase R4 (Components, Theme & Examples)**: Port `RuneKit`, `RuneThemeOpenCode`, and `RuneExamples`.
   - Each Rune crate joins `IN_SCOPE_CRATES` in `Scripts/test_parity.py` as its phase completes so completed crates remain continuously gated at `>= 95%` 1-to-1 test parity.

## Alternatives Considered

- **Separate SwiftPM Repository for Rune**: Duplicates `Taffy` (~9,000 LOC), `CWebGPU`, `CLinuxSys`, `CWinSys`, `CAndroidSys`, `CWebSys`, `Scripts/port.py`, `Scripts/test_parity.py`, and 6-platform CI infrastructure, while forcing downstream Swift apps that want GPUI + Rune/RuneKit/RuneMotion/RuneMermaid to reconcile duplicate C/WebGPU/Taffy modules.
- **Re-implementing Rune Concepts Inside `GPUI` Elements**: Violates Golden Rule #1 and #3 (`One upstream file -> one Swift file`, `Port logic, not code. It is not an architectural redesign`). Keeping Rune's own keyed-tree architecture and crate boundaries 1:1 allows mechanical upstream sync via `Scripts/port.py stale` and `bump`.

## Consequences

- `Package.swift` remains a single zero-external-dependency SwiftPM package providing both the complete `GPUI` stack and the 1:1 `Rune` / `RuneKit` stack across macOS, iOS / visionOS, Linux, Windows, Android, and WebAssembly.
- All 1,368 Rune source, test, and shader/fixture entries are tracked in `docs/PORTING_STATUS.md` and validated on every CI run by `Scripts/port.py check`.
