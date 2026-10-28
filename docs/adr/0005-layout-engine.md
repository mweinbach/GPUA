# 0005: Layout: port Taffy file-for-file

- **Status:** Accepted
- **Date:** 2026-10-28

## Context

GPUI's `taffy.rs` wraps the `taffy` crate (pinned `=0.9.0`) for flexbox, CSS grid, and block layout. GPUI exposes grid (`grid_layout` example) and relies on Taffy's exact semantics, including measure functions for text.

## Decision

Port **Taffy 0.9.0** layout engine algorithms (flexbox, grid, block, style, compute layout, cache) to Swift, preserving upstream layout calculation semantics and text measure callback contracts:

- Implement the Taffy engine (flexbox, grid, block, style tree, and layout computation) in Swift, maintaining bit-for-bit parity with upstream layout behavior.
- Support Taffy's flexbox, grid, block, and `taffy_tree` API needed by GPUI layout elements.
- Taffy is MIT-licensed. Add it to NOTICE.
- Port Taffy's test suite alongside the implementation to guarantee behavioral layout parity.

## Alternatives considered

- **Yoga** (C++, via Swift C++ interop): mature, but no CSS grid, and its semantics differ from Taffy in edge cases, which would produce visible layout differences from upstream.
- **A hand-written flexbox:** a large effort with no upstream to track.

## Consequences

Layout calculations match upstream bit-for-bit, text measure functions integrate seamlessly into element layout passes, and layout tests prove fidelity across all platforms.
