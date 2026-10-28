# AGENTS.md

Rules for any agent (human or AI) working in this repo. Read this first, then [docs/PORTING_GUIDE.md](docs/PORTING_GUIDE.md).

## What this repo is

GPUA is a **file-for-file Swift port of [GPUI](https://github.com/Glass-HQ/gpui)**, pinned to the upstream commit in [`porting.json`](porting.json). Every upstream crate is one SwiftPM target, and every upstream `.rs` file is one `.swift` file at the same relative path. The goal is a faithful port of upstream logic and behavior that can follow upstream over time. **Port logic, not code. It is not an architectural redesign.**

## Golden rules

1. **One upstream file → one Swift file. Never merge, split, rename, or move files.** `Scripts/port.py map <path>` tells you where something goes. If you think the layout is wrong, write an ADR. Don't improvise.
2. **Port from the pinned upstream, not from memory.** Run `Scripts/port.py fetch`, then read `.upstream/gpui/<path>` side by side with the Swift file. Don't port from crates.io docs, Zed `main`, or recollection.
3. **Port logic, not code (fidelity rule).** Keep the existing 1:1 upstream-file → Swift-file mapping and per-file headers. Inside each file, any idiomatic Swift is fine as long as behavior matches upstream, and tests must demonstrate that. Where Swift or the platform offers a different way to get the same result, use it and note the substitution with a `// PORT NOTE:` comment. A reviewer should be able to trace corresponding logic easily, but you do not need line-by-line transliteration.
4. **Faithful behavior, idiomatic Swift.** Do not redesign the architecture (keep GPUI's app model, entity leasing, scene graph, layout pipeline), but do write idiomatic Swift (value types for models/primitives, classes for identity/entities, Swift Concurrency, protocol extensions, standard collection types). If a platform or Swift feature provides a cleaner or more efficient mechanism to achieve upstream's behavior, use it and document the substitution with a `// PORT NOTE:`.
5. **Keep every file's header accurate.** Each ported file starts with:
   ```swift
   // Ported from: crates/gpui/src/elements/div.rs
   // Upstream commit: 650aab59d54f
   // Port status: in-progress
   ```
   Status values: `not-started` → `in-progress` → `ported` → `verified`, or `skipped` (plus a `// Skip reason:` line). Update `Upstream commit:` to the pinned commit whenever you re-sync a file.
6. **Port tests with the code.** Tests are the ultimate proof of behavioral fidelity. A file's `#[cfg(test)]` module goes to its paired file under `Tests/<Target>Tests/` (same relative path, same name). Use Swift Testing (`import Testing`). A file isn't `ported` until its behavioral tests are ported and pass, or are explicitly disabled with a reason.
7. **Everything compiles on every platform.** `swift build` must pass on macOS, Linux, and Windows CI. Platform targets wrap whole files in `#if os(...)` (the stubs already have the right guard). Don't remove guards.
8. **No new dependencies without an ADR.** That covers SwiftPM packages, vendored C libraries, and system libraries. See [docs/adr/](docs/adr).
9. **Swift-only files need a reason.** If a file has no upstream counterpart (an entry point, a shim, a replacement for a Rust crate), its first line must be `// Swift-only: <reason>`. `Scripts/port.py check` fails on unexplained orphans.
10. **Regenerate status before you commit.** Run `Scripts/port.py status --write && Scripts/port.py check`. CI runs `check`.

## Commands

```sh
Scripts/port.py fetch                     # pinned upstream → .upstream/gpui
Scripts/port.py map <rust-or-swift-path>  # show the counterpart path
Scripts/port.py todo [--target GPUI]      # not-started files, smallest first
Scripts/port.py scaffold                  # create stubs for new upstream files (never overwrites)
Scripts/port.py status --write            # regenerate docs/PORTING_STATUS.md
Scripts/port.py check                     # CI gate
Scripts/port.py stale                     # files ported from an older upstream commit

swift build                               # build everything
swift build --build-tests && swift test   # tests
swift run gpui-examples <name>            # run a ported example
```

> On macOS, if the swiftly/OSS toolchain fails against the newer Xcode SDK (e.g. `unknown argument: '-target-arch-variant'`), use Xcode's toolchain: `xcrun swift build`.

## How to pick work

1. Follow the phase order in [docs/ROADMAP.md](docs/ROADMAP.md). Dependencies come first: support crates, then `GPUI` foundations, then the app model, then platforms.
2. Within a phase, use `Scripts/port.py todo --target <T>`. Port a file only after what it `use`s exists, or stub the minimum you need and mark the file `in-progress`.
3. Keep PRs small: one file, or a tightly coupled cluster such as `geometry.rs` plus its tests. Title them `port(GPUI): elements/div.rs`.

## Where things are

| Path | What |
|---|---|
| `porting.json` | Upstream pin + crate→target mapping and per-crate decisions (port/skip/replace/deferred) |
| `Scripts/port.py` | Mapping, scaffolding, status, CI checks |
| `Sources/<Target>/` | Swift port; mirrors `crates/<crate>/src/` (and `examples/` for `GPUIExamples`) |
| `Tests/<Target>Tests/` | Inline `#[cfg(test)]` modules (same path) + `crates/<crate>/tests/` under `tests/` |
| `.upstream/gpui/` | Read-only pinned upstream checkout (gitignored) |
| `docs/` | Vision, architecture, porting guide, API design, platforms, roadmap, ADRs |

## Conventions (summary; details in the porting guide)

- Swift 6 language mode with strict concurrency, plus `ExistentialAny` (`dyn T` → `any T`).
- Types keep their upstream names verbatim (`Hsla`, `SharedString`, `AnyElement`). Functions, methods, fields, and enum cases are mechanically lowerCamelCased (`flex_col` → `flexCol`, `size_8` → `size8`, `WindowBounds::Windowed` → `.windowed`).
- Parameters are unlabeled (`_ x: T`) by default, matching Rust call sites.
- Rust `pub` → `public` if it's re-exported from the crate root, `package` if sibling targets use it, otherwise `internal`. `pub(crate)` → `internal`. Private → `private`/`fileprivate`.
- `#[cfg(target_os = "macos")]` → `#if os(macOS)`; `#[cfg(feature = "test-support")]` → `#if TestSupport` (SwiftPM trait).
- Don't add `@unchecked Sendable`, `nonisolated(unsafe)`, or force-unwraps just to silence the compiler. If you must, add a `// PORT NOTE:` explaining the upstream invariant that makes it safe.

## Definition of done for a file

- [ ] All upstream logic and behavior are ported into idiomatic Swift, or substitutions documented with `// PORT NOTE:`.
- [ ] Upstream doc comments are preserved and adapted to Swift DocC.
- [ ] Inline and behavioral tests are ported to the paired test file and pass on at least macOS and Linux (where the platform allows), verifying behavioral parity.
- [ ] The header has the right status and the pinned commit.
- [ ] `swift build` passes, and `Scripts/port.py status --write && Scripts/port.py check` passes.
