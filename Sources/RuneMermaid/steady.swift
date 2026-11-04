// Ported from: crates/rune-mermaid/src/steady.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Layouts that only grow while a diagram streams in. A build of a source still arriving holds
//! to the layout of the same source one line shorter: no node moves back a rank or changes
//! places with a node it was laid out beside, nodes only move on along their ranks (right in a
//! top-down diagram, down in a left-right one), never back toward where they were, and no gap
//! between ranks narrows. A new edge that would pull a node a rank further and leave the
//! diagram shorter for one line, only for the next line to stretch it again, leaves it as tall
//! as it was instead. The finished source lays out afresh, as a diagram that never streamed
//! does, and settles there in one glide.

#if !os(WASI)
import Foundation
#endif

/// What one layout leaves for the next build of a longer source to hold to, in the layout's
/// own axes, which stay put while the diagram streams in (see `layered`).
struct Memo: Sendable, Equatable {
    /// Each node's rank.
    var rank: [Int] = []
    /// Each node's centre along its rank (`nil` for one new since the last build). The next
    /// build places it there or further on.
    var along: [Float?] = []
    /// Each rank's centre across the ranks.
    var depth: [Float] = []
    /// Each node's name (empty: known by index).
    var ids: [String] = []

    /// This memo for a layout of nodes named `ids`, each where the node of its name was.
    func renamed(_ newIds: [String]) -> Memo {
        if newIds.isEmpty || ids.isEmpty {
            return self
        }
        var was: [String: Int] = [:]
        for (i, id) in ids.enumerated() {
            was[id] = i
        }
        let old: [Int?] = newIds.map { was[$0] }
        let newRank: [Int] = old.map { o in
            guard let o = o, o < rank.count else { return 0 }
            return rank[o]
        }
        let newAlong: [Float?] = old.map { o in
            guard let o = o, o < along.count else { return nil }
            return along[o]
        }
        return Memo(rank: newRank, along: newAlong, depth: depth, ids: newIds)
    }
}

/// What a streaming build laid out, one `Memo` per layout in the order it ran them, whether a
/// horizontal diagram turned upright, and how big it drew.
final class SteadyMemory {
    var layouts: [Memo] = []
    var turned: Bool = false
    /// The top left corner it was drawn from, in its layouts' points.
    var origin: [Float]? = nil
    /// The size the scene was drawn at.
    var size: [Float] = [0.0, 0.0]
}

private struct SteadyBuild {
    var prev: SteadyMemory?
    var next: SteadyMemory
}

private final class SteadyBuildBox {
    var current: SteadyBuild? = nil
}

#if !os(WASI)
private let steadyThreadKey = "dev.gpua.rune.mermaid.steady"

private func currentSteadyBox() -> SteadyBuildBox {
    let dict = Thread.current.threadDictionary
    if let existing = dict[steadyThreadKey] as? SteadyBuildBox {
        return existing
    }
    let created = SteadyBuildBox()
    dict[steadyThreadKey] = created
    return created
}
#else
// PORT NOTE: WASI is single-threaded; thread-local steady layout state lives in a process-local box.
nonisolated(unsafe) private let wasiSteadyBox = SteadyBuildBox()

private func currentSteadyBox() -> SteadyBuildBox {
    wasiSteadyBox
}
#endif

enum steady {
    /// Runs `f`, a scene build, holding its layouts to `prev`'s, and returns what they laid out.
    static func build<R>(_ prev: SteadyMemory?, _ f: () -> R) -> (R, SteadyMemory) {
        let box = currentSteadyBox()
        let saved = box.current
        box.current = SteadyBuild(prev: prev, next: SteadyMemory())
        defer {
            box.current = saved
        }
        let out = f()
        let next = box.current?.next ?? SteadyMemory()
        return (out, next)
    }

    /// Runs one layout of nodes named `ids`: `place` gets the memo this layout's counterpart in the
    /// last build left (`nil` outside a streaming build, or for a first one) and returns what it
    /// placed and the memo for the next build.
    static func layout<T>(_ ids: [String], _ place: (Memo?) -> (T, Memo)?) -> T? {
        let box = currentSteadyBox()
        guard let cur = box.current else {
            return place(nil)?.0
        }
        let at = cur.next.layouts.count
        let held: Memo?
        if let m = cur.prev, at < m.layouts.count {
            held = m.layouts[at].renamed(ids)
        } else {
            held = nil
        }
        let placed = place(held)
        let out: T?
        var memo: Memo
        if let (t, m) = placed {
            out = t
            memo = m
        } else {
            out = nil
            memo = Memo()
        }
        memo.ids = ids
        box.current?.next.layouts.append(memo)
        return out
    }

    /// Whether the last build turned a horizontal diagram upright, so this one stays turned.
    static func turned() -> Bool {
        currentSteadyBox().current?.prev?.turned ?? false
    }

    static func setTurned(_ turned: Bool) {
        currentSteadyBox().current?.next.turned = turned
    }

    /// The top left corner a drawing with bounds `b` is drawn from: never further in than the last
    /// build's, so a diagram growing up or left moves its nodes on, and one drawing less far out
    /// than before doesn't move them back. A turned diagram starts afresh.
    static func origin(_ b: [Float], _ turned: Bool) -> [Float] {
        let box = currentSteadyBox()
        guard let cur = box.current else {
            return [b[0], b[1]]
        }
        let was: [Float]?
        if let p = cur.prev, p.turned == turned {
            was = p.origin
        } else {
            was = nil
        }
        let o: [Float]
        if let w = was {
            o = [min(w[0], b[0]), min(w[1], b[1])]
        } else {
            o = [b[0], b[1]]
        }
        box.current?.next.origin = o
        return o
    }
}
