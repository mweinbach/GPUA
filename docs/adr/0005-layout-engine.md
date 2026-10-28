# 0005: Layout: port Taffy file-for-file

- **Status:** Proposed
- **Date:** 2026-10-27

## Context

GPUI's `taffy.rs` wraps the `taffy` crate (pinned `=0.9.0`) for flexbox, CSS grid, and block layout. GPUI exposes grid (`grid_layout` example) and relies on Taffy's exact semantics, including measure functions for text.

## Decision

Port **Taffy 0.9.0** as its own target, `Taffy`, using the same file-for-file process:

- Generalize `porting.json` to support multiple upstreams (`upstreams: [{name: "gpui", …}, {name: "taffy", repo: "https://github.com/DioxusLabs/taffy", commit: "<v0.9.0 sha>"}]`) and teach `Scripts/port.py` about them.
- Port only the features GPUI enables: flexbox, grid, block, and the `taffy_tree` API. Skip unused feature-gated modules with `skipped`.
- Taffy is MIT-licensed. Add it to NOTICE.

## Alternatives considered

- **Yoga** (C++, via Swift C++ interop): mature, but no CSS grid, and its semantics differ from Taffy in edge cases, which would produce visible layout differences from upstream.
- **A hand-written flexbox:** a large effort with no upstream to track.

## Consequences

Roughly another 15–20k lines to port, but the work is mechanical, well tested (Taffy has an extensive generated test suite we can port), and layout output can match upstream exactly.
