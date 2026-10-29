# API Parity Audit: `font_features.rs`

- **Generated At**: 2026-10-29T04:27:40Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/text_system/font_features.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/text_system/font_features.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **4** | 100.0% |
| Genuine Swift Implementations | 4 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 4 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (4 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 8 | `FontFeatures` | `struct` | `FontFeatures` | `font_features.swift:9` |
| 12 | `FontFeatures::disable_ligatures` | `fn` | `disableLigatures` | `font_features.swift:30` |
| 18 | `FontFeatures::tag_value_list` | `fn` | `tagValueList` | `font_features.swift:34` |
| 25 | `FontFeatures::is_calt_enabled` | `fn` | `isCaltEnabled` | `font_features.swift:38` |

</details>
