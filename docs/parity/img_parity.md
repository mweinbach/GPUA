# API Parity Audit: `img.rs`

- **Generated At**: 2026-10-29T07:01:58Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/img.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/img.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **15** | 100.0% |
| Genuine Swift Implementations | 15 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 15 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (15 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 31 | `LOADING_DELAY` | `const` | `loadingDelay` | `img.swift:10` |
| 37 | `ImgResourceLoader` | `type` | `ImgResourceLoader` | `img.swift:35` |
| 41 | `ImageSource` | `enum` | `ImageSource` | `img.swift:38` |
| 128 | `ImageStyle` | `struct` | `ImageStyle` | `img.swift:92` |
| 147 | `StyledImage` | `trait` | `StyledImage` | `img.swift:112` |
| 191 | `Img` | `struct` | `Img` | `img.swift:159` |
| 200 | `img` | `fn` | `img` | `img.swift:253` |
| 211 | `Img::extensions` | `fn` | `extensions` | `img.swift:178` |
| 229 | `Img::image_cache` | `fn` | `imageCache` | `img.swift:186` |
| 259 | `ImgLayoutState` | `struct` | `ImgLayoutState` | `img.swift:148` |
| 524 | `ImageSource::use_data` | `fn` | `useData` | `img.swift:54` |
| 544 | `ImageSource::get_data` | `fn` | `getData` | `img.swift:72` |
| 565 | `ImageSource::remove_asset` | `fn` | `removeAsset` | `img.swift:81` |
| 594 | `ImageAssetLoader` | `enum` | `ImageAssetLoader` | `img.swift:23` |
| 716 | `ImageCacheError` | `enum` | `ImageCacheError` | `img.swift:13` |

</details>
