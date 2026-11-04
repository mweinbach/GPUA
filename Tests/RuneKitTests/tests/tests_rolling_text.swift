// Tests ported from: crates/rune-kit/tests/rolling_text.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
import RuneThemeOpenCode
@testable import RuneKit

private struct RollingS {
    var key: String
    var text: String
    var mono: Bool
    var reduced: Bool
}

private func rollingView(_ s: RollingS, _ cx: Cx<RollingS>) -> El {
    cx.reducedMotion(s.reduced)
    let k = Kit.neutral(true)
    let font = s.mono ? k.ty.mono : k.ty.body
    return Rune.row()
        .padding(20.0)
        .child(RollingText.new(s.key, s.text).font(font).build(k))
}

private func makeRollingRuntime(
    _ key: String,
    _ text: String,
    _ mono: Bool,
    _ reduced: Bool
) -> Runtime<RollingS> {
    let s = RollingS(key: key, text: text, mono: mono, reduced: reduced)
    let rt = Runtime.new(s, rollingView, (400.0, 120.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    return rt
}

/// The present (not exiting) glyphs of label `key`, as `(key, text)`.
private func glyphKeys<T>(_ rt: Runtime<T>, _ key: String) -> [(String, String)] {
    let prefix = "\(key)."
    return rt.elements()
        .filter { !$0.inert && ($0.key?.hasPrefix(prefix) == true) }
        .map { ($0.key!, $0.text ?? "") }
}

private func retext(_ rt: Runtime<RollingS>, _ text: String) {
    rt.state.text = text
    rt.invalidate()
}

/// Each frame, each glyph's drawn rect and opacity (`nil` once it has exited).
private typealias Film = [[([Float], Float)?]]

/// Per-frame rects of `keys` over `seconds` at 120 Hz (`nil` once a glyph has exited).
private func recordFilm(_ rt: Runtime<RollingS>, _ keys: [String], _ seconds: Double) -> Film {
    var frames: Film = []
    let count = Int(seconds * 120.0)
    for _ in 0..<count {
        _ = rt.frame(1.0 / 120.0)
        frames.append(keys.map { rt.presented($0) })
    }
    return frames
}

/// The largest frame-to-frame step of any edge of any glyph, in points.
private func largestStep(_ frames: Film) -> Float {
    var worst: Float = 0.0
    if frames.count < 2 { return 0.0 }
    for idx in 0..<(frames.count - 1) {
        let prev = frames[idx]
        let next = frames[idx + 1]
        for (aOpt, bOpt) in zip(prev, next) {
            if let (a, _) = aOpt, let (b, _) = bOpt {
                for k in 0..<4 {
                    worst = max(worst, abs(a[k] - b[k]))
                }
            }
        }
    }
    return worst
}

private struct RollingPair {
    var text: String
    var font: TextStyle
}

/// The label rolled, and below it the same string as one text.
private func pairView(_ s: RollingPair, _: Cx<RollingPair>) -> El {
    let k = Kit.neutral(true)
    return Rune.col()
        .padding(20.0)
        .child(Rune.row().child(RollingText.new("pair", s.text).font(s.font).build(k)))
        .child(Rune.row().child(Rune.text(s.text).font(s.font).key("plain")))
}

private func makePairRuntime(_ text: String, _ font: TextStyle) -> Runtime<RollingPair> {
    let blobs: [[UInt8]] = RuneThemeOpenCode.FONTS.count >= 2
        ? [RuneThemeOpenCode.FONTS[0], RuneThemeOpenCode.FONTS[1]]
        : RuneThemeOpenCode.FONTS
    let fonts = TextSystem(blobs, ("Inter", "IBM Plex Mono"))
    let rt = Runtime.withText(
        RollingPair(text: text, font: font),
        pairView,
        (600.0, 120.0),
        Env.new(true, 2.0),
        fonts
    )
    _ = rt.frame(0.0)
    return rt
}

/// The rolled cells' extent (first left to last right) and the plain text's width, in points.
private func pairWidths(_ rt: Runtime<RollingPair>) -> (Float, Float) {
    let cells: [[Float]] = glyphKeys(rt, "pair").map { rt.presented($0.0)!.0 }
    let first = cells[0]
    let last = cells[cells.count - 1]
    return (last[0] + last[2] - first[0], rt.presented("plain")!.0[2])
}

private struct SecondsState {
    var text: String
    var trailing: Bool
}

private func secondsNumericValue(_ text: String) -> Double {
    var s = text
    while s.last == "s" {
        s.removeLast()
    }
    return Double(s)!
}

private func secondsView(_ s: SecondsState, _: Cx<SecondsState>) -> El {
    let k = Kit.neutral(true)
    var label = RollingText.new("t", s.text)
        .value(secondsNumericValue(s.text))
        .font(k.ty.mono)
    if s.trailing {
        label = label.trailing()
    }
    return Rune.row().w(200.0).padding(20.0).justifyEnd().child(label.build(k))
}

/// The drawn rect of the glyph showing `text` under key `t`: leaving (`exiting`) or staying.
private func secondsCell<S>(_ rt: Runtime<S>, _ text: String, _ exiting: Bool) -> [Float]? {
    rt.elements()
        .first(where: { $0.exiting == exiting && $0.text == text && ($0.key?.hasPrefix("t.") == true) })?
        .rect
}

/// The leaving glyph's y each frame while it's drawn.
private func secondsExitPath<S>(_ rt: Runtime<S>, _ text: String) -> [Float] {
    var ys: [Float] = []
    for _ in 0..<90 {
        _ = rt.frame(1.0 / 120.0)
        if let r = secondsCell(rt, text, true) {
            ys.append(r[1])
        }
    }
    return ys
}

/// A header: a long title that truncates, a spacer, and a usage group (a ring, the context and
/// the cost as trailing labels) that slides on a width-leading spring or on the labels' own.
private struct UsageState {
    var cents: Int64
    var tokens: UInt64
    var leads: Bool
}

private func formatUsageTokens(_ tokens: UInt64) -> String {
    if tokens >= 1_000 {
        let tenths = Int((Double(tokens) / 100.0).rounded(.toNearestOrEven))
        return "\(tenths / 10).\(tenths % 10)K"
    }
    return "\(tokens)"
}

private func formatUsageCost(_ cents: Int64) -> String {
    let rem = abs(cents % 100)
    let pad = rem < 10 ? "0\(rem)" : "\(rem)"
    return "$\(cents / 100).\(pad)"
}

private func usageView(_ s: UsageState, _: Cx<UsageState>) -> El {
    let k = Kit.neutral(true)
    let spring = Spring.new(0.3, 0.0)
    let font = TextStyle.new(12.0, 440.0).lh(16.0).features("'tnum' 1")
    let makeLabel = { (key: String, t: String, v: Double) -> El in
        RollingText.new(key, t).value(v).font(font).spring(spring).trailing().build(k)
    }
    let tokens = formatUsageTokens(s.tokens)
    var usage = Rune.row().key("usage").gap(6.0).centerY().motion(spring)
    if s.leads {
        usage = usage.widthLeads()
    }
    return Rune.row()
        .key("header")
        .w(300.0)
        .h(32.0)
        .px(10.0)
        .gap(8.0)
        .centerY()
        .child(
            Rune.row()
                .centerY()
                .shrink()
                .child(
                    Rune.text("Refactor the session list so pinned rows keep their place")
                        .font(TextStyle.new(13.0, 530.0))
                        .truncate()
                )
        )
        .child(Rune.spacer())
        .child(
            usage
                .child(Rune.el().key("ring").size(14.0, 14.0))
                .child(makeLabel("ctx", tokens, Double(s.tokens)))
                .child(makeLabel("cost", formatUsageCost(s.cents), Double(s.cents)))
        )
}

/// Each glyph's drawn x per frame over `seconds` (leaving glyphs included), by key.
private func usageGlyphPaths(_ rt: Runtime<UsageState>, _ seconds: Double) -> [(String, String, [Float])] {
    var paths: [(String, String, [Float])] = []
    let count = Int(seconds * 120.0)
    for _ in 0..<count {
        _ = rt.frame(1.0 / 120.0)
        for e in rt.elements() {
            guard let key = e.key, key.hasPrefix("cost.") || key.hasPrefix("ctx.") else { continue }
            if let idx = paths.firstIndex(where: { $0.0 == key }) {
                paths[idx].2.append(e.rect[0])
            } else {
                paths.append((key, e.text ?? "", [e.rect[0]]))
            }
        }
    }
    return paths
}

/// How far a path goes the wrong way: against its net travel, or out and back if it has none.
private func wrongWay(_ xs: [Float]) -> Float {
    let first = xs[0]
    let last = xs[xs.count - 1]
    let net = last - first
    if abs(net) < 0.25 {
        return xs.reduce(Float(0.0)) { max($0, abs($1 - first)) }
    }
    let dir: Float = net >= 0.0 ? 1.0 : -1.0
    let back = xs.reduce(Float(0.0)) { max($0, (first - $1) * dir) }
    let past = xs.reduce(Float(0.0)) { max($0, ($1 - last) * dir) }
    return max(back, past)
}

@Suite("RollingTextIntegrationTests", .serialized)
struct RollingTextIntegrationTests {
    @Test
    func aCountdownRollsOnlyTheChangedDigitsAndTheRestKeepTheirIdentity() {
        for mono in [false, true] {
            let key = mono ? "count-mono" : "count-sans"
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = makeRollingRuntime(key, "0:30", mono, false)
            let before = glyphKeys(rt, key)
            let texts = before.map(\.1)
            #expect(texts == ["0", ":", "3", "0"])
            let rest: [[Float]] = before.map { rt.presented($0.0)!.0 }

            retext(rt, "0:29")
            _ = rt.frame(0.0)
            let after = glyphKeys(rt, key)
            #expect(after[0] == before[0] && after[1] == before[1], "\"0\" and \":\" keep their keys")
            #expect(
                after[2...].allSatisfy { a in before.allSatisfy { b in b.0 != a.0 } },
                "\"2\" and \"9\" are new glyphs"
            )
            let all: [String] = before.map(\.0) + after[2...].map(\.0)
            let frames = recordFilm(rt, all, 1.5)

            let mid = frames[12]
            for i in 0..<2 {
                let (r, o) = mid[i]!
                #expect(r == rest[i] && o == 1.0, "\(mono): unchanged glyph \(i) never moves or fades")
            }
            let line = rest[0][3]
            for i in 2..<4 {
                let (r, o) = mid[i]!
                #expect(
                    r[1] < rest[i][1] - 1.0 && r[1] > rest[i][1] - line,
                    "\(mono): old digit \(i) rolls up: \(r)"
                )
                #expect(o < 1.0)
            }
            for glyph in mid[4..<6] {
                let (r, o) = glyph!
                #expect(
                    r[1] > rest[0][1] + 1.0 && r[1] < rest[0][1] + line,
                    "\(mono): new digit rolls in from below: \(r)"
                )
                #expect(o > 0.0 && o < 1.0)
            }
            let step = largestStep(frames)
            #expect(step < 2.5, "\(mono): no glyph jumps (largest step \(step) pt at 120 Hz)")

            let end = frames.last!
            #expect(end[2] == nil && end[3] == nil, "old digits unmount once they have rolled out")
            for glyph in end[4..<6] {
                let (r, o) = glyph!
                #expect(
                    abs(r[1] - rest[0][1]) < 0.01 && o == 1.0,
                    "new digits land on the line: \(r) \(o) vs \(rest[0])"
                )
            }
        }
    }

    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aProportionalLabelKeepsItsPrefixAndSpringsItsWidth() {
        withRollingTextStore { $0 = RollingTextStore() }
        let key = "copy"
        let rt = makeRollingRuntime(key, "Copy password", false, false)
        let before = glyphKeys(rt, key)
        let rest: [[Float]] = before[..<3].map { rt.presented($0.0)!.0 }
        let width = rt.presented(key)!.0[2]

        retext(rt, "Copied, clears in 0:30")
        _ = rt.frame(0.0)
        let after = glyphKeys(rt, key)
        #expect(Array(after[..<3]).map(\.0) == Array(before[..<3]).map(\.0) && Array(after[..<3]).map(\.1) == Array(before[..<3]).map(\.1), "\"Cop\" keeps its glyphs")
        #expect(after.map(\.1).joined() == "Copied, clears in 0:30")

        let keys: [String] = before.map(\.0) + after[3...].map(\.0) + [key]
        let frames = recordFilm(rt, keys, 1.0)
        for f in frames {
            for i in 0..<3 {
                // Its glyphs stay put; the "p" cell's width follows its new kerning ("py" → "pi").
                let cur = f[i]!.0
                #expect(cur[0] == rest[i][0] && cur[1] == rest[i][1], "the kept prefix stays put")
            }
        }
        let widths: [Float] = frames.map { $0.last!!.0[2] }
        let target = widths.last!
        #expect(target > width + 40.0, "\(width) → \(target)")
        #expect(widths[0] < width + (target - width) * 0.2, "the width springs from the old width: \(widths[0])")
        #expect(largestStep(frames) < 4.0, "no jumps: \(largestStep(frames))")
    }

    @Test
    func aRolledLabelIsAsWideAsTheSameStringSetAsOneText() {
        let plex = TextStyle.new(11.0, 400.0).mono()
        let inter = TextStyle.new(13.0, 400.0)
        let cases: [(String, TextStyle)] = [
            ("Copy password", plex),
            ("Copy password", inter),
            ("AVATAR Tokyo, WAVE", inter),
        ]
        for (text, font) in cases {
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = makePairRuntime(text, font)
            let (rolled, plain) = pairWidths(rt)
            // PORT NOTE: Swift `String` iterates extended grapheme clusters natively (`Character`),
            // matching `unicode_segmentation::UnicodeSegmentation::graphemes(true)`.
            var separate: Float = 0.0
            for ch in text {
                separate += rt.text.measure(String(ch), font, 2.0).0
            }
            #expect(
                abs(rolled - plain) <= 0.25,
                "\(text): rolled \(rolled) vs one text \(plain) (0.5 device px)"
            )
            if font.size == 11.0 && RuneThemeOpenCode.FONTS.count >= 2 {
                #expect(separate - plain > 4.0, "Plex rounds each glyph up: \(separate) vs \(plain)")
            }
        }
    }

    @Test
    func anEmojiSequenceIsOneCell() {
        withRollingTextStore { $0 = RollingTextStore() }
        let family = "👩\u{200d}👩\u{200d}👧"
        let text = "\(family) 2 👍🏽 e\u{301}"
        let rt = makePairRuntime(text, TextStyle.new(13.0, 400.0))
        let cells = glyphKeys(rt, "pair").map(\.1)
        #expect(cells == [family, " ", "2", " ", "👍🏽", " ", "e\u{301}"])
        let (rolled, plain) = pairWidths(rt)
        #expect(abs(rolled - plain) <= 0.25, "rolled \(rolled) vs one text \(plain)")
    }

    @Test
    func keptGlyphsGlideToTheirNewAdvance() {
        withRollingTextStore { $0 = RollingTextStore() }
        let font = TextStyle.new(13.0, 400.0)
        let rt = makePairRuntime("1:00", font)
        rt.state.text = "11:00"
        rt.invalidate()
        _ = rt.frame(0.0)
        for _ in 0..<240 {
            _ = rt.frame(1.0 / 120.0)
        }
        let (rolled, plain) = pairWidths(rt)
        #expect(
            abs(rolled - plain) <= 0.25,
            "after a change the cells settle on the new run: \(rolled) vs \(plain)"
        )
    }

    @Test
    func reducedMotionCrossfadesInPlace() {
        withRollingTextStore { $0 = RollingTextStore() }
        let key = "reduced"
        let rt = makeRollingRuntime(key, "0:30", false, true)
        let before = glyphKeys(rt, key)
        let rest = rt.presented(before[2].0)!.0
        retext(rt, "0:29")
        _ = rt.frame(0.0)
        let frames = recordFilm(rt, [before[2].0], 0.08)
        let (r, o) = frames.last![0]!
        #expect(r == rest, "no travel under reduced motion")
        #expect(o > 0.0 && o < 1.0, "the old digit fades: \(o)")
    }

    @Test
    func theLabelReadsAsTextInLookups() {
        withRollingTextStore { $0 = RollingTextStore() }
        let rt = makeRollingRuntime("lookup", "Import 3 items", false, false)
        let byText = { (rt: Runtime<RollingS>, text: String) -> String? in
            rt.elements().first(where: { $0.text == text })?.key
        }
        #expect(byText(rt, "Import 3 items") == "lookup")
        retext(rt, "Importing…")
        _ = rt.frame(0.0)
        #expect(byText(rt, "Importing…") == "lookup")
        #expect(byText(rt, "Import 3 items") == nil)

        // A labelled element that isn't text still has none.
        let btnRt = Runtime.new(
            (),
            { (_: Void, _: Cx<Void>) -> El in
                Button.new("Save").build(Kit.neutral(true)).key("save")
            },
            (200.0, 60.0),
            Env.new(true, 2.0)
        )
        _ = btnRt.frame(0.0)
        let save = btnRt.elements().first(where: { $0.key == "save" })!
        #expect(save.label == "Save" && save.text == nil)
    }

    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func insideAGrowthRowItsWidthSpringsUnderAnimateLayout() {
        struct GrowthRowState {
            var label: String
            var animate: Bool
            var secondRow: Bool
        }
        func view(_ s: GrowthRowState, _: Cx<GrowthRowState>) -> El {
            let k = Kit.neutral(true)
            let rowOf = { (key: String, label: String) -> El in
                var r = Rune.row()
                    .key("trigger")
                    .h(28.0)
                    .child(RollingText.new(key, label).font(k.ty.body).build(k))
                    .child(Rune.el().key("\(key)-chevron").size(14.0, 14.0))
                if s.animate {
                    r = r.animateLayout()
                }
                return r
            }
            var stack = Rune.col()
                .wFull()
                .growth(GrowthSpec())
                .child(Rune.col().key("r0").wFull().child(rowOf("count", s.label)))
            if s.secondRow {
                stack = stack.child(Rune.col().key("r1").wFull().child(rowOf("fresh", "Used 1 tool")))
            }
            return stack
        }
        let chevronX = { (rt: Runtime<GrowthRowState>) -> Float in
            rt.elements().first(where: { $0.key == "count-chevron" })!.rect[0]
        }
        for animate in [false, true] {
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = Runtime.new(
                GrowthRowState(label: "Used 1 tool", animate: animate, secondRow: false),
                view,
                (400.0, 100.0),
                Env.new(true, 2.0)
            )
            _ = rt.frame(0.0)
            let from = chevronX(rt)
            rt.update { s, _ in
                s.label = "Used 12 tools"
                s.secondRow = true
            }
            var xs: [Float] = []
            for f in 0..<120 {
                _ = rt.frame(1.0 / 120.0)
                if f == 0 {
                    #expect(
                        rt.elements()
                            .filter { $0.key?.hasPrefix("fresh.") == true }
                            .allSatisfy { $0.opacity == 1.0 },
                        "a newly mounted growth row's initial glyphs ride the row instead of rolling in"
                    )
                }
                xs.append(chevronX(rt))
            }
            let to = xs.last!
            #expect(to > from + 10.0, "the label widens: \(from) → \(to)")
            var step = abs(xs[0] - from)
            for i in 0..<(xs.count - 1) {
                step = max(step, abs(xs[i + 1] - xs[i]))
            }
            if animate {
                #expect(step < (to - from) / 4.0, "the width springs: a \(step)pt step of \(to - from)")
            } else {
                #expect(step > (to - from) * 0.9, "a growth row's contents snap by default: \(step)pt")
            }
        }
    }

    /// A count that mounts with a fade and changes while its presence is still settling (a tool
    /// group's head swapping in, then a second tool joining a moment later) rolls its new digit in.
    @Test
    func aDigitChangingSoonAfterTheLabelFadesInRollsIn() {
        struct FadeInState {
            var label: String
            var mounted: Bool
            var growth: Bool
            var explicitFade: Bool
        }
        func view(_ s: FadeInState, _: Cx<FadeInState>) -> El {
            let k = Kit.neutral(true)
            var r = Rune.row().key("trigger").h(28.0)
            if s.mounted {
                var count = RollingText.new("count", s.label).font(k.ty.body).build(k)
                if s.explicitFade {
                    count = count.transition(
                        Transition.opacity().springs(
                            SpringPair(Spring.new(0.22, 0.0), Spring.new(0.18, 0.0))
                        )
                    )
                }
                r = r.child(count)
            }
            r = r.child(Rune.el().key("chevron").size(14.0, 14.0))
            if !s.growth {
                return Rune.col().wFull().child(r)
            }
            return Rune.col()
                .wFull()
                .growth(GrowthSpec())
                .child(Rune.col().key("r0").wFull().child(r.animateLayout()))
        }
        let modes: [(Bool, Bool)] = [(false, false), (true, false), (false, true)]
        let waits: [Float] = [0.5, 1.0, 2.0]
        for (growth, explicitFade) in modes {
            for wait in waits {
                withRollingTextStore { $0 = RollingTextStore() }
                let rt = Runtime.new(
                    FadeInState(label: "Used 1", mounted: false, growth: growth, explicitFade: explicitFade),
                    view,
                    (400.0, 100.0),
                    Env.new(true, 2.0)
                )
                _ = rt.frame(0.0)
                rt.update { s, _ in s.mounted = true }
                for _ in 0..<Int(wait * 120.0) {
                    _ = rt.frame(1.0 / 120.0)
                }
                let (_, labelOp) = rt.presented("count")!
                #expect(labelOp > 0.99, "wait \(wait)s: the label has faded in: \(labelOp)")
                rt.update { s, _ in s.label = "Used 2" }
                _ = rt.frame(1.0 / 120.0)
                let two = rt.elements().first(where: {
                    !$0.inert && $0.text == "2" && ($0.key?.hasPrefix("count.") == true)
                })!
                #expect(
                    two.opacity < 0.5,
                    "growth \(growth) explicit \(explicitFade) wait \(wait)s: the new digit fades in: op \(two.opacity)"
                )
                #expect(
                    abs(two.rect[1] - two.target[1]) > 1.0,
                    "growth \(growth) explicit \(explicitFade) wait \(wait)s: the new digit rolls in: \(two.rect) -> \(two.target)"
                )
            }
        }
    }

    /// A label given its value rolls new digits up while it rises and down when it falls.
    @Test
    func aValuePicksTheRollDirection() {
        struct DirState {
            var text: String
            var value: Double
        }
        func view(_ s: DirState, _: Cx<DirState>) -> El {
            let k = Kit.neutral(true)
            return Rune.row()
                .padding(20.0)
                .child(RollingText.new("dir", s.text).value(s.value).font(k.ty.body).build(k))
        }
        withRollingTextStore { $0 = RollingTextStore() }
        let rt = Runtime.new(DirState(text: "8", value: 8.0), view, (400.0, 120.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let steps: [(String, Double, Bool)] = [("9", 9.0, true), ("8", 8.0, false), ("9", 9.0, true)]
        for (text, value, below) in steps {
            rt.update { s, _ in
                s = DirState(text: text, value: value)
            }
            _ = rt.frame(1.0 / 120.0)
            let e = rt.elements().first(where: {
                !$0.inert && $0.text == text && ($0.key?.hasPrefix("dir.") == true)
            })!
            let dy = e.rect[1] - e.target[1]
            #expect(
                below ? (dy > 1.0) : (dy < -1.0),
                "\(text): enters from \(below ? "below" : "above"): dy \(dy)"
            )
            for _ in 0..<120 {
                _ = rt.frame(1.0 / 120.0)
            }
        }
    }

    /// Right-aligned, "9s" → "10s" widens the label to the left. With `trailing`, the "1" and "0"
    /// roll in where they come to rest while the "s" holds still; without it they ride in from the
    /// right with the label's slide, over the "s".
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aTrailingLabelRollsNewDigitsInTheirColumns() {
        let drift = { (trailing: Bool) -> (Float, Float) in
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = Runtime.new(
                SecondsState(text: "9s", trailing: trailing),
                secondsView,
                (400.0, 120.0),
                Env.new(true, 2.0)
            )
            _ = rt.frame(0.0)
            rt.update { s, _ in s.text = "10s" }
            let xOf = { (rt: Runtime<SecondsState>, text: String) -> (Float, Float)? in
                rt.elements()
                    .first(where: { !$0.inert && $0.text == text && ($0.key?.hasPrefix("t.") == true) })
                    .map { ($0.rect[0], $0.target[0]) }
            }
            var newDrift: Float = 0.0
            var sDrift: Float = 0.0
            let s0 = xOf(rt, "s")!.0
            for _ in 0..<90 {
                _ = rt.frame(1.0 / 120.0)
                for d in ["1", "0"] {
                    let (at, rest) = xOf(rt, d)!
                    newDrift = max(newDrift, abs(at - rest))
                }
                sDrift = max(sDrift, abs(xOf(rt, "s")!.0 - s0))
            }
            return (newDrift, sDrift)
        }
        let (newDrift, sDrift) = drift(true)
        #expect(newDrift < 0.75, "new digits roll in their columns: \(newDrift) pt off")
        #expect(sDrift < 0.5, "the s holds still: \(sDrift) pt")
        #expect(drift(false).0 > 3.0, "without trailing they ride the slide")
    }

    /// A counter given its value: under reduced motion a falling number still swaps in place, and a
    /// value that turns back mid-roll retargets without a jump and settles.
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aValueUnderReducedMotionSwapsInPlaceAndAReversalMidRollRetargets() {
        struct CounterState {
            var value: Double
            var reduced: Bool
        }
        func formatCounter(_ v: Double) -> String {
            let asInt = Int(v)
            return Double(asInt) == v ? "\(asInt)" : "\(v)"
        }
        func view(_ s: CounterState, _ cx: Cx<CounterState>) -> El {
            cx.reducedMotion(s.reduced)
            let k = Kit.neutral(true)
            return Rune.row()
                .padding(20.0)
                .child(
                    RollingText.new("n", formatCounter(s.value))
                        .value(s.value)
                        .font(k.ty.mono)
                        .build(k)
                )
        }
        let glyph = { (rt: Runtime<CounterState>, text: String) -> ([Float], [Float])? in
            rt.elements()
                .first(where: { !$0.inert && $0.text == text && ($0.key?.hasPrefix("n.") == true) })
                .map { ($0.rect, $0.target) }
        }

        withRollingTextStore { $0 = RollingTextStore() }
        let rtReduced = Runtime.new(
            CounterState(value: 9.0, reduced: true),
            view,
            (400.0, 120.0),
            Env.new(true, 2.0)
        )
        _ = rtReduced.frame(0.0)
        rtReduced.update { s, _ in s.value = 8.0 }
        for _ in 0..<4 {
            _ = rtReduced.frame(1.0 / 120.0)
            let (rect, target) = glyph(rtReduced, "8")!
            #expect(rect[1] == target[1], "no roll under reduced motion")
        }

        withRollingTextStore { $0 = RollingTextStore() }
        let rt = Runtime.new(
            CounterState(value: 8.0, reduced: false),
            view,
            (400.0, 120.0),
            Env.new(true, 2.0)
        )
        _ = rt.frame(0.0)
        rt.update { s, _ in s.value = 9.0 }
        for _ in 0..<8 {
            _ = rt.frame(1.0 / 120.0)
        }
        rt.update { s, _ in s.value = 8.0 }
        var last = glyph(rt, "8").map { $0.0[1] }
        var worst: Float = 0.0
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            let y = glyph(rt, "8").map { $0.0[1] }
            if let a = last, let b = y {
                worst = max(worst, abs(a - b))
            }
            last = y
        }
        let (rect, target) = glyph(rt, "8")!
        #expect(worst < 4.0, "the returning 8 moves smoothly: \(worst) pt in a frame")
        #expect(rect == target, "and settles")
    }

    /// Old glyphs leave the way the new ones enter, decided by the commit that removes them: down on
    /// a first count down, and down again when the value turns back mid-roll.
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func leavingGlyphsRollTheWayThisChangeMoves() {
        withRollingTextStore { $0 = RollingTextStore() }
        let rt = Runtime.new(
            SecondsState(text: "9s", trailing: false),
            secondsView,
            (400.0, 120.0),
            Env.new(true, 2.0)
        )
        _ = rt.frame(0.0)
        rt.update { s, _ in s.text = "8s" }
        let ys1 = secondsExitPath(rt, "9")
        let nonDecreasing1 = (0..<max(0, ys1.count - 1)).allSatisfy { ys1[$0 + 1] >= ys1[$0] - 0.01 }
        #expect(
            ys1.count > 4 && nonDecreasing1 && ys1[ys1.count - 1] > ys1[0] + 2.0,
            "a first count down rolls the 9 out downward: \(ys1)"
        )

        rt.update { s, _ in s.text = "9s" }
        for _ in 0..<8 {
            _ = rt.frame(1.0 / 120.0)
        }
        rt.update { s, _ in s.text = "8s" }
        let ys2 = secondsExitPath(rt, "9")
        // It was rising; the spring carries that on for a moment before it turns, under a point.
        let minY2 = ys2.min() ?? .greatestFiniteMagnitude
        let back = ys2[0] - minY2
        #expect(
            ys2.count > 2 && back < 1.0 && ys2[ys2.count - 1] > ys2[0] + 2.0,
            "turning back mid-roll, the 9 leaves downward: \(ys2)"
        )

        rt.update { s, _ in s.text = "9s" }
        let ys3 = secondsExitPath(rt, "8")
        let nonIncreasing3 = (0..<max(0, ys3.count - 1)).allSatisfy { ys3[$0 + 1] <= ys3[$0] + 0.01 }
        #expect(
            ys3.count > 4 && nonIncreasing3,
            "counting up again, the 8 leaves upward: \(ys3)"
        )
    }

    /// In a trailing label every glyph holds its column while the edge moves: the leaving ones where
    /// they were drawn, the entering ones where they come to rest. 9s → 10s → 11s, then 19s → 100s.
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aTrailingLabelHoldsLeavingAndEnteringGlyphsInTheirColumns() {
        let run = { (from: String, to: String, gone: [String], came: [String]) -> Float in
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = Runtime.new(
                SecondsState(text: from, trailing: true),
                secondsView,
                (400.0, 120.0),
                Env.new(true, 2.0)
            )
            _ = rt.frame(0.0)
            let starts: [Float] = gone.map { secondsCell(rt, $0, false)![0] }
            rt.update { s, _ in s.text = to }
            var worst: Float = 0.0
            for _ in 0..<90 {
                _ = rt.frame(1.0 / 120.0)
                for (g, x0) in zip(gone, starts) {
                    if let r = secondsCell(rt, g, true) {
                        worst = max(worst, abs(r[0] - x0))
                    }
                }
                for c in came {
                    let e = rt.elements().first(where: {
                        !$0.exiting && $0.text == c && ($0.key?.hasPrefix("t.") == true)
                    })!
                    worst = max(worst, abs(e.rect[0] - e.target[0]))
                }
            }
            return worst
        }
        let a = run("9s", "10s", ["9"], ["1"])
        #expect(a < 0.75, "9s → 10s: \(a) pt off")

        withRollingTextStore { $0 = RollingTextStore() }
        let rt = Runtime.new(
            SecondsState(text: "10s", trailing: true),
            secondsView,
            (400.0, 120.0),
            Env.new(true, 2.0)
        )
        _ = rt.frame(0.0)
        let x0 = secondsCell(rt, "0", false)![0]
        rt.update { s, _ in s.text = "11s" }
        var drift: Float = 0.0
        for _ in 0..<90 {
            _ = rt.frame(1.0 / 120.0)
            if let r = secondsCell(rt, "0", true) {
                drift = max(drift, abs(r[0] - x0))
            }
        }
        #expect(drift < 0.5, "10s → 11s: the 0 rolls out in its column: \(drift) pt")

        let c = run("19s", "100s", ["1", "9"], [])
        #expect(c < 0.75, "19s → 100s: \(c) pt off")
    }

    /// The header's context and cost rise as a step finishes ($0.42 → $0.49), then past a round
    /// number ($0.49 → $10.45, 13.7K → 111.7K), in a usage group that slides on a width-leading
    /// spring and in one that slides on the labels' own. Every glyph, leaving ones included, holds
    /// its column or moves one way: none drifts out and back against the group's slide.
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func trailingLabelsInASlidingRowNeverReverse() {
        for leads in [true, false] {
            withRollingTextStore { $0 = RollingTextStore() }
            let rt = Runtime.new(
                UsageState(cents: 42, tokens: 12_345, leads: leads),
                usageView,
                (400.0, 80.0),
                Env.new(true, 2.0)
            )
            _ = rt.frame(0.0)
            let costLeft = { (rt: Runtime<UsageState>) -> Float in
                rt.presented("cost")!.0[0]
            }
            let before = costLeft(rt)
            let deltas: [(Int64, UInt64, Double)] = [(7, 1_400, 0.8), (996, 98_000, 1.0)]
            for (step, (cents, tokens, secs)) in deltas.enumerated() {
                rt.update { s, _ in
                    s.cents += cents
                    s.tokens += tokens
                }
                for (key, text, xs) in usageGlyphPaths(rt, secs) {
                    let w = wrongWay(xs)
                    let sample = Array(xs.prefix(40))
                    #expect(
                        w < 0.5,
                        "leads \(leads), step \(step): \(key) (\(text)) goes \(w) pt the wrong way: \(sample)"
                    )
                }
            }
            let after = costLeft(rt)
            #expect(
                after < before - 5.0,
                "leads \(leads): the cost widens to the left by a digit: \(before) → \(after)"
            )
        }
    }
}
