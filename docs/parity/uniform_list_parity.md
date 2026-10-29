# API Parity Audit: `uniform_list.rs`

- **Generated At**: 2026-10-29T07:14:06Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/uniform_list.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/uniform_list.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **24** | 100.0% |
| Genuine Swift Implementations | 24 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 24 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (24 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 22 | `uniform_list` | `fn` | `uniformList` | `uniform_list.swift:12` |
| 58 | `UniformList` | `struct` | `UniformList` | `uniform_list.swift:38` |
| 72 | `UniformListFrameState` | `struct` | `UniformListFrameState` | `uniform_list.swift:411` |
| 80 | `UniformListScrollHandle` | `struct` | `UniformListScrollHandle` | `uniform_list.swift:484` |
| 84 | `ScrollStrategy` | `enum` | `ScrollStrategy` | `uniform_list.swift:422` |
| 103 | `DeferredScrollToItem` | `struct` | `DeferredScrollToItem` | `uniform_list.swift:429` |
| 115 | `UniformListScrollState` | `struct` | `UniformListScrollState` | `uniform_list.swift:458` |
| 126 | `ItemSize` | `struct` | `ItemSize` | `uniform_list.swift:444` |
| 136 | `UniformListScrollHandle::new` | `fn` | `new` | `uniform_list.swift:505` |
| 150 | `UniformListScrollHandle::scroll_to_item` | `fn` | `scrollToItem` | `uniform_list.swift:510` |
| 163 | `UniformListScrollHandle::scroll_to_item_strict` | `fn` | `scrollToItemStrict` | `uniform_list.swift:520` |
| 182 | `UniformListScrollHandle::scroll_to_item_with_offset` | `fn` | `scrollToItemWithOffset` | `uniform_list.swift:530` |
| 201 | `UniformListScrollHandle::scroll_to_item_strict_with_offset` | `fn` | `scrollToItemStrictWithOffset` | `uniform_list.swift:540` |
| 216 | `UniformListScrollHandle::y_flipped` | `fn` | `yFlipped` | `uniform_list.swift:550` |
| 222 | `UniformListScrollHandle::logical_scroll_top_index` | `fn` | `logicalScrollTopIndex` | `uniform_list.swift:555` |
| 231 | `UniformListScrollHandle::is_scrollable` | `fn` | `isScrollable` | `uniform_list.swift:563` |
| 240 | `UniformListScrollHandle::scroll_to_bottom` | `fn` | `scrollToBottom` | `uniform_list.swift:571` |
| 568 | `UniformListDecoration` | `trait` | `UniformListDecoration` | `uniform_list.swift:577` |
| 610 | `UniformList::with_width_from_item` | `fn` | `withWidthFromItem` | `uniform_list.swift:80` |
| 616 | `UniformList::with_sizing_behavior` | `fn` | `withSizingBehavior` | `uniform_list.swift:87` |
| 624 | `UniformList::with_horizontal_sizing_behavior` | `fn` | `withHorizontalSizingBehavior` | `uniform_list.swift:94` |
| 641 | `UniformList::with_decoration` | `fn` | `withDecoration` | `uniform_list.swift:107` |
| 671 | `UniformList::track_scroll` | `fn` | `trackScroll` | `uniform_list.swift:114` |
| 678 | `UniformList::y_flipped` | `fn` | `yFlipped` | `uniform_list.swift:122` |

</details>
