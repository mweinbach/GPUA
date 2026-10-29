# API Parity Audit: `line.rs`

- **Generated At**: 2026-10-29T04:27:35Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/text_system/line.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/text_system/line.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **10** | 100.0% |
| Genuine Swift Implementations | 10 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 10 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (10 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 12 | `DecorationRun` | `struct` | `DecorationRun` | `line.swift:8` |
| 31 | `ShapedLine` | `struct` | `ShapedLine` | `line.swift:37` |
| 43 | `ShapedLine::len` | `fn` | `len` | `line.swift:54` |
| 49 | `ShapedLine::with_len` | `fn` | `withLen` | `line.swift:59` |
| 63 | `ShapedLine::paint` | `fn` | `paint` | `line.swift:77` |
| 88 | `ShapedLine::paint_background` | `fn` | `paintBackground` | `line.swift:100` |
| 115 | `WrappedLine` | `struct` | `WrappedLine` | `line.swift:124` |
| 127 | `WrappedLine::len` | `fn` | `len` | `line.swift:141` |
| 132 | `WrappedLine::paint` | `fn` | `paint` | `line.swift:147` |
| 162 | `WrappedLine::paint_background` | `fn` | `paintBackground` | `line.swift:171` |

</details>
