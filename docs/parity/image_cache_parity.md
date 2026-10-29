# API Parity Audit: `image_cache.rs`

- **Generated At**: 2026-10-29T06:59:25Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/gpui/src/elements/image_cache.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/GPUI/elements/image_cache.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **19** | 100.0% |
| Genuine Swift Implementations | 19 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 19 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (19 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 15 | `image_cache` | `fn` | `imageCache` | `image_cache.swift:232` |
| 25 | `AnyImageCache` | `struct` | `AnyImageCache` | `image_cache.swift:42` |
| 47 | `AnyImageCache::load` | `fn` | `load` | `image_cache.swift:57` |
| 60 | `load` | `fn` | `load` | `image_cache.swift:34` |
| 72 | `ImageCacheElement` | `struct` | `ImageCacheElement` | `image_cache.swift:155` |
| 165 | `ImageLoadingTask` | `type` | `ImageLoadingTask` | `image_cache.swift:10` |
| 168 | `ImageCacheItem` | `enum` | `ImageCacheItem` | `image_cache.swift:13` |
| 189 | `ImageCacheItem::get` | `fn` | `get` | `image_cache.swift:20` |
| 203 | `ImageCache` | `trait` | `ImageCache` | `image_cache.swift:31` |
| 216 | `ImageCacheProvider` | `trait` | `ImageCacheProvider` | `image_cache.swift:77` |
| 228 | `RetainAllImageCache` | `struct` | `RetainAllImageCache` | `image_cache.swift:83` |
| 241 | `RetainAllImageCache::new` | `fn` | `new` | `image_cache.swift:89` |
| 257 | `RetainAllImageCache::load` | `fn` | `load` | `image_cache.swift:94` |
| 289 | `RetainAllImageCache::clear` | `fn` | `clear` | `image_cache.swift:114` |
| 298 | `RetainAllImageCache::remove` | `fn` | `remove` | `image_cache.swift:119` |
| 308 | `RetainAllImageCache::len` | `fn` | `len` | `image_cache.swift:125` |
| 313 | `RetainAllImageCache::is_empty` | `fn` | `isEmpty` | `image_cache.swift:130` |
| 330 | `retain_all` | `fn` | `retainAll` | `image_cache.swift:150` |
| 335 | `RetainAllImageCacheProvider` | `struct` | `RetainAllImageCacheProvider` | `image_cache.swift:136` |

</details>
