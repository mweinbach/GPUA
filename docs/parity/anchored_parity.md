# API Parity Audit: `anchored.rs`

- **Generated At**: 2026-10-29T06:54:20Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/anchored.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/anchored.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **11** | 100.0% |
| Genuine Swift Implementations | 11 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 11 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (11 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 10 | `AnchoredState` | `struct` | `AnchoredState` | `anchored.swift:10` |
| 16 | `Anchored` | `struct` | `Anchored` | `anchored.swift:59` |
| 27 | `anchored` | `fn` | `anchored` | `anchored.swift:278` |
| 40 | `Anchored::anchor` | `fn` | `anchor` | `anchored.swift:80` |
| 47 | `Anchored::position` | `fn` | `position` | `anchored.swift:88` |
| 54 | `Anchored::offset` | `fn` | `offset` | `anchored.swift:68` |
| 62 | `Anchored::position_mode` | `fn` | `positionMode` | `anchored.swift:67` |
| 68 | `Anchored::snap_to_window` | `fn` | `snapToWindow` | `anchored.swift:112` |
| 74 | `Anchored::snap_to_window_with_margin` | `fn` | `snapToWindowWithMargin` | `anchored.swift:119` |
| 245 | `AnchoredFitMode` | `enum` | `AnchoredFitMode` | `anchored.swift:19` |
| 256 | `AnchoredPositionMode` | `enum` | `AnchoredPositionMode` | `anchored.swift:29` |

</details>
