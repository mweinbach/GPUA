# API Parity Audit: `window.rs`

- **Generated At**: 2026-10-29T04:27:44Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/platform/test/window.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/platform/test/test_window.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **9** | 100.0% |
| Genuine Swift Implementations | 9 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 9 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (9 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 16 | `TestWindowState` | `struct` | `TestWindowState` | `test_window.swift:72` |
| 36 | `TestWindow` | `struct` | `TestWindow` | `test_window.swift:120` |
| 95 | `TestWindow::new` | `fn` | `new` | `test_window.swift:138` |
| 121 | `TestWindow::simulate_resize` | `fn` | `simulateResize` | `test_window.swift:160` |
| 133 | `TestWindow::simulate_active_status_change` | `fn` | `simulateActiveStatusChange` | `test_window.swift:170` |
| 143 | `TestWindow::simulate_input` | `fn` | `simulateInput` | `test_window.swift:179` |
| 353 | `TestAtlasState` | `struct` | `TestAtlasState` | `test_window.swift:8` |
| 358 | `TestAtlas` | `struct` | `TestAtlas` | `test_window.swift:19` |
| 361 | `TestAtlas::new` | `fn` | `new` | `test_window.swift:27` |

</details>
