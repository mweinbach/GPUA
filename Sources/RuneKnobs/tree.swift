// Ported from: crates/rune-knobs/src/tree.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// What the side panel lists, in what order and what's folded, and its keys. Groups filed
/// under a page fold with it. The Tree layout starts with everything folded, a list of all the
/// parts with a dot on what's on screen, until one is opened; the others open what's on screen. ``LAYOUT`` picks how they're laid out
/// while comparing. ↑/↓ move a row, ← → fold and open a header or step a knob, `/` starts the
/// filter (a real text field: see `Knobs.filterKey` for the few keys the panel keeps while
/// it edits), Esc stops filtering, then clears the filter, then closes.

import Rune

/// The On screen layout's second caption.
let REST: String = "Not on screen"
let SEEN: String = "On screen"

/// A row the keyboard can stand on: a page's header, a group's header (by index), or one of a
/// group's knobs.
enum Node: Sendable, Equatable, Hashable {
    case page(String)
    case group(Int)
    case knob(Int, Int)
}

enum Layout: Sendable, Equatable, Hashable {
    case tree
    case onScreen
    case tabs
}

func layout(_ k: Knobs) -> Layout {
    switch Int(k.get(LAYOUT).rounded()) {
    case 1: return .onScreen
    case 2: return .tabs
    default: return .tree
    }
}

enum Head: Sendable, Equatable, Hashable {
    /// A page's header, which folds the page.
    case page(String)
    /// A caption over the groups, which doesn't fold.
    case caption(String)
    /// The groups alone.
    case bare
}

/// A group as listed: open or folded, its part on screen or not, the knobs it shows (all of
/// them unless filtered), and whether it's listed apart from its page, so its title names the
/// page ("Item page · Header") and needs no on-screen mark.
struct Sub: Sendable, Equatable {
    var g: Int
    var open: Bool
    var seen: Bool
    var knobs: [Int]
    var full: Bool
}

struct Section: Sendable, Equatable {
    var head: Head
    var open: Bool
    var seen: Bool
    var subs: [Sub]
}

/// The whole list, and in the Tabs layout the tabs `(page, onScreen)` and the one showing.
struct Plan: Sendable, Equatable {
    var sections: [Section] = []
    var tabs: [(String, Bool)] = []
    var tab: String? = nil
    var seen: Set<Int> = []

    init(
        sections: [Section] = [],
        tabs: [(String, Bool)] = [],
        tab: String? = nil,
        seen: Set<Int> = []
    ) {
        self.sections = sections
        self.tabs = tabs
        self.tab = tab
        self.seen = seen
    }

    static func == (lhs: Plan, rhs: Plan) -> Bool {
        guard lhs.sections == rhs.sections,
              lhs.tab == rhs.tab,
              lhs.seen == rhs.seen,
              lhs.tabs.count == rhs.tabs.count
        else { return false }
        for (a, b) in zip(lhs.tabs, rhs.tabs) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }
}

/// Pages in the order their first group is declared.
private func pages(_ groups: [Group]) -> [String] {
    var out: [String] = []
    for g in groups {
        let p = g.page()
        if !out.contains(p) {
            out.append(p)
        }
    }
    return out
}

/// Knob `i` of `g` matches every word of `words` across its page, group, title and description.
private func matches(_ g: Group, _ i: Int, _ words: [String]) -> Bool {
    let d = g.knobs[i]
    let hay = "\(g.under) \(g.name) \(d.title()) \(d.name) \(d.describe())".lowercased()
    return words.allSatisfy { hay.contains($0) }
}

private func splitAsciiOrUnicodeWhitespace(_ s: String) -> [String] {
    s.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
}

/// What the panel lists for `seen` (the groups whose part of the window is on screen).
func plan(_ k: Knobs, _ groups: [Group], _ seen: Set<Int>) -> Plan {
    let words = splitAsciiOrUnicodeWhitespace(k.query)
    // `lead`: open by default while on screen; otherwise folded until it's opened.
    let sub: (Int, Bool, Bool) -> Sub = { g, full, lead in
        let s = seen.contains(g)
        return Sub(
            g: g,
            open: !k.isFolded(groups[g].name, !(s && lead)),
            seen: s,
            knobs: Array(0..<groups[g].knobs.count),
            full: full
        )
    }

    var result = Plan()
    if !words.isEmpty {
        var subs: [Sub] = []
        for g in 0..<groups.count {
            let matchingKnobs = (0..<groups[g].knobs.count).filter { i in
                matches(groups[g], i, words)
            }
            if !matchingKnobs.isEmpty {
                var s = sub(g, true, true)
                s.open = true
                s.knobs = matchingKnobs
                subs.append(s)
            }
        }
        result.sections.append(Section(head: .bare, open: true, seen: false, subs: subs))
        result.seen = seen
        return result
    }

    let ofPage: (String) -> [Int] = { page in
        (0..<groups.count).filter { groups[$0].page() == page }
    }

    switch layout(k) {
    case .tree:
        for p in pages(groups) {
            let gs = ofPage(p)
            let lit = gs.contains(where: { seen.contains($0) })
            if gs.count == 1 && groups[gs[0]].under.isEmpty {
                result.sections.append(
                    Section(head: .bare, open: true, seen: lit, subs: [sub(gs[0], false, false)])
                )
            } else {
                // A page opens with the group left open in it.
                let holds = gs.contains { g in
                    k.group == groups[g].name && k.unfolded.contains(groups[g].name)
                }
                result.sections.append(
                    Section(
                        head: .page(p),
                        open: !k.isFolded(p, !holds),
                        seen: lit,
                        subs: gs.map { sub($0, false, false) }
                    )
                )
            }
        }

    case .onScreen:
        var on: [Int] = []
        var off: [Int] = []
        for g in 0..<groups.count {
            if seen.contains(g) {
                on.append(g)
            } else {
                off.append(g)
            }
        }
        if !on.isEmpty {
            result.sections.append(
                Section(head: .caption(SEEN), open: true, seen: true, subs: on.map { sub($0, true, true) })
            )
        }
        if !off.isEmpty {
            result.sections.append(
                Section(head: .caption(REST), open: true, seen: false, subs: off.map { sub($0, true, true) })
            )
        }

    case .tabs:
        result.tabs = pages(groups).map { p in
            (p, ofPage(p).contains(where: { seen.contains($0) }))
        }
        let picked = k.tab.flatMap { t in result.tabs.first(where: { $0.0 == t }) }
        let chosen = (picked ?? result.tabs.first(where: { $0.1 }) ?? result.tabs.first)?.0
        result.tab = chosen
        if let t = chosen {
            result.sections.append(
                Section(head: .bare, open: true, seen: true, subs: ofPage(t).map { sub($0, false, true) })
            )
        }
    }

    result.seen = seen
    return result
}

/// The rows the keyboard walks, top to bottom.
func rows(_ plan: Plan) -> [Node] {
    var out: [Node] = []
    for s in plan.sections {
        if case .page(let p) = s.head {
            out.append(.page(p))
        }
        if !s.open {
            continue
        }
        for sub in s.subs {
            out.append(.group(sub.g))
            if sub.open {
                for i in sub.knobs {
                    out.append(.knob(sub.g, i))
                }
            }
        }
    }
    return out
}

/// What a key did: nothing, a change to show at once, or a fold to animate.
enum Did: Sendable, Equatable, Hashable {
    case not
    case now
    case fold
}

private func singleDigitIndex(_ s: String) -> Int? {
    guard s.utf8.count == 1,
          let b = s.utf8.first,
          b >= UInt8(ascii: "1"),
          b <= UInt8(ascii: "9")
    else { return nil }
    return Int(b - UInt8(ascii: "1"))
}

extension Knobs {
    func at() -> Node? {
        atNode
    }

    /// Puts the keyboard on `n`; a group's row makes it the panel's group.
    mutating func setAt(_ n: Node?, _ groups: [Group]) {
        atNode = n
        let g: Int
        let i: Int
        switch n {
        case .knob(let gi, let ki)?:
            g = gi
            i = ki
        case .group(let gi)?:
            g = gi
            i = 0
        default:
            return
        }
        if g >= 0 && g < groups.count {
            group = groups[g].name
            cursor = i
        }
    }

    /// The side panel's keys, against what it lists now.
    mutating func treeKey(_ groups: [Group], _ plan: Plan, _ ev: KeyEvent) -> Did {
        if ev.mods.cmd || ev.mods.alt || ev.mods.ctrl {
            return .not
        }
        // Focus left the field without the panel hearing of it (a click elsewhere).
        if filtering && !editModel.focused {
            filtering = false
        }
        if filtering {
            return filterKey(groups, plan, ev)
        }
        let rowNodes = rows(plan)
        let here = atNode.flatMap { n in rowNodes.firstIndex(of: n) }
        let validAt: Node? = here != nil ? atNode : nil

        let did: Did
        switch ev.key {
        case .escape where !query.isEmpty:
            setQuery("")
            did = .now

        case .escape:
            close()
            return .now

        case .up, .down, .tab:
            did = moveRow(groups, plan, ev)

        case .left, .right:
            let right = (ev.key == .right)
            switch validAt {
            case .knob(let g, let i)?:
                step(groups[g].knobs[i], right, ev.mods.shift)
                did = .now

            case .group(let g)?:
                let name = groups[g].name
                let isOpen = plan.sections.flatMap(\.subs).contains { $0.g == g && $0.open }
                if (right && !isOpen) || (!right && isOpen) {
                    setFolded(name, !right)
                    did = .fold
                } else if right && isOpen {
                    if let idx = here, idx + 1 < rowNodes.count {
                        setAt(rowNodes[idx + 1], groups)
                    }
                    did = .now
                } else {
                    // A folded group's ← goes up to its page.
                    if !groups[g].under.isEmpty && rowNodes.contains(.page(groups[g].under)) {
                        setAt(.page(groups[g].under), groups)
                    }
                    did = .now
                }

            case .page(let p)?:
                let isOpen = plan.sections.contains { $0.head == .page(p) && $0.open }
                if (right && !isOpen) || (!right && isOpen) {
                    setFolded(p, !right)
                    did = .fold
                } else if right && isOpen {
                    if let idx = here, idx + 1 < rowNodes.count {
                        setAt(rowNodes[idx + 1], groups)
                    }
                    did = .now
                } else {
                    did = .now
                }

            case nil where !rowNodes.isEmpty:
                setAt(rowNodes[0], groups)
                did = .now

            case nil:
                did = .not
            }

        case .enter:
            switch validAt {
            case .group(let g)?:
                let name = groups[g].name
                let isFoldedNow = !plan.sections.flatMap(\.subs).contains { $0.g == g && $0.open }
                setFolded(name, !isFoldedNow)
                did = .fold
            case .page(let p)?:
                let isFoldedNow = !plan.sections.contains { $0.head == .page(p) && $0.open }
                setFolded(p, !isFoldedNow)
                did = .fold
            default:
                did = .not
            }

        case .backspace where !query.isEmpty:
            var q = query
            _ = q.unicodeScalars.popLast()
            setQuery(q)
            refilter(groups, plan)
            did = .now

        case .text(let t) where t == "/":
            startFilter()
            did = .now

        case .text(let t) where singleDigitIndex(t) != nil:
            // 1–9 pick the keyboard's choice's option.
            if let n = singleDigitIndex(t),
               case .knob(let g, let i)? = validAt,
               n < groups[g].knobs[i].labels.count
            {
                let d = groups[g].knobs[i]
                checkpoint()
                set(d, Float(n))
            }
            // Taken even so: the page's own number keys (a decision's options) wait for the panel to let go.
            did = .now

        case .text(let t) where (t == "[" || t == "]") && !plan.tabs.isEmpty:
            let i = plan.tab.flatMap { c in plan.tabs.firstIndex(where: { $0.0 == c }) } ?? 0
            let n = plan.tabs.count
            tab = plan.tabs[euclidMod(i + (t == "[" ? -1 : 1), n)].0
            atNode = nil
            did = .now

        default:
            did = .not
        }

        if did != .not {
            kbd = true
        }
        return did
    }

    /// The keys the panel keeps while the filter field edits (it hears every other key first
    /// and owns ← →, digits, `[` `]`, `/`, Backspace and the ⌘ ⌥ chords): ↑ ↓ move the row so
    /// a result is an arrow away, Tab moves between headers, Return stops filtering, and Esc
    /// stops it too (the matches stay; Esc again clears them, and again closes).
    mutating func filterKey(_ groups: [Group], _ plan: Plan, _ ev: KeyEvent) -> Did {
        if ev.mods.cmd || ev.mods.alt || ev.mods.ctrl {
            return .not
        }
        let did: Did
        switch ev.key {
        case .escape:
            stopFilter()
            if rows(plan).isEmpty {
                setQuery("")
            }
            did = .now
        case .enter:
            stopFilter()
            did = .now
        case .up, .down, .tab:
            did = moveRow(groups, plan, ev)
        default:
            did = .not
        }
        if did != .not {
            kbd = true
        }
        return did
    }

    /// ↑ ↓ walk the rows; Tab jumps between headers.
    private mutating func moveRow(_ groups: [Group], _ plan: Plan, _ ev: KeyEvent) -> Did {
        let rowNodes = rows(plan)
        let here = atNode.flatMap { n in rowNodes.firstIndex(of: n) }
        switch ev.key {
        case .up where !rowNodes.isEmpty, .down where !rowNodes.isEmpty:
            let down = (ev.key == .down)
            let i: Int
            if let cur = here {
                i = down ? min(cur + 1, rowNodes.count - 1) : max(cur - 1, 0)
            } else {
                i = down ? 0 : (rowNodes.count - 1)
            }
            setAt(rowNodes[i], groups)
            return .now

        case .tab:
            let heads = (0..<rowNodes.count).filter { idx in
                if case .knob = rowNodes[idx] { return false }
                return true
            }
            let atIdx = here ?? 0
            let next: Int?
            if ev.mods.shift {
                next = heads.reversed().first(where: { $0 < atIdx }) ?? heads.last
            } else {
                next = heads.first(where: { $0 > atIdx }) ?? heads.first
            }
            if let next {
                setAt(rowNodes[next], groups)
            }
            return .now

        default:
            return .not
        }
    }

    /// After the filter changes, the keyboard stands on the first knob it shows.
    mutating func refilter(_ groups: [Group], _ before: Plan) {
        let now = plan(self, groups, before.seen)
        let first = rows(now).first { n in
            if case .knob = n { return true }
            return false
        }
        setAt(first, groups)
    }
}
