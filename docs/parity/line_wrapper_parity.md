# API Parity Audit: `line_wrapper.rs`

- **Generated At**: 2026-10-29T04:27:29Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/text_system/line_wrapper.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/text_system/line_wrapper.swift`
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
| 7 | `TruncateFrom` | `enum` | `TruncateFrom` | `line_wrapper.swift:8` |
| 15 | `LineWrapper` | `struct` | `LineWrapper` | `line_wrapper.swift:73` |
| 25 | `LineWrapper::MAX_INDENT` | `const` | `maxIndent` | `line_wrapper.swift:74` |
| 27 | `LineWrapper::new` | `fn` | `new` | `line_wrapper.swift:90` |
| 38 | `LineWrapper::wrap_line` | `fn` | `wrapLine` | `line_wrapper.swift:113` |
| 139 | `LineWrapper::should_truncate_line` | `fn` | `shouldTruncateLine` | `line_wrapper.swift:205` |
| 188 | `LineWrapper::truncate_line` | `fn` | `truncateLine` | `line_wrapper.swift:258` |
| 218 | `LineWrapper::is_word_char` | `fn` | `isWordChar` | `line_wrapper.swift:308` |
| 308 | `LineFragment` | `enum` | `LineFragment` | `line_wrapper.swift:31` |
| 325 | `LineFragment::text` | `fn` | `text` | `line_wrapper.swift:33` |
| 330 | `LineFragment::element` | `fn` | `element` | `line_wrapper.swift:35` |
| 358 | `WrapBoundaryCandidate::len_utf8` | `fn` | `lenUtf8` | `line_wrapper.swift:20` |
| 368 | `Boundary` | `struct` | `Boundary` | `line_wrapper.swift:56` |

</details>
