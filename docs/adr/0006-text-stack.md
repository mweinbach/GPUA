# 0006: Text: CoreText / DirectWrite / FreeType + HarfBuzz

- **Status:** Proposed
- **Date:** 2026-10-27

## Context

`PlatformTextSystem` does font matching, metrics, shaping (`layout_line`), and glyph rasterization. Upstream uses CoreText on Apple (`gpui_macos/text_system.rs`, `gpui_ios/text_system.rs`), DirectWrite on Windows (`direct_write.rs`), and **cosmic-text + swash** on Linux/web (`gpui_wgpu/cosmic_text_system.rs`). cosmic-text is pure Rust (rustybuzz shaping, swash rasterization, fontdb discovery).

## Decision

- **Apple:** CoreText, ported 1:1.
- **Windows:** DirectWrite, ported 1:1.
- **Linux/Android:** port `cosmic_text_system.rs`'s *structure and behavior* onto **HarfBuzz** (shaping), **FreeType** (rasterization and metrics), and **fontconfig** (Linux discovery and fallback). On Android, discovery reads `/system/fonts` + `fonts.xml`.
  - Linux uses system libraries through `systemLibrary` + pkg-config.
  - Android vendors FreeType and HarfBuzz as C/C++ source targets, since the NDK doesn't expose them.
  - The file keeps its upstream name (`cosmic_text_system.swift`) and carries a `// PORT NOTE:` that explains the backend substitution.

## Alternatives considered

- Port cosmic-text + rustybuzz + swash to Swift: tens of thousands of lines of font code. Not worth it right now. Could revisit.
- Use the platform's Skia/Minikin on Android: not public NDK API.

## Consequences

Glyph output on Linux will differ slightly from upstream (a different rasterizer), so pixel tests there need tolerance. Adding FreeType/HarfBuzz/fontconfig requires follow-up ADRs for each vendoring choice.
