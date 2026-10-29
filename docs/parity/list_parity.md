# API Parity Audit: `list.rs`

- **Generated At**: 2026-10-29T07:12:37Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/list.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/list.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **35** | 100.0% |
| Genuine Swift Implementations | 35 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 35 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (35 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 24 | `list` | `fn` | `list` | `list.swift:14` |
| 37 | `List` | `struct` | `List` | `list.swift:22` |
| 46 | `List::with_sizing_behavior` | `fn` | `withSizingBehavior` | `list.swift:42` |
| 54 | `ListState` | `struct` | `ListState` | `list.swift:241` |
| 89 | `FollowMode` | `enum` | `FollowMode` | `list.swift:950` |
| 132 | `ListAlignment` | `enum` | `ListAlignment` | `list.swift:979` |
| 140 | `ListScrollEvent` | `struct` | `ListScrollEvent` | `list.swift:985` |
| 156 | `ListSizingBehavior` | `enum` | `ListSizingBehavior` | `list.swift:1000` |
| 166 | `ListMeasuringBehavior` | `enum` | `ListMeasuringBehavior` | `list.swift:1008` |
| 186 | `ListHorizontalSizingBehavior` | `enum` | `ListHorizontalSizingBehavior` | `list.swift:1022` |
| 207 | `ListPrepaintState` | `struct` | `ListPrepaintState` | `list.swift:1030` |
| 281 | `ListState::new` | `fn` | `new` | `list.swift:680` |
| 303 | `ListState::measure_all` | `fn` | `measureAll` | `list.swift:685` |
| 311 | `ListState::reset` | `fn` | `reset` | `list.swift:691` |
| 328 | `ListState::remeasure` | `fn` | `remeasure` | `list.swift:703` |
| 340 | `ListState::remeasure_items` | `fn` | `remeasureItems` | `list.swift:709` |
| 390 | `ListState::item_count` | `fn` | `itemCount` | `list.swift:738` |
| 396 | `ListState::splice` | `fn` | `splice` | `list.swift:743` |
| 404 | `ListState::splice_focusable` | `fn` | `spliceFocusable` | `list.swift:748` |
| 445 | `ListState::set_scroll_handler` | `fn` | `setScrollHandler` | `list.swift:774` |
| 453 | `ListState::logical_scroll_top` | `fn` | `logicalScrollTop` | `list.swift:779` |
| 458 | `ListState::scroll_by` | `fn` | `scrollBy` | `list.swift:784` |
| 495 | `ListState::scroll_to_end` | `fn` | `scrollToEnd` | `list.swift:813` |
| 508 | `ListState::set_follow_mode` | `fn` | `setFollowMode` | `list.swift:819` |
| 530 | `ListState::is_following_tail` | `fn` | `isFollowingTail` | `list.swift:831` |
| 538 | `ListState::scroll_to` | `fn` | `scrollTo` | `list.swift:836` |
| 556 | `ListState::scroll_to_reveal_item` | `fn` | `scrollToRevealItem` | `list.swift:854` |
| 589 | `ListState::bounds_for_item` | `fn` | `boundsForItem` | `list.swift:882` |
| 621 | `ListState::scrollbar_drag_started` | `fn` | `scrollbarDragStarted` | `list.swift:907` |
| 629 | `ListState::scrollbar_drag_ended` | `fn` | `scrollbarDragEnded` | `list.swift:912` |
| 634 | `ListState::set_offset_from_scrollbar` | `fn` | `setOffsetFromScrollbar` | `list.swift:917` |
| 640 | `ListState::max_offset_for_scrollbar` | `fn` | `maxOffsetForScrollbar` | `list.swift:922` |
| 646 | `ListState::scroll_px_offset_for_scrollbar` | `fn` | `scrollPxOffsetForScrollbar` | `list.swift:927` |
| 668 | `ListState::viewport_bounds` | `fn` | `viewportBounds` | `list.swift:944` |
| 1169 | `ListOffset` | `struct` | `ListOffset` | `list.swift:1041` |

</details>
