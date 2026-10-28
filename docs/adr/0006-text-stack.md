# 0006: Text: CoreText / DirectWrite / FreeType + HarfBuzz

- **Status:** Accepted
- **Date:** 2026-10-28

## Context

`PlatformTextSystem` does font matching, metrics, shaping (`layout_line`), and glyph rasterization. Upstream uses CoreText on Apple (`gpui_macos/text_system.rs`, `gpui_ios/text_system.rs`), DirectWrite on Windows (`direct_write.rs`), and **cosmic-text + swash** on Linux/web (`gpui_wgpu/cosmic_text_system.rs`). cosmic-text is pure Rust (rustybuzz shaping, swash rasterization, fontdb discovery).

## Decision

- **Apple:** CoreText, ported 1:1.
- **Windows:** DirectWrite via WinSDK COM interop, ported 1:1.
- **Linux/Android:** port `cosmic_text_system.rs`'s *structure and behavior* onto **HarfBuzz** (shaping), **FreeType** (rasterization and metrics), and **fontconfig** (Linux discovery and fallback). On Android, discovery reads `/system/fonts` + `fonts.xml`.
  - Linux uses system libraries through `systemLibrary` targets (`CFreeType`, `CHarfBuzz`, `CFontConfig`) + pkg-config. Under R5, `libfreetype6-dev`, `libharfbuzz-dev`, and `libfontconfig1-dev` are accepted system dependencies.
  - Android vendors FreeType and HarfBuzz as C/C++ source targets, since the NDK doesn't expose them.
  - The file keeps its upstream name (`cosmic_text_system.swift`) and carries a `// PORT NOTE:` that explains the backend substitution.
- **Headless Core & Test Platform:** `NoopTextSystem` with deterministic mock font metrics (constant line height, fixed glyph advances) allowing headless rendering and layout tests to run predictably without platform font dependencies.

## Alternatives considered

- Port cosmic-text + rustybuzz + swash to Swift: tens of thousands of lines of font code. Not worth it right now. Could revisit.
- Use the platform's Skia/Minikin on Android: not public NDK API.

## Consequences

Glyph output on Linux will differ slightly from upstream (a different rasterizer), so pixel tests there need tolerance. Linux CI installs system packages `libfreetype6-dev`, `libharfbuzz-dev`, and `libfontconfig1-dev`. Headless test suites run deterministically using `NoopTextSystem`.
