# 0005: Layout: pure Swift multi-upstream port of Taffy 0.9.0

- **Status:** Accepted (Amended)
- **Date:** 2026-10-28
- **Amended:** 2026-10-28 (Milestone 2 Remediation & Multi-Upstream Architecture)

## Context

Upstream GPUI (`crates/gpui/src/taffy.rs`, 584 LOC) wraps the Rust `taffy` crate (pinned `=0.9.0`) for flexbox, CSS Grid, and block layout. GPUI relies extensively on Taffy's exact semantics:
1. `TaffyTree<NodeContext>` storage arena, generational slot mapping, 9-slot layout cache, and dirty ancestor propagation.
2. Text and custom element measurement callback integration (`NodeMeasureFn`) in `compute_layout_with_measure`.
3. Cumulative pixel rounding (`round_layout`) preventing subpixel gaps and overlaps between adjacent elements.
4. Full CSS Flexbox Level 1 resolution: flex basis, grow/shrink factor resolution loops, auto margin distribution, and baseline alignment.
5. Full CSS Grid Level 1 resolution: fractional units (`fr`), explicit/implicit grid placement, auto-flow, and 5-phase track sizing.
6. CSS Block layout: vertical margin collapsing and auto-margin inline centering.

An earlier attempt to substitute an ad-hoc ~600-line layout solver inside `Sources/GPUI/taffy.swift` (Dead End #8) failed behavioral equivalence on flex-basis, shrink/grow resolution, min/max clamping, percentage resolution, auto margins, and CSS Grid track sizing. Per the Parent Directive and fidelity rules, GPUA requires a faithful implementation backed by empirical conformance evidence.

## Decision

Port **Taffy 0.9.0** as a pure Swift, multi-upstream target (`Taffy`) with file-for-file mapping and prove behavioral parity through an automated Chrome conformance gate:

1. **Multi-Upstream Configuration**:
   - Primary upstream: `gpui` pinned to commit `650aab59d54f4f6f85d42c965831935568ac1162` in `.upstream/gpui`.
   - Secondary upstream: `taffy` pinned to commit `599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a` (tag `v0.9.0`, repository `https://github.com/DioxusLabs/taffy`) in `.upstream/taffy`.
   - `porting.json` and `Scripts/port.py` are extended to support secondary upstreams, validating file mapping and commit tracking across both repositories.

2. **File-for-File Target Architecture (`Sources/Taffy/`)**:
   - The 47 Rust source files in Taffy 0.9.0 `src/` map 1:1 to `Sources/Taffy/`.
   - Subsystem 1: Core Geometry (`geometry.swift`) and Math/Sys (`util/math.swift`, `util/sys.swift`).
   - Subsystem 2: Style Primitives (`style/dimension.swift`, `style/alignment.swift`, `style/flex.swift`, `style/grid.swift`, `style/style.swift`, `style_helpers.swift`).
   - Subsystem 3: Arena Tree and 9-Slot Cache (`tree/taffy_tree.swift`, `tree/cache.swift`, `tree/node.swift`, `tree/layout.swift`, `tree/traits.swift`).
   - Subsystem 4: Layout Solvers (`compute/flexbox.swift`, `compute/block.swift`, `compute/grid/`, `compute/leaf.swift`, `compute/compute.swift`).
   - Every file maintains the canonical header with `// Ported from: src/<path>.rs` and upstream commit `599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a`.

3. **GPUI Layout Adapter (`Sources/GPUI/taffy.swift`)**:
   - GPUI's `taffy.swift` remains a faithful 584-line adapter importing `Taffy`.
   - `TaffyLayoutEngine` wraps `TaffyTree<NodeContext>`, enables rounding, and delegates layout computation without ad-hoc algorithmic shortcuts.

4. **Mandatory 110-Fixture Chrome Layout Conformance Gate**:
   - Taffy 0.9.0 ships with 1,034 W3C/Chrome conformance layout test fixtures in `tests/generated/`.
   - GPUA establishes a mandatory gate subset of **110 representative fixtures (220 tests)** across Flexbox (50 fixtures), CSS Grid (30 fixtures), Block (20 fixtures), and Leaf/Measure (10 fixtures) in `Tests/TaffyTests/Generated/`.
   - **Gate Criterion**: 100% of the 110 fixtures must match Chrome-generated border box coordinates and dimensions within a `0.1` px tolerance on macOS and Linux.
   - `Sources/GPUI/taffy.swift` shall only be marked `ported` once this conformance gate passes 100%.

## Alternatives Considered

- **Yoga (C++ via Swift C++ interop)**: Lacks CSS Grid, has known edge-case differences from W3C Flexbox Level 1, and introduces a complex C++ toolchain dependency.
- **Simplified / hand-rolled layout solver in GPUI**: Disqualified as Dead End #8. Fails behavioral equivalence on complex layouts, percentages, auto margins, baseline alignment, and CSS Grid track sizing.
- **Vendoring Taffy via Rust C-FFI / cxx**: Rejected in favor of pure Swift, eliminating Cargo toolchain requirements in downstream SwiftPM consumers and maintaining seamless Swift Concurrency and memory safety.

## Consequences

- Full behavioral parity with upstream Zed/GPUI layout behavior across macOS, Linux, and Windows.
- Clean architectural boundary: `Taffy` is a standalone, reusable Swift layout package that GPUI depends upon.
- Independent test verification via Chrome/W3C layout conformance fixtures guarantees against layout regressions.
- Upstream Taffy updates can be pulled and tracked using `Scripts/port.py`.
