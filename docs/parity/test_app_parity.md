# API Parity Audit: `test_app.rs`

- **Generated At**: 2026-10-29T04:27:49Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/app/test_app.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app/test_app.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **49** | 100.0% |
| Genuine Swift Implementations | 49 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 49 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (49 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 40 | `TestApp` | `struct` | `TestApp` | `test_app.swift:10` |
| 52 | `TestApp::new` | `fn` | `new` | `test_app.swift:46` |
| 57 | `TestApp::with_seed` | `fn` | `withSeed` | `test_app.swift:50` |
| 62 | `TestApp::with_text_system` | `fn` | `withTextSystem` | `test_app.swift:54` |
| 67 | `TestApp::with_text_system_and_assets` | `fn` | `withTextSystemAndAssets` | `test_app.swift:58` |
| 111 | `TestApp::update` | `fn` | `update` | `test_app.swift:94` |
| 121 | `TestApp::read` | `fn` | `read` | `test_app.swift:100` |
| 127 | `TestApp::new_entity` | `fn` | `newEntity` | `test_app.swift:104` |
| 135 | `TestApp::update_entity` | `fn` | `updateEntity` | `test_app.swift:111` |
| 144 | `TestApp::read_entity` | `fn` | `readEntity` | `test_app.swift:117` |
| 153 | `TestApp::open_window` | `fn` | `openWindow` | `test_app.swift:121` |
| 178 | `TestApp::open_window_with_options` | `fn` | `openWindowWithOptions` | `test_app.swift:125` |
| 197 | `TestApp::run_until_parked` | `fn` | `runUntilParked` | `test_app.swift:141` |
| 202 | `TestApp::advance_clock` | `fn` | `advanceClock` | `test_app.swift:145` |
| 207 | `TestApp::spawn` | `fn` | `spawn` | `test_app.swift:150` |
| 216 | `TestApp::background_spawn` | `fn` | `backgroundSpawn` | `test_app.swift:154` |
| 224 | `TestApp::to_async` | `fn` | `toAsync` | `test_app.swift:158` |
| 233 | `TestApp::background_executor` | `fn` | `backgroundExecutor` | `test_app.swift:13` |
| 238 | `TestApp::foreground_executor` | `fn` | `foregroundExecutor` | `test_app.swift:14` |
| 243 | `TestApp::text_system` | `fn` | `textSystem` | `test_app.swift:16` |
| 248 | `TestApp::has_global` | `fn` | `hasGlobal` | `test_app.swift:166` |
| 253 | `TestApp::set_global` | `fn` | `setGlobal` | `test_app.swift:170` |
| 258 | `TestApp::read_global` | `fn` | `readGlobal` | `test_app.swift:175` |
| 263 | `TestApp::update_global` | `fn` | `updateGlobal` | `test_app.swift:180` |
| 270 | `TestApp::write_to_clipboard` | `fn` | `writeToClipboard` | `test_app.swift:186` |
| 275 | `TestApp::read_from_clipboard` | `fn` | `readFromClipboard` | `test_app.swift:190` |
| 280 | `TestApp::opened_url` | `fn` | `openedUrl` | `test_app.swift:194` |
| 285 | `TestApp::did_prompt_for_new_path` | `fn` | `didPromptForNewPath` | `test_app.swift:198` |
| 290 | `TestApp::simulate_new_path_selection` | `fn` | `simulateNewPathSelection` | `test_app.swift:202` |
| 298 | `TestApp::has_pending_prompt` | `fn` | `hasPendingPrompt` | `test_app.swift:207` |
| 303 | `TestApp::simulate_prompt_answer` | `fn` | `simulatePromptAnswer` | `test_app.swift:211` |
| 308 | `TestApp::windows` | `fn` | `windows` | `test_app.swift:216` |
| 320 | `TestAppWindow` | `struct` | `TestAppWindow` | `test_app.swift:225` |
| 329 | `TestAppWindow::handle` | `fn` | `handle` | `test_app.swift:226` |
| 334 | `TestAppWindow::root` | `fn` | `root` | `test_app.swift:243` |
| 344 | `TestAppWindow::update` | `fn` | `update` | `test_app.swift:251` |
| 359 | `TestAppWindow::read` | `fn` | `read` | `test_app.swift:262` |
| 374 | `TestAppWindow::title` | `fn` | `title` | `test_app.swift:267` |
| 384 | `TestAppWindow::simulate_keystroke` | `fn` | `simulateKeystroke` | `test_app.swift:271` |
| 398 | `TestAppWindow::simulate_keystrokes` | `fn` | `simulateKeystrokes` | `test_app.swift:280` |
| 405 | `TestAppWindow::simulate_input` | `fn` | `simulateInput` | `test_app.swift:286` |
| 412 | `TestAppWindow::simulate_mouse_move` | `fn` | `simulateMouseMove` | `test_app.swift:292` |
| 421 | `TestAppWindow::simulate_mouse_down` | `fn` | `simulateMouseDown` | `test_app.swift:299` |
| 432 | `TestAppWindow::simulate_mouse_up` | `fn` | `simulateMouseUp` | `test_app.swift:306` |
| 442 | `TestAppWindow::simulate_click` | `fn` | `simulateClick` | `test_app.swift:313` |
| 448 | `TestAppWindow::simulate_scroll` | `fn` | `simulateScroll` | `test_app.swift:318` |
| 458 | `TestAppWindow::simulate_event` | `fn` | `simulateEvent` | `test_app.swift:325` |
| 472 | `TestAppWindow::simulate_resize` | `fn` | `simulateResize` | `test_app.swift:332` |
| 485 | `TestAppWindow::draw` | `fn` | `draw` | `test_app.swift:339` |

</details>
