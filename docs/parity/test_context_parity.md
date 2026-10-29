# API Parity Audit: `test_context.rs`

- **Generated At**: 2026-10-29T04:27:49Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/app/test_context.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app/test_context.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **72** | 100.0% |
| Genuine Swift Implementations | 72 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 72 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (72 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 20 | `TestAppContext` | `struct` | `TestAppContext` | `test_context.swift:15` |
| 117 | `TestAppContext::build` | `fn` | `build` | `test_context.swift:43` |
| 142 | `TestAppContext::skip_drawing` | `fn` | `skipDrawing` | `test_context.swift:66` |
| 147 | `TestAppContext::single` | `fn` | `single` | `test_context.swift:70` |
| 153 | `TestAppContext::test_function_name` | `fn` | `testFunctionName` | `test_context.swift:75` |
| 158 | `TestAppContext::did_prompt_for_new_path` | `fn` | `didPromptForNewPath` | `test_context.swift:79` |
| 163 | `TestAppContext::new_app` | `fn` | `newApp` | `test_context.swift:83` |
| 169 | `TestAppContext::quit` | `fn` | `quit` | `test_context.swift:87` |
| 175 | `TestAppContext::on_quit` | `fn` | `onQuit` | `test_context.swift:96` |
| 180 | `TestAppContext::refresh` | `fn` | `refresh` | `test_context.swift:100` |
| 187 | `TestAppContext::executor` | `fn` | `executor` | `test_context.swift:104` |
| 192 | `TestAppContext::foreground_executor` | `fn` | `foregroundExecutor` | `test_context.swift:18` |
| 203 | `TestAppContext::update` | `fn` | `update` | `test_context.swift:109` |
| 209 | `TestAppContext::read` | `fn` | `read` | `test_context.swift:113` |
| 216 | `TestAppContext::add_window` | `fn` | `addWindow` | `test_context.swift:117` |
| 239 | `TestAppContext::open_window` | `fn` | `openWindow` | `test_context.swift:124` |
| 263 | `TestAppContext::add_empty_window` | `fn` | `addEmptyWindow` | `test_context.swift:134` |
| 284 | `TestAppContext::add_window_view` | `fn` | `addWindowView` | `test_context.swift:141` |
| 313 | `TestAppContext::text_system` | `fn` | `textSystem` | `test_context.swift:21` |
| 318 | `TestAppContext::write_to_clipboard` | `fn` | `writeToClipboard` | `test_context.swift:146` |
| 324 | `TestAppContext::read_from_clipboard` | `fn` | `readFromClipboard` | `test_context.swift:150` |
| 329 | `TestAppContext::simulate_new_path_selection` | `fn` | `simulateNewPathSelection` | `test_context.swift:154` |
| 338 | `TestAppContext::simulate_prompt_answer` | `fn` | `simulatePromptAnswer` | `test_context.swift:158` |
| 343 | `TestAppContext::has_pending_prompt` | `fn` | `hasPendingPrompt` | `test_context.swift:162` |
| 348 | `TestAppContext::pending_prompt` | `fn` | `pendingPrompt` | `test_context.swift:166` |
| 353 | `TestAppContext::opened_url` | `fn` | `openedUrl` | `test_context.swift:170` |
| 358 | `TestAppContext::simulate_window_resize` | `fn` | `simulateWindowResize` | `test_context.swift:174` |
| 363 | `TestAppContext::expect_restart` | `fn` | `expectRestart` | `test_context.swift:180` |
| 371 | `TestAppContext::set_screen_capture_sources` | `fn` | `setScreenCaptureSources` | `test_context.swift:184` |
| 376 | `TestAppContext::windows` | `fn` | `windows` | `test_context.swift:188` |
| 382 | `TestAppContext::spawn` | `fn` | `spawn` | `test_context.swift:250` |
| 391 | `TestAppContext::has_global` | `fn` | `hasGlobal` | `test_context.swift:258` |
| 398 | `TestAppContext::read_global` | `fn` | `readGlobal` | `test_context.swift:262` |
| 404 | `TestAppContext::try_read_global` | `fn` | `tryReadGlobal` | `test_context.swift:266` |
| 410 | `TestAppContext::set_global` | `fn` | `setGlobal` | `test_context.swift:271` |
| 416 | `TestAppContext::update_global` | `fn` | `updateGlobal` | `test_context.swift:275` |
| 423 | `TestAppContext::to_async` | `fn` | `toAsync` | `test_context.swift:279` |
| 432 | `TestAppContext::run_until_parked` | `fn` | `runUntilParked` | `test_context.swift:196` |
| 437 | `TestAppContext::dispatch_action` | `fn` | `dispatchAction` | `test_context.swift:227` |
| 454 | `TestAppContext::simulate_keystrokes` | `fn` | `simulateKeystrokes` | `test_context.swift:210` |
| 470 | `TestAppContext::simulate_input` | `fn` | `simulateInput` | `test_context.swift:216` |
| 479 | `TestAppContext::dispatch_keystroke` | `fn` | `dispatchKeystroke` | `test_context.swift:233` |
| 487 | `TestAppContext::test_window` | `fn` | `testWindow` | `test_context.swift:192` |
| 502 | `TestAppContext::notifications` | `fn` | `notifications` | `test_context.swift:287` |
| 522 | `TestAppContext::events` | `fn` | `events` | `test_context.swift:299` |
| 542 | `TestAppContext::condition` | `fn` | `condition` | `test_context.swift:311` |
| 574 | `TestAppContext::set_name` | `fn` | `setName` | `test_context.swift:333` |
| 581 | `Entity::next_event` | `fn` | `nextEvent` | `test_context.swift:342` |
| 606 | `Entity::next_notification` | `fn` | `nextNotification` | `test_context.swift:350` |
| 631 | `Entity::condition` | `fn` | `condition` | `test_context.swift:360` |
| 694 | `VisualTestContext` | `struct` | `VisualTestContext` | `test_context.swift:373` |
| 704 | `VisualTestContext::update` | `fn` | `update` | `test_context.swift:387` |
| 713 | `VisualTestContext::from_window` | `fn` | `fromWindow` | `test_context.swift:382` |
| 721 | `VisualTestContext::run_until_parked` | `fn` | `runUntilParked` | `test_context.swift:393` |
| 726 | `VisualTestContext::dispatch_action` | `fn` | `dispatchAction` | `test_context.swift:397` |
| 734 | `VisualTestContext::window_title` | `fn` | `windowTitle` | `test_context.swift:401` |
| 740 | `VisualTestContext::simulate_keystrokes` | `fn` | `simulateKeystrokes` | `test_context.swift:405` |
| 746 | `VisualTestContext::simulate_input` | `fn` | `simulateInput` | `test_context.swift:409` |
| 751 | `VisualTestContext::simulate_mouse_move` | `fn` | `simulateMouseMove` | `test_context.swift:413` |
| 765 | `VisualTestContext::simulate_mouse_down` | `fn` | `simulateMouseDown` | `test_context.swift:417` |
| 781 | `VisualTestContext::simulate_mouse_up` | `fn` | `simulateMouseUp` | `test_context.swift:421` |
| 796 | `VisualTestContext::simulate_click` | `fn` | `simulateClick` | `test_context.swift:425` |
| 813 | `VisualTestContext::simulate_modifiers_change` | `fn` | `simulateModifiersChange` | `test_context.swift:434` |
| 821 | `VisualTestContext::simulate_capslock_change` | `fn` | `simulateCapslockChange` | `test_context.swift:438` |
| 829 | `VisualTestContext::simulate_resize` | `fn` | `simulateResize` | `test_context.swift:442` |
| 834 | `VisualTestContext::debug_bounds` | `fn` | `debugBounds` | `test_context.swift:446` |
| 839 | `VisualTestContext::draw` | `fn` | `draw` | `test_context.swift:450` |
| 865 | `VisualTestContext::simulate_event` | `fn` | `simulateEvent` | `test_context.swift:222` |
| 872 | `VisualTestContext::deactivate_window` | `fn` | `deactivateWindow` | `test_context.swift:459` |
| 881 | `VisualTestContext::simulate_close` | `fn` | `simulateClose` | `test_context.swift:466` |
| 910 | `VisualTestContext::into_mut` | `fn` | `intoMut` | `test_context.swift:473` |
| 1056 | `AnyWindowHandle::build_entity` | `fn` | `buildEntity` | `test_context.swift:482` |

</details>
