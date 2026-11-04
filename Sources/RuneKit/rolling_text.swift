// Ported from: crates/rune-kit/src/rolling_text.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A label whose changed characters roll (iOS numeric/text content transition), for proportional
//! and monospace fonts alike.
//!
//! Each grapheme cluster is its own keyed text node in a soft-clipped row, as wide as its advance
//! in the whole label shaped once (kerning included), so at rest the row sets exactly like the
//! same string as one text. When the text changes,
//! the new clusters are matched to the old ones (common prefix and suffix, then an LCS of the
//! middle for short strings): matched clusters keep their key and slide to their new x on the
//! layout spring; the rest leave through one edge and enter from the other with a small per-glyph
//! stagger. A label given its ``RollingText/value(_:)`` picks the edge from the value's direction, as
//! SwiftUI's `.numericText(value:)` does: up as it rises, down as it falls. The row's width springs to the new width (`widthLeads`). Everything runs on the
//! render clock; reduced motion drops the travel and leaves a crossfade.
//!
//! Keys must survive between builds, so each label remembers its previous clusters by its
//! ``RollingText/new(_:_:)`` key (per thread, per key). Rebuilding with the same text is a no-op.

#if !os(WASI)
import Foundation
#endif
import Rune

/// Extra spring duration per changed glyph, left to right.
private let STAGGER: Float = 0.03
/// The stagger stops growing after this many glyphs, so long replacements still land together.
private let STAGGER_CAP: Int = 6
/// LCS only runs while `old × new` middle clusters fit this budget; longer middles just roll.
private let LCS_BUDGET: Int = 48 * 48

/// Labels remembered per thread; the least recently built go first. A label that was evicted
/// and comes back starts its roll over.
let ROLLING_TEXT_MAX_LABELS: Int = 512
/// Cluster text (and key) bytes remembered per thread.
let ROLLING_TEXT_MAX_BYTES: Int = 256 * 1024

struct RollingTextMemory {
    var clusters: [(String, UInt64)] = []
    var next: UInt64 = 0
    var value: Double? = nil
    var used: UInt64 = 0

    func bytes(_ key: String) -> Int {
        key.utf8.count + clusters.reduce(0) { $0 + $1.0.utf8.count + 16 }
    }
}

struct RollingTextStore {
    var labels: [String: RollingTextMemory] = [:]
    var tick: UInt64 = 0
    var bytes: Int = 0

    /// Drops the least recently built labels until both bounds hold, never `keep` (the label being
    /// built, so one label bigger than the byte bound is still remembered).
    mutating func evict(_ keep: String) {
        if labels.count <= ROLLING_TEXT_MAX_LABELS && bytes <= ROLLING_TEXT_MAX_BYTES {
            return
        }
        var order: [(UInt64, String)] = labels
            .filter { $0.key != keep }
            .map { ($0.value.used, $0.key) }
        order.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        // Down to three quarters, so the sort isn't paid on every new label.
        let maxLabels = ROLLING_TEXT_MAX_LABELS * 3 / 4
        let maxBytes = ROLLING_TEXT_MAX_BYTES * 3 / 4
        for (_, k) in order {
            if labels.count <= maxLabels && bytes <= maxBytes {
                break
            }
            if let m = labels.removeValue(forKey: k) {
                bytes -= m.bytes(k)
            }
        }
    }
}

#if os(WASI)
// PORT NOTE: WASI (wasm32-unknown-wasip1) is single-threaded and lacks `Foundation.Thread`;
// a module-private global preserves Rust `thread_local!` semantics on WASI.
nonisolated(unsafe) private var wasiRollingTextStore = RollingTextStore()

func withRollingTextStore<R>(_ body: (inout RollingTextStore) -> R) -> R {
    body(&wasiRollingTextStore)
}
#else
private final class RollingTextStoreBox {
    var store = RollingTextStore()
}

private let rollingTextThreadKey = "gpua.rune_kit.rolling_text.memory"

func withRollingTextStore<R>(_ body: (inout RollingTextStore) -> R) -> R {
    let dict = Thread.current.threadDictionary
    let box: RollingTextStoreBox
    if let existing = dict[rollingTextThreadKey] as? RollingTextStoreBox {
        box = existing
    } else {
        let created = RollingTextStoreBox()
        dict[rollingTextThreadKey] = created
        box = created
    }
    return body(&box.store)
}
#endif

/// A label that rolls only the characters that changed.
///
/// ```swift
/// RollingText.new("copy-label", copied ? "Copied, clears in 0:\(left)" : "Copy password")
///     .font(k.ty.uiMedium)
///     .build(k)
/// ```
public struct RollingText {
    private var key: String
    private var text: String
    private var fontVal: TextStyle?
    private var colorVal: Color?
    private var springVal: Spring
    private var fromVal: Edge
    private var valueVal: Double?
    private var trailingVal: Bool

    /// The default roll and slide spring: quick, with a hint of overshoot.
    public static let SPRING = Spring(0.36, 0.12)

    /// `key` names this label (it keys the row and remembers the previous text); `text` is what
    /// it shows now.
    public init(_ key: String, _ text: String) {
        self.key = key
        self.text = text
        self.fontVal = nil
        self.colorVal = nil
        self.springVal = Self.SPRING
        self.fromVal = .bottom
        self.valueVal = nil
        self.trailingVal = false
    }

    /// `key` names this label (it keys the row and remembers the previous text); `text` is what
    /// it shows now.
    public static func new(_ key: String, _ text: String) -> RollingText {
        RollingText(key, text)
    }

    public func font(_ font: TextStyle) -> RollingText {
        var copy = self
        copy.fontVal = font
        return copy
    }

    public func color(_ color: Color) -> RollingText {
        var copy = self
        copy.colorVal = color
        return copy
    }

    /// The roll and slide spring (default ``RollingText/SPRING``).
    public func spring(_ spring: Spring) -> RollingText {
        var copy = self
        copy.springVal = spring
        return copy
    }

    /// The edge new glyphs enter from (old ones leave through the opposite edge). Default
    /// `Edge.bottom`; `Edge.top` reads as counting down.
    public func from(_ edge: Edge) -> RollingText {
        var copy = self
        copy.fromVal = edge
        return copy
    }

    /// The number the label shows (SwiftUI's `.numericText(value:)`): when it rises, new glyphs
    /// enter from ``RollingText/from(_:)`` (digits move up); when it falls, from the opposite edge.
    /// Text that changes while the value holds (a new unit or format) rolls from `from`, as a
    /// label without a value does; so does a value that isn't finite.
    public func value(_ value: Double) -> RollingText {
        var copy = self
        copy.valueVal = value
        return copy
    }

    /// The label sits against its trailing edge (right-aligned), so it widens to the left. The
    /// label and its glyphs ride their parent's trailing edge (`El.rideTrailing()`), so new
    /// glyphs roll in where they come to rest and the glyphs that stay or leave hold their
    /// columns, whatever spring the row around it slides on: "9s" → "10s" rolls "10" in beside
    /// the "s", not over it.
    public func trailing() -> RollingText {
        var copy = self
        copy.trailingVal = true
        return copy
    }

    public func build(_ k: Kit) -> El {
        let font = fontVal ?? k.ty.ui
        let color = colorVal ?? k.c.textBase
        let (glyphs, falling) = rollingTextKeys(key, text, valueVal, trailingVal)
        let from = falling ? fromVal.opposite() : fromVal
        let edge = max(font.linePx() * 0.12, 1.0)
        // Glyphs leave the way this build rolls, whichever way they last did.
        let push = Transition.push(from)
        let exit = push.springs(SpringPair(springVal, springVal))
        // The fades sit in padding that negative margins take back out of layout, so the resting
        // glyphs (descenders included) are never faded but rolling glyphs and a growing or
        // shrinking edge stay soft. Glyphs slide on the row's own width-leading X spring. A
        // trailing label and its glyphs instead ride their parent's trailing edge: as the label
        // widens to the left, the glyphs that stay, the ones leaving and the ones entering all
        // hold their columns, whatever springs the rows around them slide on.
        let side = max(font.size * 0.3, 2.0)
        let isTrailing = trailingVal
        func lead(_ e: El) -> El {
            isTrailing ? e.rideTrailing() : e.widthLeads()
        }
        var e = lead(
            row()
                .key(key)
                .role("text")
                .label(text)
                .h(font.linePx() + 2.0 * edge)
                .px(side)
                .py(edge)
                .ml(-side)
                .mr(-side)
                .mt(-edge)
                .mb(-edge)
                .motion(springVal)
        )
        .clipFade(side, edge, side, edge)
        .childExit(exit)

        // Every cell measures as its slice of the whole label shaped once, so the row keeps the
        // run's kerned, fractional advances and the width of the same string set as one text.
        let run = Run.new(text)
        var byteOffsets: [Int] = []
        byteOffsets.reserveCapacity(glyphs.count)
        var byteCursor = 0
        // PORT NOTE: Swift `Character` iteration follows Unicode UAX #29 extended grapheme clusters,
        // matching `unicode_segmentation::UnicodeSegmentation::grapheme_indices(true)`.
        for ch in text {
            byteOffsets.append(byteCursor)
            byteCursor += ch.utf8.count
        }

        var rank = 0
        for (g, at) in zip(glyphs, byteOffsets) {
            let cellSpring: Spring
            if g.entered {
                cellSpring = Spring(springVal.duration + STAGGER * Float(min(rank, STAGGER_CAP)), springVal.bounce)
                rank += 1
            } else {
                cellSpring = springVal
            }
            let tr: Transition
            if g.entered {
                tr = push.springs(SpringPair(cellSpring, springVal))
            } else {
                tr = Transition.asymmetric(Transition.identity(), push)
            }
            e = e.child(
                lead(
                    Rune.text(g.cluster)
                        .key("\(key).\(g.id)")
                        .font(font)
                        .advanceIn(run, at)
                        .color(color)
                        .motion(cellSpring)
                )
                .transition(tr)
            )
        }
        return e
    }
}

struct RollingGlyph {
    var cluster: String
    var id: UInt64
    /// New in this build (it rolls in); otherwise it kept its identity.
    var entered: Bool
}

/// Assigns each cluster of `text` a stable id: clusters matched to the previous text under `key`
/// keep theirs, the rest get fresh ones. Also whether `value` fell below the last finite value.
func rollingTextKeys(
    _ key: String,
    _ text: String,
    _ value: Double?,
    _ trailing: Bool
) -> ([RollingGlyph], Bool) {
    withRollingTextStore { store in
        store.tick += 1
        let tick = store.tick
        let known = store.labels[key] != nil
        var mem = store.labels[key] ?? RollingTextMemory()
        mem.used = tick
        if known {
            store.bytes -= mem.bytes(key)
        }
        let newClusters: [String] = text.map { String($0) }
        let oldClusters: [String] = mem.clusters.map(\.0)
        let matched = rollingTextDiff(oldClusters, newClusters, trailing)
        let fresh = mem.clusters.isEmpty && mem.next == 0
        var glyphs: [RollingGlyph] = []
        glyphs.reserveCapacity(newClusters.count)
        for (c, from) in zip(newClusters, matched) {
            let id: UInt64
            let entered: Bool
            if let i = from {
                id = mem.clusters[i].1
                entered = false
            } else {
                mem.next += 1
                id = mem.next
                entered = !fresh
            }
            glyphs.append(RollingGlyph(cluster: c, id: id, entered: entered))
        }
        mem.clusters = glyphs.map { ($0.cluster, $0.id) }
        let falling: Bool
        if let oldVal = mem.value, let newVal = value, newVal.isFinite && newVal < oldVal {
            falling = true
        } else {
            falling = false
        }
        if let v = value, v.isFinite {
            mem.value = v
        }
        store.bytes += mem.bytes(key)
        store.labels[key] = mem
        store.evict(key)
        return (glyphs, falling)
    }
}

/// For each cluster of `new`, the index of the `old` cluster it continues, if any. Matches keep
/// order: the common prefix and suffix, then an LCS of the middle when it is short. Middle matches
/// survive in runs of two or more, or alone when they hold their place (the ":" of "1:00" →
/// "0:59"); a lone letter that would slide among rolling neighbours rolls too, so "Copy password"
/// → "Copied, clears in" doesn't leave a stray "r" or "s" gliding across the label.
///
/// A `trailing` label holds still at its right edge, so it matches like an odometer, from the
/// right: the suffix first, a prefix only of non-digits (a "\$" slides left with the number, a
/// digit that changes column rolls), and a place counted from the end. "10s" → "100s" keeps
/// "0s" and rolls a new "1" and "0" in; "19s" → "100s" keeps only the "s".
func rollingTextDiff(_ old: [String], _ new: [String], _ trailing: Bool) -> [Int?] {
    var out = [Int?](repeating: nil, count: new.count)
    let n = min(old.count, new.count)
    func digit(_ c: String) -> Bool {
        c.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
    var suf = 0
    func matchSuffix(_ pre: Int) {
        while suf < n - pre && old[old.count - 1 - suf] == new[new.count - 1 - suf] {
            out[new.count - 1 - suf] = old.count - 1 - suf
            suf += 1
        }
    }
    if trailing {
        matchSuffix(0)
    }
    var pre = 0
    while pre < n - suf && old[pre] == new[pre] && !(trailing && digit(new[pre])) {
        out[pre] = pre
        pre += 1
    }
    if !trailing {
        matchSuffix(pre)
    }
    let a = Array(old[pre..<(old.count - suf)])
    let b = Array(new[pre..<(new.count - suf)])
    if a.isEmpty || b.isEmpty || a.count * b.count > LCS_BUDGET {
        return out
    }
    // How far a match slides, in glyphs, measured from whichever end it sits closer to.
    func shift(_ i: Int, _ j: Int) -> Int {
        let end = abs((a.count - i) - (b.count - j))
        return trailing ? end : min(abs(i - j), end)
    }
    // A weighted LCS (suffix table): each match scores more the less it slides, so among
    // equally long subsequences the one that stays in place wins ("1:00" → "0:59" keeps ":").
    func weight(_ i: Int, _ j: Int) -> UInt32 {
        UInt32(8 - min(shift(i, j), 7))
    }
    let w = b.count + 1
    var t = [UInt32](repeating: 0, count: (a.count + 1) * w)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            let skip = max(t[(i + 1) * w + j], t[i * w + j + 1])
            if a[i] == b[j] {
                t[i * w + j] = max(skip, t[(i + 1) * w + j + 1] + weight(i, j))
            } else {
                t[i * w + j] = skip
            }
        }
    }
    var pairs: [(Int, Int)] = []
    var i = 0
    var j = 0
    while i < a.count && j < b.count {
        if a[i] == b[j] && t[i * w + j] == t[(i + 1) * w + j + 1] + weight(i, j) {
            pairs.append((i, j))
            i += 1
            j += 1
        } else if t[(i + 1) * w + j] >= t[i * w + j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    for (k, pair) in pairs.enumerated() {
        let (pi, pj) = pair
        let prevRun = k > 0 && pairs[k - 1].0 == pi - 1 && pairs[k - 1].1 == pj - 1
        let nextRun = k + 1 < pairs.count && pairs[k + 1].0 == pi + 1 && pairs[k + 1].1 == pj + 1
        if prevRun || nextRun || shift(pi, pj) == 0 {
            out[pre + pj] = pre + pi
        }
    }
    return out
}

/// Namespace mirroring `rune_kit::rolling_text` module exports.
public enum rolling_text {
    public typealias RollingText = RuneKit.RollingText
}
