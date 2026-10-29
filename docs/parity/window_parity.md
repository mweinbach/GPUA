# API Parity Audit: `window.rs`

- **Generated At**: 2026-10-29T04:27:12Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/window.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/window.swift`
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/window/prompts.swift`
- **Ledger File**: `docs/parity/window_parity.json`

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **309** | 100.0% |
| Genuine Swift Implementations | 304 | 98.4% |
| Legitimate Ledger Exemptions | 5 | 1.6% |
| — *Deferred to Later Batch* | 5 | 1.6% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Legitimate Ledger Exemptions

| Upstream Item | Status | Target Batch | Technical Rationale |
| :--- | :--- | :--- | :--- |
| `ELEMENT_ARENA` | `deferred` | Batch 3.4 (Element Tree) | Requires ElementArena from Batch 3.4 |
| `Window::prepaint_index` | `deferred` | Batch 3.4 (Element Tree) | Requires ElementArena and AnyElement lifecycle from Batch 3.4 |
| `Window::reuse_prepaint` | `deferred` | Batch 3.4 (Element Tree) | Requires ElementArena and AnyElement lifecycle from Batch 3.4 |
| `Window::paint_index` | `deferred` | Batch 3.4 (Element Tree) | Requires ElementArena and AnyElement lifecycle from Batch 3.4 |
| `Window::reuse_paint` | `deferred` | Batch 3.4 (Element Tree) | Requires ElementArena and AnyElement lifecycle from Batch 3.4 |

## Genuine Swift Implementations

Found 304 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (304 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 72 | `SurfaceId` | `struct` | `SurfaceId` | `window.swift:19` |
| 78 | `SurfaceId::new` | `fn` | `new` | `window.swift:22` |
| 85 | `GpuiSurfaceHandle` | `struct` | `GpuiSurfaceHandle` | `window.swift:49` |
| 94 | `SurfaceState` | `struct` | `SurfaceState` | `window.swift:207` |
| 117 | `DEFAULT_WINDOW_SIZE` | `const` | `defaultWindowSize` | `window.swift:11` |
| 121 | `DEFAULT_ADDITIONAL_WINDOW_SIZE` | `const` | `defaultAdditionalWindowSize` | `window.swift:14` |
| 128 | `DispatchPhase` | `enum` | `DispatchPhase` | `window.swift:62` |
| 146 | `DispatchPhase::bubble` | `fn` | `bubble` | `window.swift:64` |
| 152 | `DispatchPhase::capture` | `fn` | `capture` | `window.swift:66` |
| 164 | `WindowInvalidator` | `struct` | `WindowInvalidator` | `window.swift:92` |
| 169 | `WindowInvalidator::new` | `fn` | `new` | `window.swift:96` |
| 179 | `WindowInvalidator::invalidate_view` | `fn` | `invalidateView` | `window.swift:106` |
| 191 | `WindowInvalidator::is_dirty` | `fn` | `isDirty` | `window.swift:120` |
| 195 | `WindowInvalidator::set_dirty` | `fn` | `setDirty` | `window.swift:126` |
| 199 | `WindowInvalidator::set_phase` | `fn` | `setPhase` | `window.swift:138` |
| 203 | `WindowInvalidator::take_views` | `fn` | `takeViews` | `window.swift:144` |
| 207 | `WindowInvalidator::replace_views` | `fn` | `replaceViews` | `window.swift:152` |
| 211 | `WindowInvalidator::not_drawing` | `fn` | `notDrawing` | `window.swift:158` |
| 216 | `WindowInvalidator::debug_assert_paint` | `fn` | `debugAssertPaint` | `window.swift:164` |
| 224 | `WindowInvalidator::debug_assert_prepaint` | `fn` | `debugAssertPrepaint` | `window.swift:168` |
| 232 | `WindowInvalidator::debug_assert_paint_or_prepaint` | `fn` | `debugAssertPaintOrPrepaint` | `window.swift:172` |
| 245 | `AnyWindowFocusListener` | `type` | `AnyWindowFocusListener` | `window.swift:202` |
| 248 | `WindowFocusEvent` | `struct` | `WindowFocusEvent` | `window.swift:524` |
| 254 | `WindowFocusEvent::is_focus_in` | `fn` | `isFocusIn` | `window.swift:533` |
| 258 | `WindowFocusEvent::is_focus_out` | `fn` | `isFocusOut` | `window.swift:537` |
| 264 | `FocusOutEvent` | `struct` | `FocusOutEvent` | `window.swift:543` |
| 271 | `FocusId` | `struct` | `FocusId` | `window.swift:281` |
| 287 | `with_element_arena` | `fn` | `withElementArena` | `window.swift:227` |
| 302 | `ElementArenaScope` | `struct` | `ElementArenaScope` | `window.swift:220` |
| 308 | `ElementArenaScope::enter` | `fn` | `enter` | `window.swift:221` |
| 328 | `ArenaClearNeeded` | `struct` | `ArenaClearNeeded` | `window.swift:186` |
| 334 | `ArenaClearNeeded::new` | `fn` | `new` | `window.swift:189` |
| 341 | `ArenaClearNeeded::clear` | `fn` | `clear` | `window.swift:197` |
| 349 | `FocusMap` | `type` | `FocusMap` | `window.swift:327` |
| 350 | `FocusRef` | `struct` | `FocusRef` | `window.swift:312` |
| 358 | `FocusId::is_focused` | `fn` | `isFocused` | `window.swift:292` |
| 364 | `FocusId::contains_focused` | `fn` | `containsFocused` | `window.swift:296` |
| 372 | `FocusId::within_focused` | `fn` | `withinFocused` | `window.swift:301` |
| 378 | `FocusId::contains` | `fn` | `contains` | `window.swift:306` |
| 387 | `FocusHandle` | `struct` | `FocusHandle` | `window.swift:397` |
| 403 | `FocusHandle::new` | `fn` | `new` | `window.swift:408` |
| 418 | `FocusHandle::for_id` | `fn` | `forId` | `window.swift:417` |
| 433 | `FocusHandle::tab_index` | `fn` | `tabIndex` | `window.swift:400` |
| 444 | `FocusHandle::tab_stop` | `fn` | `tabStop` | `window.swift:401` |
| 453 | `FocusHandle::downgrade` | `fn` | `downgrade` | `window.swift:450` |
| 461 | `FocusHandle::focus` | `fn` | `focus` | `window.swift:813` |
| 466 | `FocusHandle::is_focused` | `fn` | `isFocused` | `window.swift:454` |
| 472 | `FocusHandle::contains_focused` | `fn` | `containsFocused` | `window.swift:458` |
| 478 | `FocusHandle::within_focused` | `fn` | `withinFocused` | `window.swift:462` |
| 483 | `FocusHandle::contains` | `fn` | `contains` | `window.swift:466` |
| 488 | `FocusHandle::dispatch_action` | `fn` | `dispatchAction` | `window.swift:475` |
| 526 | `WeakFocusHandle` | `struct` | `WeakFocusHandle` | `window.swift:492` |
| 533 | `WeakFocusHandle::upgrade` | `fn` | `upgrade` | `window.swift:501` |
| 561 | `Focusable` | `trait` | `Focusable` | `prompts.swift:62` |
| 574 | `ManagedView` | `trait` | `ManagedView` | `window.swift:553` |
| 579 | `DismissEvent` | `struct` | `DismissEvent` | `window.swift:555` |
| 583 | `AnyMouseListener` | `type` | `AnyMouseListener` | `window.swift:559` |
| 587 | `CursorStyleRequest` | `struct` | `CursorStyleRequest` | `window.swift:561` |
| 593 | `HitTest` | `struct` | `HitTest` | `window.swift:769` |
| 600 | `WindowControlArea` | `enum` | `WindowControlArea` | `window.swift:571` |
| 613 | `HitboxId` | `struct` | `HitboxId` | `window.swift:582` |
| 622 | `HitboxId::is_hovered` | `fn` | `isHovered` | `window.swift:593` |
| 642 | `HitboxId::should_handle_scroll` | `fn` | `shouldHandleScroll` | `window.swift:603` |
| 654 | `Hitbox` | `struct` | `Hitbox` | `window.swift:616` |
| 683 | `Hitbox::is_hovered` | `fn` | `isHovered` | `window.swift:634` |
| 693 | `Hitbox::should_handle_scroll` | `fn` | `shouldHandleScroll` | `window.swift:638` |
| 700 | `HitboxBehavior` | `enum` | `HitboxBehavior` | `window.swift:609` |
| 759 | `TooltipId` | `struct` | `TooltipId` | `window.swift:644` |
| 763 | `TooltipId::is_hovered` | `fn` | `isHovered` | `window.swift:651` |
| 774 | `TooltipBounds` | `struct` | `TooltipBounds` | `window.swift:657` |
| 780 | `TooltipRequest` | `struct` | `TooltipRequest` | `window.swift:668` |
| 785 | `DeferredDraw` | `struct` | `DeferredDraw` | `window.swift:782` |
| 802 | `Frame` | `struct` | `Frame` | `window.swift:812` |
| 827 | `PrepaintStateIndex` | `struct` | `PrepaintStateIndex` | `window.swift:678` |
| 837 | `PaintIndex` | `struct` | `PaintIndex` | `window.swift:700` |
| 848 | `Frame::new` | `fn` | `new` | `window.swift:826` |
| 877 | `Frame::clear` | `fn` | `clear` | `window.swift:849` |
| 900 | `Frame::cursor_style` | `fn` | `cursorStyle` | `window.swift:865` |
| 913 | `Frame::hit_test` | `fn` | `hitTest` | `window.swift:878` |
| 937 | `Frame::focus_path` | `fn` | `focusPath` | `window.swift:900` |
| 943 | `Frame::finish` | `fn` | `finish` | `window.swift:905` |
| 963 | `Window` | `struct` | `Window` | `window.swift:1523` |
| 1057 | `InputRateTracker` | `struct` | `InputRateTracker` | `window.swift:725` |
| 1078 | `InputRateTracker::record_input` | `fn` | `recordInput` | `window.swift:744` |
| 1089 | `InputRateTracker::is_high_rate` | `fn` | `isHighRate` | `window.swift:754` |
| 1100 | `DrawPhase` | `enum` | `DrawPhase` | `window.swift:75` |
| 1115 | `ElementStateBox` | `struct` | `ElementStateBox` | `window.swift:760` |
| 1187 | `Window::new` | `fn` | `new` | `window.swift:1589` |
| 1715 | `Window::new_focus_listener` | `fn` | `newFocusListener` | `window.swift:2594` |
| 1725 | `DispatchEventResult` | `struct` | `DispatchEventResult` | `window.swift:798` |
| 1735 | `ContentMask` | `struct` | `ContentMask` | `window.swift:1121` |
| 1742 | `ContentMask::scale` | `fn` | `scale` | `window.swift:1122` |
| 1749 | `ContentMask::intersect` | `fn` | `intersect` | `window.swift:1126` |
| 1771 | `Window::observe_window_appearance` | `fn` | `observeWindowAppearance` | `window.swift:2023` |
| 1787 | `Window::observe_button_layout_changed` | `fn` | `observeButtonLayoutChanged` | `window.swift:2027` |
| 1803 | `Window::replace_root` | `fn` | `replaceRoot` | `window.swift:2047` |
| 1818 | `Window::root` | `fn` | `root` | `window.swift:1532` |
| 1828 | `Window::window_handle` | `fn` | `windowHandle` | `window.swift:2052` |
| 1833 | `Window::refresh` | `fn` | `refresh` | `window.swift:2056` |
| 1841 | `Window::remove_window` | `fn` | `removeWindow` | `window.swift:2060` |
| 1846 | `Window::focused` | `fn` | `focused` | `window.swift:1674` |
| 1852 | `Window::focus` | `fn` | `focus` | `window.swift:1542` |
| 1875 | `Window::blur` | `fn` | `blur` | `window.swift:1687` |
| 1885 | `Window::disable_focus` | `fn` | `disableFocus` | `window.swift:1698` |
| 1891 | `Window::focus_next` | `fn` | `focusNext` | `window.swift:1703` |
| 1902 | `Window::focus_prev` | `fn` | `focusPrev` | `window.swift:1710` |
| 1913 | `Window::text_system` | `fn` | `textSystem` | `window.swift:2946` |
| 1918 | `Window::text_style` | `fn` | `textStyle` | `window.swift:2953` |
| 1929 | `Window::is_maximized` | `fn` | `isMaximized` | `window.swift:2065` |
| 1934 | `Window::request_decorations` | `fn` | `requestDecorations` | `window.swift:3232` |
| 1939 | `Window::start_window_resize` | `fn` | `startWindowResize` | `window.swift:3236` |
| 1945 | `Window::window_bounds` | `fn` | `windowBounds` | `window.swift:2077` |
| 1950 | `Window::inner_window_bounds` | `fn` | `innerWindowBounds` | `window.swift:2081` |
| 1955 | `Window::dispatch_action` | `fn` | `dispatchAction` | `window.swift:2395` |
| 1971 | `Window::dispatch_action_on_view` | `fn` | `dispatchActionOnView` | `window.swift:2404` |
| 1982 | `Window::dispatch_keystroke_observers` | `fn` | `dispatchKeystrokeObservers` | `window.swift:2656` |
| 2006 | `Window::dispatch_keystroke_interceptors` | `fn` | `dispatchKeystrokeInterceptors` | `window.swift:2671` |
| 2033 | `Window::defer` | `fn` | `defer` | `window.swift:3105` |
| 2043 | `Window::observe` | `fn` | `observe` | `window.swift:3112` |
| 2072 | `Window::subscribe` | `fn` | `subscribe` | `window.swift:3124` |
| 2107 | `Window::observe_release` | `fn` | `observeRelease` | `window.swift:3135` |
| 2131 | `Window::to_async` | `fn` | `toAsync` | `window.swift:3156` |
| 2136 | `Window::on_next_frame` | `fn` | `onNextFrame` | `window.swift:2003` |
| 2146 | `Window::request_animation_frame` | `fn` | `requestAnimationFrame` | `window.swift:2007` |
| 2155 | `Window::spawn` | `fn` | `spawn` | `window.swift:3161` |
| 2171 | `Window::spawn_with_priority` | `fn` | `spawnWithPriority` | `window.swift:3166` |
| 2212 | `Window::bounds` | `fn` | `bounds` | `window.swift:2073` |
| 2220 | `Window::render_to_image` | `fn` | `renderToImage` | `window.swift:3228` |
| 2226 | `Window::resize` | `fn` | `resize` | `window.swift:2085` |
| 2231 | `Window::is_fullscreen` | `fn` | `isFullscreen` | `window.swift:2069` |
| 2235 | `Window::appearance_changed` | `fn` | `appearanceChanged` | `window.swift:2031` |
| 2245 | `Window::button_layout_changed` | `fn` | `buttonLayoutChanged` | `window.swift:2038` |
| 2252 | `Window::appearance` | `fn` | `appearance` | `window.swift:2093` |
| 2257 | `Window::titlebar_height` | `fn` | `titlebarHeight` | `window.swift:2097` |
| 2263 | `Window::window_controls_padding` | `fn` | `windowControlsPadding` | `window.swift:2101` |
| 2268 | `Window::viewport_size` | `fn` | `viewportSize` | `window.swift:1528` |
| 2277 | `Window::mouse_position_in_window` | `fn` | `mousePositionInWindow` | `window.swift:2105` |
| 2306 | `Window::safe_area_insets` | `fn` | `safeAreaInsets` | `window.swift:3244` |
| 2311 | `Window::is_window_active` | `fn` | `isWindowActive` | `window.swift:2109` |
| 2318 | `Window::is_window_hovered` | `fn` | `isWindowHovered` | `window.swift:2113` |
| 2331 | `Window::zoom_window` | `fn` | `zoomWindow` | `window.swift:2121` |
| 2336 | `Window::show_window_menu` | `fn` | `showWindowMenu` | `window.swift:3248` |
| 2344 | `Window::start_window_move` | `fn` | `startWindowMove` | `window.swift:3240` |
| 2349 | `Window::set_client_inset` | `fn` | `setClientInset` | `window.swift:2141` |
| 2355 | `Window::client_inset` | `fn` | `clientInset` | `window.swift:2137` |
| 2360 | `Window::window_decorations` | `fn` | `windowDecorations` | `window.swift:3252` |
| 2365 | `Window::window_controls` | `fn` | `windowControls` | `window.swift:3256` |
| 2370 | `Window::set_window_title` | `fn` | `setWindowTitle` | `window.swift:2133` |
| 2375 | `Window::set_app_id` | `fn` | `setAppId` | `window.swift:3260` |
| 2380 | `Window::set_background_appearance` | `fn` | `setBackgroundAppearance` | `window.swift:2146` |
| 2386 | `Window::set_background_color` | `fn` | `setBackgroundColor` | `window.swift:2151` |
| 2391 | `Window::set_window_edited` | `fn` | `setWindowEdited` | `window.swift:3264` |
| 2396 | `Window::display` | `fn` | `display` | `window.swift:3268` |
| 2404 | `Window::show_character_palette` | `fn` | `showCharacterPalette` | `window.swift:3272` |
| 2414 | `Window::raw_native_view_ptr` | `fn` | `rawNativeViewPtr` | `window.swift:3276` |
| 2429 | `Window::native_toolbar_item_bounds` | `fn` | `nativeToolbarItemBounds` | `window.swift:3280` |
| 2436 | `Window::push_native_view_override` | `fn` | `pushNativeViewOverride` | `window.swift:3284` |
| 2442 | `Window::pop_native_view_override` | `fn` | `popNativeViewOverride` | `window.swift:3288` |
| 2453 | `Window::register_surface` | `fn` | `registerSurface` | `window.swift:3292` |
| 2491 | `Window::unregister_surface` | `fn` | `unregisterSurface` | `window.swift:3296` |
| 2500 | `Window::surface_native_view_ptr` | `fn` | `surfaceNativeViewPtr` | `window.swift:3300` |
| 2506 | `Window::invalidate_surface` | `fn` | `invalidateSurface` | `window.swift:3304` |
| 2529 | `Window::update_surface_root_view` | `fn` | `updateSurfaceRootView` | `window.swift:3308` |
| 2549 | `Window::scale_factor` | `fn` | `scaleFactor` | `window.swift:1527` |
| 2555 | `Window::rem_size` | `fn` | `remSize` | `window.swift:1529` |
| 2564 | `Window::set_rem_size` | `fn` | `setRemSize` | `window.swift:3178` |
| 2570 | `Window::with_global_id` | `fn` | `withGlobalId` | `window.swift:2798` |
| 2584 | `Window::with_id` | `fn` | `withId` | `window.swift:2792` |
| 2601 | `Window::with_rem_size` | `fn` | `withRemSize` | `window.swift:3183` |
| 2618 | `Window::line_height` | `fn` | `lineHeight` | `window.swift:3192` |
| 2624 | `Window::prevent_default` | `fn` | `preventDefault` | `window.swift:2717` |
| 2629 | `Window::default_prevented` | `fn` | `defaultPrevented` | `window.swift:1567` |
| 2634 | `Window::is_action_available` | `fn` | `isActionAvailable` | `window.swift:2457` |
| 2643 | `Window::is_action_available_in` | `fn` | `isActionAvailableIn` | `window.swift:2465` |
| 2651 | `Window::mouse_position` | `fn` | `mousePosition` | `window.swift:1537` |
| 2661 | `Window::capture_pointer` | `fn` | `capturePointer` | `window.swift:2725` |
| 2666 | `Window::release_pointer` | `fn` | `releasePointer` | `window.swift:2729` |
| 2671 | `Window::captured_hitbox` | `fn` | `capturedHitbox` | `window.swift:1563` |
| 2676 | `Window::modifiers` | `fn` | `modifiers` | `window.swift:1539` |
| 2682 | `Window::last_input_was_keyboard` | `fn` | `lastInputWasKeyboard` | `window.swift:2733` |
| 2687 | `Window::capslock` | `fn` | `capslock` | `window.swift:1540` |
| 2698 | `Window::draw` | `fn` | `draw` | `window.swift:1956` |
| 3431 | `Window::with_text_style` | `fn` | `withTextStyle` | `window.swift:2844` |
| 3448 | `Window::set_cursor_style` | `fn` | `setCursorStyle` | `window.swift:2737` |
| 3460 | `Window::set_window_cursor_style` | `fn` | `setWindowCursorStyle` | `window.swift:2741` |
| 3470 | `Window::set_tooltip` | `fn` | `setTooltip` | `window.swift:2745` |
| 3484 | `Window::with_content_mask` | `fn` | `withContentMask` | `window.swift:1902` |
| 3503 | `Window::with_element_offset` | `fn` | `withElementOffset` | `window.swift:1917` |
| 3521 | `Window::with_absolute_element_offset` | `fn` | `withAbsoluteElementOffset` | `window.swift:2812` |
| 3533 | `Window::with_element_opacity` | `fn` | `withElementOpacity` | `window.swift:2819` |
| 3556 | `Window::transact` | `fn` | `transact` | `window.swift:3174` |
| 3584 | `Window::request_autoscroll` | `fn` | `requestAutoscroll` | `window.swift:2011` |
| 3591 | `Window::take_autoscroll` | `fn` | `takeAutoscroll` | `window.swift:2015` |
| 3601 | `Window::use_asset` | `fn` | `useAsset` | `window.swift:2855` |
| 3628 | `Window::get_asset` | `fn` | `getAsset` | `window.swift:2859` |
| 3634 | `Window::element_offset` | `fn` | `elementOffset` | `window.swift:2863` |
| 3645 | `Window::element_opacity` | `fn` | `elementOpacity` | `window.swift:1547` |
| 3651 | `Window::content_mask` | `fn` | `contentMask` | `window.swift:1913` |
| 3666 | `Window::with_element_namespace` | `fn` | `withElementNamespace` | `window.swift:2806` |
| 3678 | `Window::use_keyed_state` | `fn` | `useKeyedState` | `window.swift:2850` |
| 3707 | `Window::use_state` | `fn` | `useState` | `window.swift:1764` |
| 3723 | `Window::with_element_state` | `fn` | `withElementState` | `window.swift:1750` |
| 3804 | `Window::with_optional_element_state` | `fn` | `withOptionalElementState` | `window.swift:2826` |
| 3833 | `Window::with_tab_group` | `fn` | `withTabGroup` | `window.swift:2830` |
| 3849 | `Window::defer_draw` | `fn` | `deferDraw` | `window.swift:1938` |
| 3867 | `Window::defer_draw_with_target` | `fn` | `deferDrawWithTarget` | `window.swift:2883` |
| 3900 | `Window::paint_layer` | `fn` | `paintLayer` | `window.swift:2892` |
| 3924 | `Window::paint_shadows` | `fn` | `paintShadows` | `window.swift:2896` |
| 3957 | `Window::paint_quad` | `fn` | `paintQuad` | `window.swift:1820` |
| 3978 | `Window::paint_path` | `fn` | `paintPath` | `window.swift:1828` |
| 3995 | `Window::paint_underline` | `fn` | `paintUnderline` | `window.swift:1832` |
| 4030 | `Window::paint_strikethrough` | `fn` | `paintStrikethrough` | `window.swift:1870` |
| 4066 | `Window::paint_glyph` | `fn` | `paintGlyph` | `window.swift:2961` |
| 4162 | `Window::paint_emoji` | `fn` | `paintEmoji` | `window.swift:3015` |
| 4218 | `Window::paint_svg` | `fn` | `paintSvg` | `window.swift:2928` |
| 4284 | `Window::paint_image` | `fn` | `paintImage` | `window.swift:3062` |
| 4336 | `Window::paint_surface` | `fn` | `paintSurface` | `window.swift:1896` |
| 4353 | `Window::drop_image` | `fn` | `dropImage` | `window.swift:3081` |
| 4372 | `Window::request_layout` | `fn` | `requestLayout` | `window.swift:1778` |
| 4401 | `Window::request_measured_layout` | `fn` | `requestMeasuredLayout` | `window.swift:1793` |
| 4421 | `Window::compute_layout` | `fn` | `computeLayout` | `window.swift:1808` |
| 4438 | `Window::layout_bounds` | `fn` | `layoutBounds` | `window.swift:1814` |
| 4457 | `Window::insert_hitbox` | `fn` | `insertHitbox` | `window.swift:1719` |
| 4476 | `Window::insert_window_control_hitbox` | `fn` | `insertWindowControlHitbox` | `window.swift:1731` |
| 4485 | `Window::set_key_context` | `fn` | `setKeyContext` | `window.swift:2867` |
| 4494 | `Window::set_focus_handle` | `fn` | `setFocusHandle` | `window.swift:2871` |
| 4507 | `Window::set_view_id` | `fn` | `setViewId` | `window.swift:2875` |
| 4513 | `Window::current_view` | `fn` | `currentView` | `window.swift:2879` |
| 4519 | `Window::with_rendered_view` | `fn` | `withRenderedView` | `window.swift:2834` |
| 4531 | `Window::with_image_cache` | `fn` | `withImageCache` | `window.swift:2840` |
| 4553 | `Window::handle_input` | `fn` | `handleInput` | `window.swift:2623` |
| 4581 | `Window::on_mouse_event` | `fn` | `onMouseEvent` | `window.swift:2533` |
| 4604 | `Window::on_key_event` | `fn` | `onKeyEvent` | `window.swift:2543` |
| 4625 | `Window::on_modifiers_changed` | `fn` | `onModifiersChanged` | `window.swift:2553` |
| 4641 | `Window::on_focus_in` | `fn` | `onFocusIn` | `window.swift:2560` |
| 4661 | `Window::on_focus_out` | `fn` | `onFocusOut` | `window.swift:2577` |
| 4711 | `Window::dispatch_keystroke` | `fn` | `dispatchKeystroke` | `window.swift:2605` |
| 4738 | `Window::keystroke_text_for` | `fn` | `keystrokeTextFor` | `window.swift:2524` |
| 4753 | `Window::dispatch_event` | `fn` | `dispatchEvent` | `window.swift:2161` |
| 5285 | `Window::pending_input_changed` | `fn` | `pendingInputChanged` | `window.swift:2688` |
| 5343 | `Window::has_pending_keystrokes` | `fn` | `hasPendingKeystrokes` | `window.swift:2699` |
| 5347 | `Window::clear_pending_keystrokes` | `fn` | `clearPendingKeystrokes` | `window.swift:2703` |
| 5352 | `Window::pending_input_keystrokes` | `fn` | `pendingInputKeystrokes` | `window.swift:2707` |
| 5507 | `Window::observe_global` | `fn` | `observeGlobal` | `window.swift:3144` |
| 5526 | `Window::activate_window` | `fn` | `activateWindow` | `window.swift:2117` |
| 5531 | `Window::minimize_window` | `fn` | `minimizeWindow` | `window.swift:2125` |
| 5536 | `Window::toggle_fullscreen` | `fn` | `toggleFullscreen` | `window.swift:2129` |
| 5541 | `Window::invalidate_character_coordinates` | `fn` | `invalidateCharacterCoordinates` | `window.swift:2711` |
| 5555 | `Window::prompt` | `fn` | `prompt` | `window.swift:3197` |
| 5610 | `Window::context_stack` | `fn` | `contextStack` | `window.swift:2518` |
| 5627 | `Window::available_actions` | `fn` | `availableActions` | `window.swift:2472` |
| 5643 | `Window::bindings_for_action` | `fn` | `bindingsForAction` | `window.swift:2477` |
| 5651 | `Window::highest_precedence_binding_for_action` | `fn` | `highestPrecedenceBindingForAction` | `window.swift:2482` |
| 5661 | `Window::bindings_for_action_in_context` | `fn` | `bindingsForActionInContext` | `window.swift:2487` |
| 5672 | `Window::highest_precedence_binding_for_action_in_context` | `fn` | `highestPrecedenceBindingForActionInContext` | `window.swift:2491` |
| 5684 | `Window::bindings_for_action_in` | `fn` | `bindingsForActionIn` | `window.swift:2495` |
| 5699 | `Window::highest_precedence_binding_for_action_in` | `fn` | `highestPrecedenceBindingForActionIn` | `window.swift:2504` |
| 5710 | `Window::possible_bindings_for_input` | `fn` | `possibleBindingsForInput` | `window.swift:2513` |
| 5739 | `Window::listener_for` | `fn` | `listenerFor` | `window.swift:2762` |
| 5751 | `Window::handler_for` | `fn` | `handlerFor` | `window.swift:2774` |
| 5764 | `Window::on_window_should_close` | `fn` | `onWindowShouldClose` | `window.swift:2786` |
| 5783 | `Window::on_action` | `fn` | `onAction` | `window.swift:2438` |
| 5803 | `Window::on_action_when` | `fn` | `onActionWhen` | `window.swift:2446` |
| 5820 | `Window::gpu_specs` | `fn` | `gpuSpecs` | `window.swift:3312` |
| 5826 | `Window::titlebar_double_click` | `fn` | `titlebarDoubleClick` | `window.swift:3316` |
| 5832 | `Window::window_title` | `fn` | `windowTitle` | `window.swift:1559` |
| 5838 | `Window::tabbed_windows` | `fn` | `tabbedWindows` | `window.swift:3320` |
| 5844 | `Window::tab_bar_visible` | `fn` | `tabBarVisible` | `window.swift:3324` |
| 5850 | `Window::merge_all_windows` | `fn` | `mergeAllWindows` | `window.swift:3328` |
| 5856 | `Window::move_tab_to_new_window` | `fn` | `moveTabToNewWindow` | `window.swift:3332` |
| 5862 | `Window::toggle_window_tab_overview` | `fn` | `toggleWindowTabOverview` | `window.swift:3336` |
| 5868 | `Window::set_tabbing_identifier` | `fn` | `setTabbingIdentifier` | `window.swift:3340` |
| 5875 | `Window::toggle_inspector` | `fn` | `toggleInspector` | `window.swift:3344` |
| 5884 | `Window::is_inspector_picking` | `fn` | `isInspectorPicking` | `window.swift:3349` |
| 5896 | `Window::with_inspector_state` | `fn` | `withInspectorState` | `window.swift:3353` |
| 5917 | `Window::build_inspector_element_id` | `fn` | `buildInspectorElementId` | `window.swift:3357` |
| 5960 | `Window::insert_inspector_hitbox` | `fn` | `insertInspectorHitbox` | `window.swift:3361` |
| 6065 | `Window::set_modifiers` | `fn` | `setModifiers` | `window.swift:2752` |
| 6073 | `Window::simulate_mouse_move` | `fn` | `simulateMouseMove` | `window.swift:2757` |
| 6086 | `WindowId` | `struct` | `WindowId` | `window.swift:1008` |
| 6091 | `WindowId::as_u64` | `fn` | `asU64` | `window.swift:1023` |
| 6105 | `WindowHandle` | `struct` | `WindowHandle` | `window.swift:1070` |
| 6123 | `WindowHandle::new` | `fn` | `new` | `window.swift:1073` |
| 6137 | `WindowHandle::root` | `fn` | `root` | `window.swift:1532` |
| 6151 | `WindowHandle::update` | `fn` | `update` | `window.swift:1082` |
| 6171 | `WindowHandle::read` | `fn` | `read` | `window.swift:1087` |
| 6190 | `WindowHandle::read_with` | `fn` | `readWith` | `window.swift:1092` |
| 6200 | `WindowHandle::entity` | `fn` | `entity` | `window.swift:1097` |
| 6211 | `WindowHandle::is_active` | `fn` | `isActive` | `window.swift:1436` |
| 6247 | `AnyWindowHandle` | `struct` | `AnyWindowHandle` | `window.swift:1029` |
| 6254 | `AnyWindowHandle::window_id` | `fn` | `windowId` | `window.swift:1036` |
| 6260 | `AnyWindowHandle::downcast` | `fn` | `downcast` | `window.swift:1040` |
| 6274 | `AnyWindowHandle::update` | `fn` | `update` | `window.swift:1045` |
| 6288 | `AnyWindowHandle::read` | `fn` | `read` | `window.swift:1059` |
| 6320 | `ElementId` | `enum` | `ElementId` | `window.swift:233` |
| 6343 | `ElementId::named_usize` | `fn` | `namedUsize` | `window.swift:246` |
| 6477 | `PaintQuad` | `struct` | `PaintQuad` | `window.swift:1134` |
| 6494 | `PaintQuad::corner_radii` | `fn` | `cornerRadii` | `window.swift:1136` |
| 6502 | `PaintQuad::border_widths` | `fn` | `borderWidths` | `window.swift:1138` |
| 6510 | `PaintQuad::border_color` | `fn` | `borderColor` | `window.swift:1139` |
| 6518 | `PaintQuad::background` | `fn` | `background` | `window.swift:1137` |
| 6527 | `quad` | `fn` | `quad` | `window.swift:1195` |
| 6546 | `fill` | `fn` | `fill` | `window.swift:1182` |
| 6558 | `outline` | `fn` | `outline` | `window.swift:1241` |

</details>
