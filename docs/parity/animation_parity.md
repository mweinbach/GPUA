# API Parity Audit: `animation.rs`

- **Generated At**: 2026-10-29T06:55:12Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/animation.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/animation.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **13** | 100.0% |
| Genuine Swift Implementations | 13 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 13 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (13 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 15 | `Animation` | `struct` | `Animation` | `animation.swift:66` |
| 28 | `Animation::new` | `fn` | `new` | `animation.swift:83` |
| 37 | `Animation::repeat` | `fn` | `repeat` | `animation.swift:88` |
| 45 | `Animation::with_easing` | `fn` | `withEasing` | `animation.swift:95` |
| 52 | `AnimationExt` | `trait` | `AnimationExt` | `animation.swift:105` |
| 93 | `AnimationElement` | `struct` | `AnimationElement` | `animation.swift:158` |
| 103 | `AnimationElement::map_element` | `fn` | `mapElement` | `animation.swift:189` |
| 213 | `linear` | `fn` | `linear` | `animation.swift:10` |
| 218 | `quadratic` | `fn` | `quadratic` | `animation.swift:15` |
| 223 | `ease_in_out` | `fn` | `easeInOut` | `animation.swift:20` |
| 233 | `ease_out_quint` | `fn` | `easeOutQuint` | `animation.swift:30` |
| 238 | `bounce` | `fn` | `bounce` | `animation.swift:39` |
| 249 | `pulsating_between` | `fn` | `pulsatingBetween` | `animation.swift:50` |

</details>
