# API Parity Audit: `platform.rs`

- **Generated At**: 2026-10-29T04:27:44Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/platform/test/platform.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/platform/test/test_platform.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **16** | 100.0% |
| Genuine Swift Implementations | 16 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 16 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (16 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 25 | `TestPlatform` | `struct` | `TestPlatform` | `test_platform.swift:54` |
| 49 | `TestScreenCaptureSource` | `struct` | `TestScreenCaptureSource` | `test_platform.swift:9` |
| 52 | `TestScreenCaptureStream` | `struct` | `TestScreenCaptureStream` | `test_platform.swift:21` |
| 91 | `TestPrompts` | `struct` | `TestPrompts` | `test_platform.swift:46` |
| 97 | `TestPlatform::new` | `fn` | `new` | `test_platform.swift:81` |
| 101 | `TestPlatform::with_text_system` | `fn` | `withTextSystem` | `test_platform.swift:92` |
| 109 | `TestPlatform::with_platform` | `fn` | `withPlatform` | `test_platform.swift:105` |
| 147 | `TestPlatform::simulate_new_path_selection` | `fn` | `simulateNewPathSelection` | `test_platform.swift:118` |
| 161 | `TestPlatform::simulate_prompt_answer` | `fn` | `simulatePromptAnswer` | `test_platform.swift:131` |
| 177 | `TestPlatform::has_pending_prompt` | `fn` | `hasPendingPrompt` | `test_platform.swift:148` |
| 181 | `TestPlatform::pending_prompt` | `fn` | `pendingPrompt` | `test_platform.swift:154` |
| 190 | `TestPlatform::set_screen_capture_sources` | `fn` | `setScreenCaptureSources` | `test_platform.swift:161` |
| 194 | `TestPlatform::prompt` | `fn` | `prompt` | `test_platform.swift:178` |
| 214 | `TestPlatform::set_active_window` | `fn` | `setActiveWindow` | `test_platform.swift:191` |
| 236 | `TestPlatform::did_prompt_for_new_path` | `fn` | `didPromptForNewPath` | `test_platform.swift:205` |
| 471 | `TestScreenCaptureSource::new` | `fn` | `new` | `test_platform.swift:15` |

</details>
