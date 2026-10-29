# API Parity Audit: `visual_test_context.rs`

- **Generated At**: 2026-10-29T11:17:09Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/app/visual_test_context.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/app/visual_test_context.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **33** | 100.0% |
| Genuine Swift Implementations | 33 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 33 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (33 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 21 | `VisualTestAppContext` | `struct` | `VisualTestAppContext` | `visual_test_context.swift:176` |
| 45 | `VisualTestAppContext::new` | `fn` | `new` | `visual_test_context.swift:191` |
| 53 | `VisualTestAppContext::with_asset_source` | `fn` | `withAssetSource` | `visual_test_context.swift:195` |
| 97 | `VisualTestAppContext::open_offscreen_window` | `fn` | `openOffscreenWindow` | `visual_test_context.swift:206` |
| 122 | `VisualTestAppContext::open_offscreen_window_default` | `fn` | `openOffscreenWindowDefault` | `visual_test_context.swift:221` |
| 131 | `VisualTestAppContext::is_screen_capture_supported` | `fn` | `isScreenCaptureSupported` | `visual_test_context.swift:250` |
| 136 | `VisualTestAppContext::text_system` | `fn` | `textSystem` | `visual_test_context.swift:254` |
| 141 | `VisualTestAppContext::executor` | `fn` | `executor` | `visual_test_context.swift:258` |
| 146 | `VisualTestAppContext::foreground_executor` | `fn` | `foregroundExecutor` | `visual_test_context.swift:179` |
| 152 | `VisualTestAppContext::run_until_parked` | `fn` | `runUntilParked` | `visual_test_context.swift:262` |
| 159 | `VisualTestAppContext::advance_clock` | `fn` | `advanceClock` | `visual_test_context.swift:266` |
| 164 | `VisualTestAppContext::update` | `fn` | `update` | `visual_test_context.swift:351` |
| 170 | `VisualTestAppContext::read` | `fn` | `read` | `visual_test_context.swift:270` |
| 176 | `VisualTestAppContext::update_window` | `fn` | `updateWindow` | `visual_test_context.swift:388` |
| 185 | `VisualTestAppContext::spawn` | `fn` | `spawn` | `visual_test_context.swift:274` |
| 194 | `VisualTestAppContext::has_global` | `fn` | `hasGlobal` | `visual_test_context.swift:278` |
| 200 | `VisualTestAppContext::read_global` | `fn` | `readGlobal` | `visual_test_context.swift:384` |
| 206 | `VisualTestAppContext::set_global` | `fn` | `setGlobal` | `visual_test_context.swift:401` |
| 212 | `VisualTestAppContext::update_global` | `fn` | `updateGlobal` | `visual_test_context.swift:282` |
| 225 | `VisualTestAppContext::simulate_keystrokes` | `fn` | `simulateKeystrokes` | `visual_test_context.swift:49` |
| 235 | `VisualTestAppContext::dispatch_keystroke` | `fn` | `dispatchKeystroke` | `visual_test_context.swift:290` |
| 243 | `VisualTestAppContext::simulate_input` | `fn` | `simulateInput` | `visual_test_context.swift:53` |
| 258 | `VisualTestAppContext::simulate_mouse_move` | `fn` | `simulateMouseMove` | `visual_test_context.swift:57` |
| 276 | `VisualTestAppContext::simulate_mouse_down` | `fn` | `simulateMouseDown` | `visual_test_context.swift:61` |
| 296 | `VisualTestAppContext::simulate_mouse_up` | `fn` | `simulateMouseUp` | `visual_test_context.swift:65` |
| 315 | `VisualTestAppContext::simulate_click` | `fn` | `simulateClick` | `visual_test_context.swift:69` |
| 326 | `VisualTestAppContext::simulate_event` | `fn` | `simulateEvent` | `visual_test_context.swift:137` |
| 335 | `VisualTestAppContext::dispatch_action` | `fn` | `dispatchAction` | `visual_test_context.swift:37` |
| 344 | `VisualTestAppContext::write_to_clipboard` | `fn` | `writeToClipboard` | `visual_test_context.swift:298` |
| 349 | `VisualTestAppContext::read_from_clipboard` | `fn` | `readFromClipboard` | `visual_test_context.swift:302` |
| 354 | `VisualTestAppContext::wait_for` | `fn` | `waitFor` | `visual_test_context.swift:306` |
| 385 | `VisualTestAppContext::capture_screenshot` | `fn` | `captureScreenshot` | `visual_test_context.swift:337` |
| 390 | `VisualTestAppContext::wait_for_animations` | `fn` | `waitForAnimations` | `visual_test_context.swift:343` |

</details>
