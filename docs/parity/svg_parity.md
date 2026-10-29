# API Parity Audit: `svg.rs`

- **Generated At**: 2026-10-29T07:00:34Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/svg.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/svg.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **12** | 100.0% |
| Genuine Swift Implementations | 12 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 12 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (12 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 11 | `Svg` | `struct` | `Svg` | `svg.swift:71` |
| 20 | `svg` | `fn` | `svg` | `svg.swift:170` |
| 31 | `Svg::path` | `fn` | `path` | `svg.swift:77` |
| 37 | `Svg::external_path` | `fn` | `externalPath` | `svg.swift:78` |
| 44 | `Svg::with_transformation` | `fn` | `withTransformation` | `svg.swift:102` |
| 187 | `Transformation` | `struct` | `Transformation` | `svg.swift:10` |
| 205 | `Transformation::scale` | `fn` | `scale` | `svg.swift:11` |
| 214 | `Transformation::translate` | `fn` | `translate` | `svg.swift:12` |
| 223 | `Transformation::rotate` | `fn` | `rotate` | `svg.swift:13` |
| 233 | `Transformation::with_scaling` | `fn` | `withScaling` | `svg.swift:41` |
| 239 | `Transformation::with_translation` | `fn` | `withTranslation` | `svg.swift:48` |
| 245 | `Transformation::with_rotation` | `fn` | `withRotation` | `svg.swift:55` |

</details>
