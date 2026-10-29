# API Parity Audit: `line_layout.rs`

- **Generated At**: 2026-10-29T04:27:26Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/text_system/line_layout.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/text_system/line_layout.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **30** | 100.0% |
| Genuine Swift Implementations | 30 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 30 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (30 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 16 | `LineLayout` | `struct` | `LineLayout` | `line_layout.swift:12` |
| 33 | `ShapedRun` | `struct` | `ShapedRun` | `line_layout.swift:211` |
| 42 | `ShapedGlyph` | `struct` | `ShapedGlyph` | `line_layout.swift:224` |
| 58 | `LineLayout::index_for_x` | `fn` | `indexForX` | `line_layout.swift:47` |
| 75 | `LineLayout::closest_index_for_x` | `fn` | `closestIndexForX` | `line_layout.swift:62` |
| 105 | `LineLayout::x_for_index` | `fn` | `xForIndex` | `line_layout.swift:92` |
| 117 | `LineLayout::font_id_for_index` | `fn` | `fontIdForIndex` | `line_layout.swift:104` |
| 212 | `WrappedLineLayout` | `struct` | `WrappedLineLayout` | `line_layout.swift:279` |
| 225 | `WrapBoundary` | `struct` | `WrapBoundary` | `line_layout.swift:259` |
| 235 | `WrappedLineLayout::len` | `fn` | `len` | `line_layout.swift:297` |
| 240 | `WrappedLineLayout::width` | `fn` | `width` | `line_layout.swift:301` |
| 248 | `WrappedLineLayout::size` | `fn` | `size` | `line_layout.swift:305` |
| 256 | `WrappedLineLayout::ascent` | `fn` | `ascent` | `line_layout.swift:312` |
| 261 | `WrappedLineLayout::descent` | `fn` | `descent` | `line_layout.swift:316` |
| 266 | `WrappedLineLayout::wrap_boundaries` | `fn` | `wrapBoundaries` | `line_layout.swift:283` |
| 271 | `WrappedLineLayout::font_size` | `fn` | `fontSize` | `line_layout.swift:320` |
| 276 | `WrappedLineLayout::runs` | `fn` | `runs` | `line_layout.swift:324` |
| 283 | `WrappedLineLayout::index_for_position` | `fn` | `indexForPosition` | `line_layout.swift:328` |
| 296 | `WrappedLineLayout::closest_index_for_position` | `fn` | `closestIndexForPosition` | `line_layout.swift:332` |
| 362 | `WrappedLineLayout::position_for_index` | `fn` | `positionForIndex` | `line_layout.swift:384` |
| 392 | `LineLayoutCache` | `struct` | `LineLayoutCache` | `line_layout.swift:456` |
| 407 | `LineLayoutIndex` | `struct` | `LineLayoutIndex` | `line_layout.swift:418` |
| 413 | `LineLayoutCache::new` | `fn` | `new` | `line_layout.swift:466` |
| 421 | `LineLayoutCache::layout_index` | `fn` | `layoutIndex` | `line_layout.swift:470` |
| 429 | `LineLayoutCache::reuse_layouts` | `fn` | `reuseLayouts` | `line_layout.swift:479` |
| 450 | `LineLayoutCache::truncate_layouts` | `fn` | `truncateLayouts` | `line_layout.swift:506` |
| 458 | `LineLayoutCache::finish_frame` | `fn` | `finishFrame` | `line_layout.swift:517` |
| 468 | `LineLayoutCache::layout_wrapped_line` | `fn` | `layoutWrappedLine` | `line_layout.swift:524` |
| 533 | `LineLayoutCache::layout_line` | `fn` | `layoutLine` | `line_layout.swift:576` |
| 598 | `FontRun` | `struct` | `FontRun` | `line_layout.swift:248` |

</details>
