// Ported from: crates/rune-mermaid/src/scenes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Built scenes, kept by source, style and hover, so a diagram rebuilt with nothing new costs a
//! lookup, and a diagram streaming in builds each line held to the one before (see `steady`).

#if !os(WASI)
import Foundation
#endif

import Rune

private let CACHE_LEN: Int = 16
/// How many lines back a growing build looks for one it can hold to before it starts afresh.
private let MAX_HELD_LINES: Int = 64

struct SceneCacheKey: Hashable {
    var src: String
    var style: DiagramStyle
    var hoverKind: Hover?
    var hoverColor: Color?
    var growing: Bool
    var epoch: UInt64
}

typealias BuiltScene = (Scene?, SteadyMemory?)

final class SceneCache {
    var map: [SceneCacheKey: BuiltScene] = [:]
    var order: [SceneCacheKey] = []
    var hoverLives: [String: Live<Float>] = [:]

    func clear() {
        map.removeAll()
        order.removeAll()
        for live in hoverLives.values {
            live.set(0.0)
        }
        hoverLives.removeAll()
    }
}

private final class SceneCacheBox {
    var cache = SceneCache()
}

#if !os(WASI)
private let scenesThreadKey = "dev.gpua.rune.mermaid.scenes"

private func currentSceneCacheBox() -> SceneCacheBox {
    let dict = Thread.current.threadDictionary
    if let existing = dict[scenesThreadKey] as? SceneCacheBox {
        return existing
    }
    let created = SceneCacheBox()
    dict[scenesThreadKey] = created
    return created
}
#else
// PORT NOTE: WASI is single-threaded; thread-local scene cache lives in a process-local box.
nonisolated(unsafe) private let wasiSceneCacheBox = SceneCacheBox()

private func currentSceneCacheBox() -> SceneCacheBox {
    wasiSceneCacheBox
}
#endif

enum scenes {
    static func resetCache() {
        currentSceneCacheBox().cache.clear()
    }

    static func hoverLive(_ key: String) -> Live<Float> {
        let box = currentSceneCacheBox()
        if let existing = box.cache.hoverLives[key] {
            return existing
        }
        let created = Live<Float>(0.0)
        box.cache.hoverLives[key] = created
        return created
    }

    private static func makeKey(
        _ src: String,
        _ style: DiagramStyle,
        _ hover: (Hover, Color)?,
        _ growing: Bool
    ) -> SceneCacheKey {
        SceneCacheKey(
            src: src,
            style: style,
            hoverKind: hover?.0,
            hoverColor: hover?.1,
            growing: growing,
            epoch: Rune.fontEpoch()
        )
    }

    /// `src`'s scene, from the cache or built and kept; held to `prev` when `holding` is `true`.
    static func built(
        _ src: String,
        _ style: DiagramStyle,
        _ hover: (Hover, Color)?,
        _ prev: SteadyMemory??
    ) -> BuiltScene {
        let key = makeKey(src, style, hover, prev != nil)
        let box = currentSceneCacheBox()
        if let hit = box.cache.map[key] {
            return hit
        }
        let b = build(src, style, hover, prev)
        if box.cache.order.count >= CACHE_LEN {
            let old = box.cache.order.removeFirst()
            box.cache.map.removeValue(forKey: old)
        }
        box.cache.order.append(key)
        box.cache.map[key] = b
        return b
    }

    private static func build(
        _ src: String,
        _ style: DiagramStyle,
        _ hover: (Hover, Color)?,
        _ prev: SteadyMemory??
    ) -> BuiltScene {
        // PORT NOTE: Swift has no `std::panic::catch_unwind`; layout and parsing guard bounds/non-finites directly.
        let safe = { buildScene(src, style, hover) }
        switch prev {
        case .none:
            return (safe(), nil)
        case .some(let prevMem):
            let held = prevMem?.size ?? [0.0, 0.0]
            let (s, memory) = steady.build(prevMem, safe)
            if let s = s {
                // Nor does the card shrink, even as the diagram shrinks to fit a wider layout.
                s.size = [max(s.size[0], held[0]), max(s.size[1], held[1])]
                memory.size = s.size
            } else {
                memory.size = held
            }
            return (s, memory)
        }
    }

    /// `src` laid out held to the same source a line shorter, laid out held to the one a line
    /// shorter again, and so on, so it lays out the same however many lines each build added.
    static func growing(
        _ src: String,
        _ style: DiagramStyle,
        _ hover: (Hover, Color)?
    ) -> Scene? {
        var chain: [String] = [String(src.trimmedEnd())]
        var prev: SteadyMemory? = nil
        let box = currentSceneCacheBox()
        if let hit = box.cache.map[makeKey(chain[0], style, hover, true)] {
            return hit.0
        }
        while let cur = chain.last, let nl = cur.lastIndex(of: "\n") {
            let shorter = String(cur[..<nl].trimmedEnd())
            if let hit = box.cache.map[makeKey(shorter, style, hover, true)] {
                prev = hit.1
                break
            }
            if chain.count >= MAX_HELD_LINES {
                break
            }
            chain.append(shorter)
        }
        // Only the source asked for is kept: the shorter ones were built for it alone.
        let last = chain.removeFirst()
        for s in chain.reversed() {
            prev = build(s, style, hover, .some(prev)).1
        }
        return built(last, style, hover, .some(prev)).0
    }
}
