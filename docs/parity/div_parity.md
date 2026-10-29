# API Parity Audit: `div.rs`

- **Generated At**: 2026-10-29T06:45:40Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/div.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/div.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **100** | 100.0% |
| Genuine Swift Implementations | 100 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 100 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (100 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 52 | `GroupStyle` | `struct` | `GroupStyle` | `div.swift:11` |
| 62 | `DragMoveEvent` | `struct` | `DragMoveEvent` | `div.swift:28` |
| 74 | `DragMoveEvent::drag` | `fn` | `drag` | `div.swift:44` |
| 82 | `DragMoveEvent::dragged_item` | `fn` | `draggedItem` | `div.swift:52` |
| 91 | `Interactivity::new` | `fn` | `new` | `div.swift:336` |
| 100 | `Interactivity::new` | `fn` | `new` | `div.swift:336` |
| 105 | `Interactivity::source_location` | `fn` | `sourceLocation` | `div.swift:340` |
| 121 | `Interactivity::on_mouse_down` | `fn` | `onMouseDown` | `div.swift:344` |
| 141 | `Interactivity::capture_any_mouse_down` | `fn` | `captureAnyMouseDown` | `div.swift:355` |
| 157 | `Interactivity::on_any_mouse_down` | `fn` | `onAnyMouseDown` | `div.swift:365` |
| 173 | `Interactivity::on_mouse_pressure` | `fn` | `onMousePressure` | `div.swift:375` |
| 189 | `Interactivity::capture_mouse_pressure` | `fn` | `captureMousePressure` | `div.swift:385` |
| 205 | `Interactivity::on_mouse_up` | `fn` | `onMouseUp` | `div.swift:395` |
| 225 | `Interactivity::capture_any_mouse_up` | `fn` | `captureAnyMouseUp` | `div.swift:406` |
| 241 | `Interactivity::on_any_mouse_up` | `fn` | `onAnyMouseUp` | `div.swift:416` |
| 258 | `Interactivity::on_mouse_down_out` | `fn` | `onMouseDownOut` | `div.swift:426` |
| 275 | `Interactivity::on_mouse_up_out` | `fn` | `onMouseUpOut` | `div.swift:436` |
| 295 | `Interactivity::on_mouse_move` | `fn` | `onMouseMove` | `div.swift:447` |
| 314 | `Interactivity::on_drag_move` | `fn` | `onDragMove` | `div.swift:457` |
| 344 | `Interactivity::on_scroll_wheel` | `fn` | `onScrollWheel` | `div.swift:476` |
| 357 | `Interactivity::on_pinch` | `fn` | `onPinch` | `div.swift:486` |
| 367 | `Interactivity::on_rotation` | `fn` | `onRotation` | `div.swift:496` |
| 383 | `Interactivity::capture_action` | `fn` | `captureAction` | `div.swift:506` |
| 404 | `Interactivity::on_action` | `fn` | `onAction` | `div.swift:522` |
| 422 | `Interactivity::on_boxed_action` | `fn` | `onBoxedAction` | `div.swift:534` |
| 442 | `Interactivity::on_key_down` | `fn` | `onKeyDown` | `div.swift:546` |
| 458 | `Interactivity::capture_key_down` | `fn` | `captureKeyDown` | `div.swift:556` |
| 474 | `Interactivity::on_key_up` | `fn` | `onKeyUp` | `div.swift:566` |
| 487 | `Interactivity::capture_key_up` | `fn` | `captureKeyUp` | `div.swift:576` |
| 503 | `Interactivity::on_modifiers_changed` | `fn` | `onModifiersChanged` | `div.swift:586` |
| 517 | `Interactivity::on_drop` | `fn` | `onDrop` | `div.swift:594` |
| 528 | `Interactivity::can_drop` | `fn` | `canDrop` | `div.swift:604` |
| 539 | `Interactivity::on_click` | `fn` | `onClick` | `div.swift:610` |
| 552 | `Interactivity::on_aux_click` | `fn` | `onAuxClick` | `div.swift:616` |
| 568 | `Interactivity::on_drag` | `fn` | `onDrag` | `div.swift:622` |
| 594 | `Interactivity::on_hover` | `fn` | `onHover` | `div.swift:635` |
| 607 | `Interactivity::tooltip` | `fn` | `tooltip` | `div.swift:641` |
| 624 | `Interactivity::hoverable_tooltip` | `fn` | `hoverableTooltip` | `div.swift:647` |
| 644 | `Interactivity::occlude_mouse` | `fn` | `occludeMouse` | `div.swift:653` |
| 650 | `Interactivity::window_control_area` | `fn` | `windowControlArea` | `div.swift:657` |
| 658 | `Interactivity::block_mouse_except_scroll` | `fn` | `blockMouseExceptScroll` | `div.swift:661` |
| 665 | `InteractiveElement` | `trait` | `InteractiveElement` | `div.swift:1352` |
| 1161 | `StatefulInteractiveElement` | `trait` | `StatefulInteractiveElement` | `div.swift:1681` |
| 1319 | `MouseDownListener` | `type` | `MouseDownListener` | `div.swift:59` |
| 1321 | `MouseUpListener` | `type` | `MouseUpListener` | `div.swift:60` |
| 1323 | `MousePressureListener` | `type` | `MousePressureListener` | `div.swift:61` |
| 1325 | `MouseMoveListener` | `type` | `MouseMoveListener` | `div.swift:62` |
| 1328 | `ScrollWheelListener` | `type` | `ScrollWheelListener` | `div.swift:63` |
| 1331 | `PinchListener` | `type` | `PinchListener` | `div.swift:64` |
| 1334 | `RotationListener` | `type` | `RotationListener` | `div.swift:65` |
| 1337 | `ClickListener` | `type` | `ClickListener` | `div.swift:66` |
| 1339 | `DragListener` | `type` | `DragListener` | `div.swift:67` |
| 1346 | `TooltipBuilder` | `struct` | `TooltipBuilder` | `div.swift:89` |
| 1351 | `KeyDownListener` | `type` | `KeyDownListener` | `div.swift:81` |
| 1354 | `KeyUpListener` | `type` | `KeyUpListener` | `div.swift:82` |
| 1357 | `ModifiersChangedListener` | `type` | `ModifiersChangedListener` | `div.swift:83` |
| 1360 | `ActionListener` | `type` | `ActionListener` | `div.swift:84` |
| 1365 | `div` | `fn` | `div` | `div.swift:1796` |
| 1376 | `Div` | `struct` | `Div` | `div.swift:1801` |
| 1387 | `Div::on_children_prepainted` | `fn` | `onChildrenPrepainted` | `div.swift:1824` |
| 1396 | `Div::image_cache` | `fn` | `imageCache` | `div.swift:1832` |
| 1409 | `Div::with_dynamic_prepaint_order` | `fn` | `withDynamicPrepaintOrder` | `div.swift:1838` |
| 1424 | `DivFrameState` | `struct` | `DivFrameState` | `div.swift:2030` |
| 1430 | `DivInspectorState` | `struct` | `DivInspectorState` | `div.swift:2038` |
| 1654 | `Interactivity` | `struct` | `Interactivity` | `div.swift:278` |
| 1719 | `Interactivity::request_layout` | `fn` | `requestLayout` | `div.swift:666` |
| 1804 | `Interactivity::prepaint` | `fn` | `prepaint` | `div.swift:706` |
| 1970 | `Interactivity::paint` | `fn` | `paint` | `div.swift:756` |
| 2728 | `Interactivity::compute_style` | `fn` | `computeStyle` | `div.swift:831` |
| 2870 | `InteractiveElementState` | `struct` | `InteractiveElementState` | `div.swift:233` |
| 2882 | `ElementClickedState` | `struct` | `ElementClickedState` | `div.swift:204` |
| 2898 | `ElementHoverState` | `struct` | `ElementHoverState` | `div.swift:219` |
| 2906 | `ActiveTooltip` | `enum` | `ActiveTooltip` | `div.swift:102` |
| 2922 | `clear_active_tooltip` | `fn` | `clearActiveTooltip` | `div.swift:111` |
| 2934 | `clear_active_tooltip_if_not_hoverable` | `fn` | `clearActiveTooltipIfNotHoverable` | `div.swift:126` |
| 2950 | `set_tooltip_on_window` | `fn` | `setTooltipOnWindow` | `div.swift:144` |
| 2963 | `register_tooltip_mouse_handlers` | `fn` | `registerTooltipMouseHandlers` | `div.swift:161` |
| 3189 | `GroupHitboxes` | `struct` | `GroupHitboxes` | `div.swift:248` |
| 3194 | `GroupHitboxes::get` | `fn` | `get` | `div.swift:254` |
| 3202 | `GroupHitboxes::push` | `fn` | `push` | `div.swift:260` |
| 3210 | `GroupHitboxes::pop` | `fn` | `pop` | `div.swift:267` |
| 3216 | `Stateful` | `struct` | `Stateful` | `div.swift:2057` |
| 3328 | `ScrollAnchor` | `struct` | `ScrollAnchor` | `div.swift:2148` |
| 3335 | `ScrollAnchor::for_handle` | `fn` | `forHandle` | `div.swift:2161` |
| 3342 | `ScrollAnchor::scroll_to` | `fn` | `scrollTo` | `div.swift:2169` |
| 3381 | `ScrollHandle` | `struct` | `ScrollHandle` | `div.swift:2212` |
| 3391 | `ScrollHandle::new` | `fn` | `new` | `div.swift:2219` |
| 3396 | `ScrollHandle::offset` | `fn` | `offset` | `div.swift:2223` |
| 3401 | `ScrollHandle::max_offset` | `fn` | `maxOffset` | `div.swift:2227` |
| 3406 | `ScrollHandle::top_item` | `fn` | `topItem` | `div.swift:2231` |
| 3425 | `ScrollHandle::bottom_item` | `fn` | `bottomItem` | `div.swift:2241` |
| 3444 | `ScrollHandle::bounds` | `fn` | `bounds` | `div.swift:2251` |
| 3449 | `ScrollHandle::bounds_for_item` | `fn` | `boundsForItem` | `div.swift:2255` |
| 3454 | `ScrollHandle::scroll_to_item` | `fn` | `scrollToItem` | `div.swift:2260` |
| 3464 | `ScrollHandle::scroll_to_top_of_item` | `fn` | `scrollToTopOfItem` | `div.swift:2264` |
| 3524 | `ScrollHandle::scroll_to_bottom` | `fn` | `scrollToBottom` | `div.swift:2305` |
| 3532 | `ScrollHandle::set_offset` | `fn` | `setOffset` | `div.swift:2309` |
| 3538 | `ScrollHandle::logical_scroll_top` | `fn` | `logicalScrollTop` | `div.swift:2313` |
| 3553 | `ScrollHandle::logical_scroll_bottom` | `fn` | `logicalScrollBottom` | `div.swift:2321` |
| 3568 | `ScrollHandle::children_count` | `fn` | `childrenCount` | `div.swift:2329` |

</details>
