// Ported from: crates/rune/src/runtime/paint/cache_layer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Offscreen raster layer cache (`El.cache`) tracking subtree signatures, raster scales, and resident eviction.

import RuneMotion

struct CachedLayerEntry: Sendable {
    var signature: UInt64
    var rasterScale: Float
    var seenScale: Float
    var scaleChangedAt: Double
    var envScale: Float
    var wasLive: Bool
    var relBounds: [Float]
    var glyphs: Int
    var commitGen: UInt64
    var paintStateHash: UInt64
}

struct LayerCacheStore: Sendable {
    var entries: [RuneMotion.NodeId: CachedLayerEntry] = [:]

    mutating func prune(keeping: Set<RuneMotion.NodeId>) {
        entries = entries.filter { keeping.contains($0.key) }
    }

    mutating func evict(_ id: RuneMotion.NodeId) {
        entries.removeValue(forKey: id)
    }

    mutating func clear() {
        entries.removeAll()
    }

    func get(_ id: RuneMotion.NodeId) -> CachedLayerEntry? {
        entries[id]
    }

    mutating func insert(_ id: RuneMotion.NodeId, _ entry: CachedLayerEntry) {
        entries[id] = entry
    }
}

func sealCacheLayerMarker(
    _ instances: inout [Instance],
    start: Int,
    rect: [Float],
    id: RuneMotion.NodeId,
    signature: UInt64
) {
    guard instances.indices.contains(start) else { return }
    instances[start].rect = rect
    instances[start].params[3] = 1.0
    instances[start].radii = packU64F32(id.rawValue)
    instances[start].uv = packU64F32(signature == 0 ? 1 : signature)
    instances.append(Instance.endLayer())
}
