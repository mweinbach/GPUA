# API Parity Audit: `text_system.rs`

- **Generated At**: 2026-10-29T04:27:22Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/text_system.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/text_system.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **69** | 100.0% |
| Genuine Swift Implementations | 69 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 69 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (69 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 38 | `FontId` | `struct` | `FontId` | `text_system.swift:9` |
| 42 | `FontFamilyId` | `struct` | `FontFamilyId` | `text_system.swift:18` |
| 45 | `SUBPIXEL_VARIANTS_X` | `const` | `subpixelVariantsX` | `text_system.swift:27` |
| 48 | `SUBPIXEL_VARIANTS_Y` | `const` | `subpixelVariantsY` | `text_system.swift:31` |
| 55 | `TextSystem` | `struct` | `TextSystem` | `text_system.swift:302` |
| 66 | `TextSystem::new` | `fn` | `new` | `text_system.swift:328` |
| 91 | `TextSystem::all_font_names` | `fn` | `allFontNames` | `text_system.swift:332` |
| 105 | `TextSystem::add_fonts` | `fn` | `addFonts` | `text_system.swift:340` |
| 135 | `TextSystem::get_font_for_id` | `fn` | `getFontForId` | `text_system.swift:359` |
| 151 | `TextSystem::resolve_font` | `fn` | `resolveFont` | `text_system.swift:368` |
| 174 | `TextSystem::bounding_box` | `fn` | `boundingBox` | `text_system.swift:380` |
| 179 | `TextSystem::typographic_bounds` | `fn` | `typographicBounds` | `text_system.swift:385` |
| 198 | `TextSystem::advance` | `fn` | `advance` | `text_system.swift:398` |
| 212 | `TextSystem::em_width` | `fn` | `emWidth` | `text_system.swift:409` |
| 219 | `TextSystem::em_advance` | `fn` | `emAdvance` | `text_system.swift:413` |
| 224 | `TextSystem::layout_width` | `fn` | `layoutWidth` | `text_system.swift:417` |
| 240 | `TextSystem::em_layout_width` | `fn` | `emLayoutWidth` | `text_system.swift:423` |
| 247 | `TextSystem::ch_width` | `fn` | `chWidth` | `text_system.swift:427` |
| 254 | `TextSystem::ch_advance` | `fn` | `chAdvance` | `text_system.swift:431` |
| 261 | `TextSystem::units_per_em` | `fn` | `unitsPerEm` | `text_system.swift:435` |
| 266 | `TextSystem::cap_height` | `fn` | `capHeight` | `text_system.swift:439` |
| 271 | `TextSystem::x_height` | `fn` | `xHeight` | `text_system.swift:443` |
| 276 | `TextSystem::ascent` | `fn` | `ascent` | `text_system.swift:447` |
| 282 | `TextSystem::descent` | `fn` | `descent` | `text_system.swift:451` |
| 287 | `TextSystem::baseline_offset` | `fn` | `baselineOffset` | `text_system.swift:455` |
| 314 | `TextSystem::line_wrapper` | `fn` | `lineWrapper` | `text_system.swift:462` |
| 331 | `TextSystem::raster_bounds` | `fn` | `rasterBounds` | `text_system.swift:486` |
| 343 | `TextSystem::rasterize_glyph` | `fn` | `rasterizeGlyph` | `text_system.swift:501` |
| 354 | `TextSystem::recommended_rendering_mode` | `fn` | `recommendedRenderingMode` | `text_system.swift:507` |
| 366 | `WindowTextSystem` | `struct` | `WindowTextSystem` | `text_system.swift:565` |
| 373 | `WindowTextSystem::new` | `fn` | `new` | `text_system.swift:574` |
| 380 | `WindowTextSystem::layout_index` | `fn` | `layoutIndex` | `text_system.swift:578` |
| 384 | `WindowTextSystem::reuse_layouts` | `fn` | `reuseLayouts` | `text_system.swift:582` |
| 388 | `WindowTextSystem::truncate_layouts` | `fn` | `truncateLayouts` | `text_system.swift:586` |
| 398 | `WindowTextSystem::shape_line` | `fn` | `shapeLine` | `text_system.swift:599` |
| 442 | `WindowTextSystem::shape_text` | `fn` | `shapeText` | `text_system.swift:631` |
| 570 | `WindowTextSystem::finish_frame` | `fn` | `finishFrame` | `text_system.swift:708` |
| 578 | `WindowTextSystem::layout_line` | `fn` | `layoutLine` | `text_system.swift:712` |
| 637 | `LineWrapperHandle` | `struct` | `LineWrapperHandle` | `text_system.swift:528` |
| 674 | `FontWeight` | `struct` | `FontWeight` | `text_system.swift:37` |
| 705 | `FontWeight::THIN` | `const` | `thin` | `text_system.swift:52` |
| 707 | `FontWeight::EXTRA_LIGHT` | `const` | `extraLight` | `text_system.swift:53` |
| 709 | `FontWeight::LIGHT` | `const` | `light` | `text_system.swift:54` |
| 711 | `FontWeight::NORMAL` | `const` | `normal` | `text_system.swift:55` |
| 713 | `FontWeight::MEDIUM` | `const` | `medium` | `text_system.swift:56` |
| 715 | `FontWeight::SEMIBOLD` | `const` | `semibold` | `text_system.swift:57` |
| 717 | `FontWeight::BOLD` | `const` | `bold` | `text_system.swift:58` |
| 719 | `FontWeight::EXTRA_BOLD` | `const` | `extraBold` | `text_system.swift:59` |
| 721 | `FontWeight::BLACK` | `const` | `black` | `text_system.swift:60` |
| 724 | `FontWeight::ALL` | `const` | `all` | `text_system.swift:62` |
| 756 | `FontStyle` | `enum` | `FontStyle` | `text_system.swift:72` |
| 774 | `TextRun` | `struct` | `TextRun` | `text_system.swift:133` |
| 801 | `GlyphId` | `struct` | `GlyphId` | `text_system.swift:159` |
| 805 | `RenderGlyphParams` | `struct` | `RenderGlyphParams` | `text_system.swift:168` |
| 831 | `Font` | `struct` | `Font` | `text_system.swift:86` |
| 857 | `font` | `fn` | `font` | `text_system.swift:128` |
| 869 | `Font::bold` | `fn` | `bold` | `text_system.swift:113` |
| 875 | `Font::italic` | `fn` | `italic` | `text_system.swift:120` |
| 884 | `FontMetrics` | `struct` | `FontMetrics` | `text_system.swift:197` |
| 917 | `FontMetrics::ascent` | `fn` | `ascent` | `text_system.swift:199` |
| 922 | `FontMetrics::descent` | `fn` | `descent` | `text_system.swift:200` |
| 927 | `FontMetrics::line_gap` | `fn` | `lineGap` | `text_system.swift:201` |
| 932 | `FontMetrics::underline_position` | `fn` | `underlinePosition` | `text_system.swift:202` |
| 937 | `FontMetrics::underline_thickness` | `fn` | `underlineThickness` | `text_system.swift:203` |
| 942 | `FontMetrics::cap_height` | `fn` | `capHeight` | `text_system.swift:204` |
| 947 | `FontMetrics::x_height` | `fn` | `xHeight` | `text_system.swift:205` |
| 952 | `FontMetrics::bounding_box` | `fn` | `boundingBox` | `text_system.swift:206` |
| 958 | `font_name_with_fallbacks` | `fn` | `fontNameWithFallbacks` | `text_system.swift:268` |
| 971 | `font_name_with_fallbacks_shared` | `fn` | `fontNameWithFallbacksShared` | `text_system.swift:282` |

</details>
