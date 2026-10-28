# 0001: File-for-file port of upstream GPUI

- **Status:** Accepted
- **Date:** 2026-10-27

## Context

We want GPUI's architecture and quality in Swift on every platform Swift supports. GPUI is ~135k lines of Rust across ~290 files and it changes constantly. A "Swift-inspired rewrite" would fall out of sync on day one and would lose the hard-won fixes that live in upstream's details.

## Decision

- Port **file-for-file**: one Rust crate → one SwiftPM target, one `.rs` → one `.swift` at the same relative path, keeping item order and doc comments.
- Pin one upstream commit (`porting.json`). Each Swift file records its source path, the commit it was synced to, and its port status in a header.
- `Scripts/port.py` owns the mapping, scaffolding, status reporting, and CI validation.
- Translate idioms mechanically, following `docs/PORTING_GUIDE.md`. Deviations need a `// PORT NOTE:`.
- No Rust in the build. This is a real port, not FFI bindings.

## Alternatives considered

- **Bind Rust GPUI through a C ABI.** Fastest route to pixels. But the Rust toolchain would be needed for every target, Swift types couldn't conform to `Render`/`Element`, and the public API would feel foreign. Rejected.
- **A clean-room Swift framework "inspired by" GPUI.** Freedom to redesign, but no upstream tracking and years of re-learning the same lessons. Rejected.
- **Port by subsystem, not file.** More natural Swift module boundaries, but upstream diffs stop applying mechanically. Rejected.

## Consequences

- Some files read as "Rust in Swift clothing" (snake_case file names, unlabeled parameters). We accept that for traceability.
- Upstream sync becomes routine: `bump` → `stale` → re-port the diffs.
- Swift-specific improvements (result builders, SwiftUI interop) can come later as *additive* layers in separate targets.
