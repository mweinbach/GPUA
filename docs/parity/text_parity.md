# API Parity Audit: `text.rs`

- **Generated At**: 2026-10-29T07:04:37Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/text.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/text.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **21** | 100.0% |
| Genuine Swift Implementations | 21 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 21 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (21 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 158 | `StyledText` | `struct` | `StyledText` | `text.swift:274` |
| 167 | `StyledText::new` | `fn` | `new` | `text.swift:291` |
| 177 | `StyledText::layout` | `fn` | `layout` | `text.swift:296` |
| 183 | `StyledText::with_default_highlights` | `fn` | `withDefaultHighlights` | `text.swift:302` |
| 198 | `StyledText::with_highlights` | `fn` | `withHighlights` | `text.swift:328` |
| 246 | `StyledText::with_runs` | `fn` | `withRuns` | `text.swift:335` |
| 327 | `TextLayout` | `struct` | `TextLayout` | `text.swift:37` |
| 505 | `TextLayout::index_for_position` | `fn` | `indexForPosition` | `text.swift:138` |
| 539 | `TextLayout::position_for_index` | `fn` | `positionForIndex` | `text.swift:171` |
| 570 | `TextLayout::line_layout_for_index` | `fn` | `lineLayoutForIndex` | `text.swift:198` |
| 600 | `TextLayout::bounds` | `fn` | `bounds` | `text.swift:221` |
| 605 | `TextLayout::line_height` | `fn` | `lineHeight` | `text.swift:226` |
| 610 | `TextLayout::len` | `fn` | `len` | `text.swift:231` |
| 615 | `TextLayout::text` | `fn` | `text` | `text.swift:236` |
| 627 | `TextLayout::wrapped_text` | `fn` | `wrappedText` | `text.swift:241` |
| 651 | `InteractiveText` | `struct` | `InteractiveText` | `text.swift:399` |
| 669 | `InteractiveTextState` | `struct` | `InteractiveTextState` | `text.swift:386` |
| 678 | `InteractiveText::new` | `fn` | `new` | `text.swift:420` |
| 692 | `InteractiveText::on_click` | `fn` | `onClick` | `text.swift:426` |
| 711 | `InteractiveText::on_hover` | `fn` | `onHover` | `text.swift:438` |
| 720 | `InteractiveText::tooltip` | `fn` | `tooltip` | `text.swift:447` |

</details>
