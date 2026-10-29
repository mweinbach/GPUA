# API Parity Audit: `app.rs`

- **Generated At**: 2026-10-29T02:53:12Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/app.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app.swift`
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app/entity_map.swift`
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app/app_context.swift`
- **Ledger File**: `docs/parity/app_parity.json`

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **186** | 100.0% |
| Genuine Swift Implementations | 177 | 95.2% |
| Legitimate Ledger Exemptions | 9 | 4.8% |
| — *Deferred to Later Batch* | 2 | 1.1% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 7 | 3.8% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Legitimate Ledger Exemptions

| Upstream Item | Status | Target Batch | Technical Rationale |
| :--- | :--- | :--- | :--- |
| `Application::text_system` | `deferred` | Batch 3.3 (TestPlatform / Text System) | Text system queries and layout pipeline are scheduled for Batch 3.3 implementation. |
| `App::text_system` | `deferred` | Batch 3.3 (TestPlatform / Text System) | Text system queries and layout pipeline are scheduled for Batch 3.3 implementation. |
| `AppCell` | `omitted` | Batch 3.1 (App Model) | Rust-specific RefCell wrapper for interior mutability; Swift uses reference types and actor isolation. |
| `AppCell::borrow` | `omitted` | Batch 3.1 (App Model) | Rust RefCell borrow method; not needed with Swift reference semantics and actor isolation. |
| `AppCell::borrow_mut` | `omitted` | Batch 3.1 (App Model) | Rust RefCell mutable borrow method; not needed with Swift reference semantics and actor isolation. |
| `AppCell::try_borrow_mut` | `omitted` | Batch 3.1 (App Model) | Rust RefCell try_borrow_mut method; not needed with Swift reference semantics and actor isolation. |
| `AppRef` | `omitted` | Batch 3.1 (App Model) | Rust RefCell RAII immutability guard; not needed in Swift reference model. |
| `AppRefMut` | `omitted` | Batch 3.1 (App Model) | Rust RefCell RAII mutable borrow guard; not needed in Swift reference model. |
| `App::ref_counts_drop_handle` | `omitted` | Batch 3.1 (App Model) | Internal Rust Rc/RefCell drop handle for reference count tracking; Swift ARC handles deallocation natively. |

## Genuine Swift Implementations

Found 177 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (177 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 71 | `SHUTDOWN_TIMEOUT` | `const` | `shutdownTimeout` | `app.swift:13` |
| 140 | `Application` | `struct` | `Application` | `app.swift:591` |
| 172 | `Application::with_platform` | `fn` | `withPlatform` | `app.swift:598` |
| 181 | `Application::with_assets` | `fn` | `withAssets` | `app.swift:603` |
| 191 | `Application::with_http_client` | `fn` | `withHttpClient` | `app.swift:608` |
| 200 | `Application::with_quit_mode` | `fn` | `withQuitMode` | `app.swift:613` |
| 207 | `Application::run` | `fn` | `run` | `app.swift:618` |
| 224 | `Application::on_open_urls` | `fn` | `onOpenUrls` | `app.swift:625` |
| 234 | `Application::on_reopen` | `fn` | `onReopen` | `app.swift:630` |
| 248 | `Application::background_executor` | `fn` | `backgroundExecutor` | `app.swift:638` |
| 253 | `Application::foreground_executor` | `fn` | `foregroundExecutor` | `app.swift:642` |
| 263 | `Application::path_for_auxiliary_executable` | `fn` | `pathForAuxiliaryExecutable` | `app.swift:646` |
| 270 | `KeystrokeObserver` | `type` | `KeystrokeObserver` | `app.swift:276` |
| 279 | `QuitMode` | `enum` | `QuitMode` | `app.swift:16` |
| 291 | `SystemWindowTab` | `struct` | `SystemWindowTab` | `app.swift:49` |
| 300 | `SystemWindowTab::new` | `fn` | `new` | `app.swift:62` |
| 312 | `SystemWindowTabController` | `struct` | `SystemWindowTabController` | `app.swift:68` |
| 321 | `SystemWindowTabController::new` | `fn` | `new` | `app.swift:81` |
| 329 | `SystemWindowTabController::init` | `fn` | `init` | `app.swift:72` |
| 334 | `SystemWindowTabController::tab_groups` | `fn` | `tabGroups` | `app.swift:90` |
| 339 | `SystemWindowTabController::get_next_tab_group_window` | `fn` | `getNextTabGroupWindow` | `app.swift:95` |
| 364 | `SystemWindowTabController::get_prev_tab_group_window` | `fn` | `getPrevTabGroupWindow` | `app.swift:106` |
| 393 | `SystemWindowTabController::tabs` | `fn` | `tabs` | `app.swift:116` |
| 400 | `SystemWindowTabController::init_visible` | `fn` | `initVisible` | `app.swift:121` |
| 408 | `SystemWindowTabController::is_visible` | `fn` | `isVisible` | `app.swift:129` |
| 413 | `SystemWindowTabController::set_visible` | `fn` | `setVisible` | `app.swift:134` |
| 419 | `SystemWindowTabController::update_last_active` | `fn` | `updateLastActive` | `app.swift:141` |
| 431 | `SystemWindowTabController::update_tab_position` | `fn` | `updateTabPosition` | `app.swift:152` |
| 445 | `SystemWindowTabController::update_tab_title` | `fn` | `updateTabTitle` | `app.swift:169` |
| 469 | `SystemWindowTabController::add_tab` | `fn` | `addTab` | `app.swift:186` |
| 502 | `SystemWindowTabController::remove_tab` | `fn` | `removeTab` | `app.swift:209` |
| 517 | `SystemWindowTabController::move_tab_to_new_window` | `fn` | `moveTabToNewWindow` | `app.swift:225` |
| 528 | `SystemWindowTabController::merge_all_windows` | `fn` | `mergeAllWindows` | `app.swift:236` |
| 546 | `SystemWindowTabController::select_next_tab` | `fn` | `selectNextTab` | `app.swift:251` |
| 561 | `SystemWindowTabController::select_previous_tab` | `fn` | `selectPreviousTab` | `app.swift:262` |
| 580 | `GpuiMode` | `enum` | `GpuiMode` | `app.swift:30` |
| 590 | `GpuiMode::test` | `fn` | `test` | `app.swift:31` |
| 597 | `GpuiMode::skip_drawing` | `fn` | `skipDrawing` | `app.swift:38` |
| 609 | `App` | `struct` | `App` | `app.swift:682` |
| 693 | `App::new_app` | `fn` | `newApp` | `app.swift:764` |
| 830 | `App::leak_detector_snapshot` | `fn` | `leakDetectorSnapshot` | `entity_map.swift:620` |
| 846 | `App::assert_no_new_leaks` | `fn` | `assertNoNewLeaks` | `entity_map.swift:144` |
| 852 | `App::shutdown` | `fn` | `shutdown` | `app.swift:1404` |
| 880 | `App::keyboard_layout` | `fn` | `keyboardLayout` | `app.swift:1477` |
| 885 | `App::keyboard_mapper` | `fn` | `keyboardMapper` | `app.swift:1481` |
| 890 | `App::on_keyboard_layout_change` | `fn` | `onKeyboardLayoutChange` | `app.swift:1485` |
| 906 | `App::quit` | `fn` | `quit` | `app.swift:1423` |
| 912 | `App::refresh_windows` | `fn` | `refreshWindows` | `app.swift:1189` |
| 916 | `App::update` | `fn` | `update` | `app.swift:793` |
| 923 | `App::start_update` | `fn` | `startUpdate` | `app.swift:778` |
| 927 | `App::finish_update` | `fn` | `finishUpdate` | `app.swift:782` |
| 937 | `App::observe` | `fn` | `observe` | `app.swift:976` |
| 951 | `App::detect_accessed_entities` | `fn` | `detectAccessedEntities` | `app.swift:1219` |
| 967 | `App::record_entities_accessed` | `fn` | `recordEntitiesAccessed` | `app.swift:1226` |
| 994 | `App::new_observer` | `fn` | `newObserver` | `app.swift:983` |
| 1000 | `App::observe_internal` | `fn` | `observeInternal` | `app.swift:989` |
| 1024 | `App::subscribe` | `fn` | `subscribe` | `app.swift:1000` |
| 1039 | `App::new_subscription` | `fn` | `newSubscription` | `app.swift:1007` |
| 1048 | `App::subscribe_internal` | `fn` | `subscribeInternal` | `app.swift:1013` |
| 1078 | `App::windows` | `fn` | `windows` | `app.swift:1157` |
| 1090 | `App::window_stack` | `fn` | `windowStack` | `app.swift:1161` |
| 1095 | `App::active_window` | `fn` | `activeWindow` | `app.swift:1165` |
| 1102 | `App::open_window` | `fn` | `openWindow` | `app.swift:1169` |
| 1138 | `App::activate` | `fn` | `activate` | `app.swift:1428` |
| 1143 | `App::hide` | `fn` | `hide` | `app.swift:1432` |
| 1148 | `App::hide_other_apps` | `fn` | `hideOtherApps` | `app.swift:1436` |
| 1153 | `App::unhide_other_apps` | `fn` | `unhideOtherApps` | `app.swift:1440` |
| 1158 | `App::displays` | `fn` | `displays` | `app.swift:1444` |
| 1163 | `App::primary_display` | `fn` | `primaryDisplay` | `app.swift:1448` |
| 1168 | `App::is_screen_capture_supported` | `fn` | `isScreenCaptureSupported` | `app.swift:1456` |
| 1173 | `App::screen_capture_sources` | `fn` | `screenCaptureSources` | `app.swift:1460` |
| 1180 | `App::find_display` | `fn` | `findDisplay` | `app.swift:1452` |
| 1188 | `App::thermal_state` | `fn` | `thermalState` | `app.swift:1464` |
| 1193 | `App::on_thermal_state_change` | `fn` | `onThermalStateChange` | `app.swift:1468` |
| 1209 | `App::window_appearance` | `fn` | `windowAppearance` | `app.swift:1494` |
| 1214 | `App::button_layout` | `fn` | `buttonLayout` | `app.swift:1498` |
| 1219 | `App::read_from_clipboard` | `fn` | `readFromClipboard` | `app.swift:1502` |
| 1224 | `App::set_text_rendering_mode` | `fn` | `setTextRenderingMode` | `app.swift:1526` |
| 1229 | `App::text_rendering_mode` | `fn` | `textRenderingMode` | `app.swift:1530` |
| 1234 | `App::write_to_clipboard` | `fn` | `writeToClipboard` | `app.swift:1506` |
| 1241 | `App::read_from_primary` | `fn` | `readFromPrimary` | `app.swift:1510` |
| 1248 | `App::write_to_primary` | `fn` | `writeToPrimary` | `app.swift:1514` |
| 1258 | `App::read_from_find_pasteboard` | `fn` | `readFromFindPasteboard` | `app.swift:1518` |
| 1268 | `App::write_to_find_pasteboard` | `fn` | `writeToFindPasteboard` | `app.swift:1522` |
| 1273 | `App::write_credentials` | `fn` | `writeCredentials` | `app.swift:1534` |
| 1283 | `App::read_credentials` | `fn` | `readCredentials` | `app.swift:1538` |
| 1288 | `App::delete_credentials` | `fn` | `deleteCredentials` | `app.swift:1542` |
| 1293 | `App::open_url` | `fn` | `openUrl` | `app.swift:1546` |
| 1303 | `App::register_url_scheme` | `fn` | `registerUrlScheme` | `app.swift:1550` |
| 1310 | `App::app_path` | `fn` | `appPath` | `app.swift:1554` |
| 1317 | `App::compositor_name` | `fn` | `compositorName` | `app.swift:1558` |
| 1322 | `App::path_for_auxiliary_executable` | `fn` | `pathForAuxiliaryExecutable` | `app.swift:1562` |
| 1331 | `App::prompt_for_paths` | `fn` | `promptForPaths` | `app.swift:1566` |
| 1344 | `App::prompt_for_new_path` | `fn` | `promptForNewPath` | `app.swift:1570` |
| 1353 | `App::reveal_path` | `fn` | `revealPath` | `app.swift:1574` |
| 1358 | `App::open_with_system` | `fn` | `openWithSystem` | `app.swift:1578` |
| 1363 | `App::should_auto_hide_scrollbars` | `fn` | `shouldAutoHideScrollbars` | `app.swift:1582` |
| 1368 | `App::restart` | `fn` | `restart` | `app.swift:1412` |
| 1376 | `App::set_restart_path` | `fn` | `setRestartPath` | `app.swift:1419` |
| 1381 | `App::http_client` | `fn` | `httpClient` | `app.swift:1586` |
| 1386 | `App::set_http_client` | `fn` | `setHttpClient` | `app.swift:1590` |
| 1392 | `App::set_quit_mode` | `fn` | `setQuitMode` | `app.swift:1594` |
| 1397 | `App::svg_renderer` | `fn` | `svgRenderer` | `app.swift:1598` |
| 1401 | `App::push_effect` | `fn` | `pushEffect` | `app.swift:799` |
| 1629 | `App::to_async` | `fn` | `toAsync` | `app.swift:1753` |
| 1638 | `App::background_executor` | `fn` | `backgroundExecutor` | `app.swift:1731` |
| 1643 | `App::foreground_executor` | `fn` | `foregroundExecutor` | `app.swift:1735` |
| 1653 | `App::spawn` | `fn` | `spawn` | `app.swift:1739` |
| 1671 | `App::spawn_with_priority` | `fn` | `spawnWithPriority` | `app.swift:1746` |
| 1688 | `App::defer` | `fn` | `defer` | `app.swift:921` |
| 1695 | `App::asset_source` | `fn` | `assetSource` | `app.swift:1660` |
| 1705 | `App::has_global` | `fn` | `hasGlobal` | `app.swift:1095` |
| 1711 | `App::global` | `fn` | `global` | `app.swift:1084` |
| 1720 | `App::try_global` | `fn` | `tryGlobal` | `app.swift:1091` |
| 1728 | `App::global_mut` | `fn` | `globalMut` | `app.swift:1099` |
| 1740 | `App::default_global` | `fn` | `defaultGlobal` | `app.swift:1103` |
| 1751 | `App::set_global` | `fn` | `setGlobal` | `app.swift:1076` |
| 1759 | `App::clear_globals` | `fn` | `clearGlobals` | `app.swift:1110` |
| 1764 | `App::remove_global` | `fn` | `removeGlobal` | `app.swift:1114` |
| 1776 | `App::observe_global` | `fn` | `observeGlobal` | `app.swift:1147` |
| 1793 | `App::lease_global` | `fn` | `leaseGlobal` | `app.swift:1118` |
| 1803 | `App::end_global_lease` | `fn` | `endGlobalLease` | `app.swift:1125` |
| 1810 | `App::new_entity_observer` | `fn` | `newEntityObserver` | `app.swift:1027` |
| 1822 | `App::observe_new` | `fn` | `observeNew` | `app.swift:1036` |
| 1843 | `App::observe_release` | `fn` | `observeRelease` | `app.swift:1047` |
| 1864 | `App::observe_release_in` | `fn` | `observeReleaseIn` | `app.swift:1061` |
| 1882 | `App::observe_keystrokes` | `fn` | `observeKeystrokes` | `app.swift:1246` |
| 1908 | `App::intercept_keystrokes` | `fn` | `interceptKeystrokes` | `app.swift:1255` |
| 1931 | `App::bind_keys` | `fn` | `bindKeys` | `app.swift:1271` |
| 1937 | `App::clear_key_bindings` | `fn` | `clearKeyBindings` | `app.swift:1276` |
| 1943 | `App::key_bindings` | `fn` | `keyBindings` | `app.swift:1281` |
| 1950 | `App::on_action` | `fn` | `onAction` | `app.swift:1285` |
| 1970 | `App::stop_propagation` | `fn` | `stopPropagation` | `app.swift:1296` |
| 1978 | `App::propagate` | `fn` | `propagate` | `app.swift:1300` |
| 1983 | `App::build_action` | `fn` | `buildAction` | `app.swift:1304` |
| 1993 | `App::all_action_names` | `fn` | `allActionNames` | `app.swift:1308` |
| 2000 | `App::all_bindings_for_input` | `fn` | `allBindingsForInput` | `app.swift:1312` |
| 2007 | `App::bindings_for_input_in_context` | `fn` | `bindingsForInputInContext` | `app.swift:1316` |
| 2016 | `App::action_schemas` | `fn` | `actionSchemas` | `app.swift:1321` |
| 2027 | `App::action_schema_by_name` | `fn` | `actionSchemaByName` | `app.swift:1325` |
| 2036 | `App::deprecated_actions_to_preferred_actions` | `fn` | `deprecatedActionsToPreferredActions` | `app.swift:1332` |
| 2041 | `App::action_deprecation_messages` | `fn` | `actionDeprecationMessages` | `app.swift:1336` |
| 2046 | `App::action_documentation` | `fn` | `actionDocumentation` | `app.swift:1340` |
| 2052 | `App::on_app_quit` | `fn` | `onAppQuit` | `app.swift:1383` |
| 2073 | `App::on_app_restart` | `fn` | `onAppRestart` | `app.swift:1389` |
| 2087 | `App::on_window_closed` | `fn` | `onWindowClosed` | `app.swift:1398` |
| 2096 | `App::clear_pending_keystrokes` | `fn` | `clearPendingKeystrokes` | `app.swift:1264` |
| 2111 | `App::is_action_available` | `fn` | `isActionAvailable` | `app.swift:1344` |
| 2127 | `App::set_menus` | `fn` | `setMenus` | `app.swift:1602` |
| 2133 | `App::get_menus` | `fn` | `getMenus` | `app.swift:1606` |
| 2138 | `App::set_dock_menu` | `fn` | `setDockMenu` | `app.swift:1610` |
| 2143 | `App::perform_dock_menu_action` | `fn` | `performDockMenuAction` | `app.swift:1614` |
| 2151 | `App::add_recent_document` | `fn` | `addRecentDocument` | `app.swift:1618` |
| 2157 | `App::update_jump_list` | `fn` | `updateJumpList` | `app.swift:1622` |
| 2167 | `App::dispatch_action` | `fn` | `dispatchAction` | `app.swift:1355` |
| 2227 | `App::has_active_drag` | `fn` | `hasActiveDrag` | `app.swift:1626` |
| 2232 | `App::active_drag_cursor_style` | `fn` | `activeDragCursorStyle` | `app.swift:1630` |
| 2237 | `App::stop_active_drag` | `fn` | `stopActiveDrag` | `app.swift:1634` |
| 2248 | `App::set_active_drag_cursor_style` | `fn` | `setActiveDragCursorStyle` | `app.swift:1643` |
| 2264 | `App::set_prompt_builder` | `fn` | `setPromptBuilder` | `app.swift:1652` |
| 2281 | `App::reset_prompt_builder` | `fn` | `resetPromptBuilder` | `app.swift:1656` |
| 2286 | `App::remove_asset` | `fn` | `removeAsset` | `app.swift:1669` |
| 2295 | `App::fetch_asset` | `fn` | `fetchAsset` | `app.swift:1676` |
| 2317 | `App::focus_handle` | `fn` | `focusHandle` | `app.swift:1690` |
| 2322 | `App::notify` | `fn` | `notify` | `app.swift:906` |
| 2346 | `App::get_name` | `fn` | `getName` | `app.swift:1694` |
| 2351 | `App::can_select_mixed_files_and_dirs` | `fn` | `canSelectMixedFilesAndDirs` | `app.swift:1698` |
| 2359 | `App::drop_image` | `fn` | `dropImage` | `app.swift:1702` |
| 2373 | `App::set_inspector_renderer` | `fn` | `setInspectorRenderer` | `app.swift:1719` |
| 2379 | `App::register_inspector_element` | `fn` | `registerInspectorElement` | `app.swift:1723` |
| 2389 | `App::init_colors` | `fn` | `initColors` | `app.swift:1727` |
| 2511 | `Effect` | `enum` | `Effect` | `app.swift:733` |
| 2550 | `GlobalLease` | `struct` | `GlobalLease` | `app.swift:281` |
| 2580 | `AnyDrag` | `struct` | `AnyDrag` | `app.swift:1796` |
| 2598 | `AnyTooltip` | `struct` | `AnyTooltip` | `app.swift:1826` |
| 2613 | `KeystrokeEvent` | `struct` | `KeystrokeEvent` | `app.swift:1849` |
| 2650 | `GpuiBorrow` | `struct` | `GpuiBorrow` | `app.swift:653` |

</details>
