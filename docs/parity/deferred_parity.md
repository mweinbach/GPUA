# API Parity Audit: `deferred.rs`

- **Generated At**: 2026-10-29T06:55:53Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/deferred.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/deferred.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **6** | 100.0% |
| Genuine Swift Implementations | 6 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 6 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (6 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 7 | `deferred` | `fn` | `deferred` | `deferred.swift:113` |
| 17 | `DeferredTarget` | `enum` | `DeferredTarget` | `deferred.swift:10` |
| 26 | `Deferred` | `struct` | `Deferred` | `deferred.swift:19` |
| 36 | `Deferred::with_priority` | `fn` | `withPriority` | `deferred.swift:36` |
| 47 | `Deferred::window_overlay` | `fn` | `windowOverlay` | `deferred.swift:43` |
| 114 | `Deferred::priority` | `fn` | `priority` | `deferred.swift:24` |

</details>
