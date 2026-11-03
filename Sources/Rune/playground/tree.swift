// Ported from: crates/rune/src/playground/tree.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The story list as a tree: a story's path names its groups, one per `/`, so
//! `"Sidebar/Filter buttons/Compact"` lists "Compact" in "Filter buttons", inside "Sidebar".
//! A group is known by its path prefix (`"Sidebar/Filter buttons"`), which folds keep, and
//! every level folds.

extension Playground {
    /// Lists these top-level groups first, in this order, then the rest in the order they first
    /// appear. Scenes and stories are alike here: `["Prototypes", "Scenes"]` lists the
    /// "Prototypes" stories above the scenes. Inside a group, stories keep the order they're
    /// declared in. A name that isn't a group is passed over (and logged in debug builds).
    public func groupOrder(_ groups: [String]) -> Playground<S> {
        var copy = self
        copy.groupOrderList = groups
        return copy
    }
}

/// A row of the story list. A header carries its first story, which keys it, and its depth;
/// a story its depth, the number of groups it's in.
enum PlaygroundRow: Equatable {
    case header(String, Int, Int)
    case story(Int, Int)

    /// A header's element key: by its first story, with its depth below the top.
    static func headerKey(_ first: Int, _ depth: Int) -> String {
        if depth == 0 {
            return "playground-group-\(first)"
        }
        return "playground-group-\(first)-\(depth)"
    }
}

extension PlaygroundLive {
    /// Story `i`'s groups, outermost first, each by its path prefix: `"Sidebar"`, then
    /// `"Sidebar/Filter buttons"`.
    func groupsOf(_ i: Int) -> [String] {
        let g = group(i)
        var out: [String] = []
        var idx = g.startIndex
        while idx < g.endIndex {
            if g[idx] == "/" {
                out.append(String(g[..<idx]))
            }
            idx = g.index(after: idx)
        }
        out.append(g)
        return out
    }

    /// Stories in list order: each group gathered where its first story is, at every level, and
    /// stories and groups inside one kept in the order they first appear, except that the
    /// top-level groups `first` names come first, in its order (``Playground/groupOrder(_:)``).
    func treeOrder(_ listed: [Int], _ first: [String]) -> [Int] {
        #if DEBUG
        for name in first where !listed.contains(where: { groupsOf($0).first == name }) {
            toolingStderr("rune: Playground::group_order names \(name.debugDescription), which isn't a group in the list\n")
        }
        #endif
        var out: [Int] = []
        out.reserveCapacity(listed.count)
        gather(listed, 0, first, &out)
        return out
    }

    private func gather(_ items: [Int], _ depth: Int, _ first: [String], _ out: inout [Int]) {
        var runs: [(String?, [Int])] = []
        for i in items {
            let gs = groupsOf(i)
            if depth < gs.count {
                let g = gs[depth]
                if let pos = runs.firstIndex(where: { $0.0 == g }) {
                    runs[pos].1.append(i)
                } else {
                    runs.append((g, [i]))
                }
            } else {
                runs.append((nil, [i]))
            }
        }
        if depth == 0 {
            // Stable sort by `first` index (`Int.max` when absent).
            let indexed = runs.enumerated().map { offset, entry -> (Int, Int, (String?, [Int])) in
                let rank = entry.0.flatMap { g in first.firstIndex(of: g) } ?? Int.max
                return (rank, offset, entry)
            }
            runs = indexed.sorted { a, b in
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1 < b.1
            }.map(\.2)
        }
        for (g, inside) in runs {
            if g != nil {
                gather(inside, depth + 1, first, &out)
            } else {
                out.append(contentsOf: inside)
            }
        }
    }

    /// What the filter field holds, trimmed.
    func query() -> String {
        trimAsciiWhitespace(controls.filter.text)
    }

    /// Empties the filter field; true when it held something.
    func clearFilter() -> Bool {
        if controls.filter.text.isEmpty { return false }
        controls.filter.replaceText("")
        return true
    }

    /// The first story the filter keeps, unless the selected one is among them.
    func firstMatch() -> Int? {
        if header == nil && selected < count() && matches(selected) {
            return nil
        }
        return order.first(where: { matches($0) })
    }

    /// The first story the list shows, which ↓ from the filter goes to.
    func firstShown() -> Int? {
        for r in rows() {
            if case .story(let i, _) = r {
                return i
            }
        }
        return nil
    }

    /// Whether story `i` matches the filter: each word somewhere in its path, ignoring case.
    func matches(_ i: Int) -> Bool {
        let q = query()
        if q.isEmpty { return true }
        let p = path(i).lowercased()
        let words = q.lowercased().split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { p.contains($0) }
    }

    /// Whether `group` is folded, as the list shows it: a filter shows every match.
    func isFolded(_ group: String) -> Bool {
        query().isEmpty && folded.contains(group)
    }

    /// Whether story `i` is in `group`, directly or in a group inside it.
    func isIn(_ i: Int, _ groupName: String) -> Bool {
        let own = group(i)
        if own == groupName { return true }
        guard own.hasPrefix(groupName) else { return false }
        let rest = own.dropFirst(groupName.count)
        return rest.first == "/"
    }

    /// The stories in `group` that the filter keeps, which its header counts.
    func countIn(_ groupName: String) -> Int {
        order.filter { isIn($0, groupName) && matches($0) }.count
    }

    /// The first story in `group`, filter or not, which keys its header.
    private func firstIn(_ groupName: String) -> Int {
        order.first(where: { isIn($0, groupName) }) ?? 0
    }

    /// The group around `group`, if it's not at the top.
    static func parent(_ groupName: String) -> String? {
        guard let range = groupName.range(of: "/", options: .backwards) else {
            return nil
        }
        return String(groupName[..<range.lowerBound])
    }

    /// The list's rows: each group's header, then what's in it unless it, or a group around it,
    /// is folded. A filter keeps its matches and the headers above them.
    func rows() -> [PlaygroundRow] {
        var out: [PlaygroundRow] = []
        var openGroups: [String] = []
        for i in order where matches(i) {
            let gs = groupsOf(i)
            var same = 0
            while same < openGroups.count && same < gs.count && openGroups[same] == gs[same] {
                same += 1
            }
            if openGroups.count > same {
                openGroups.removeSubrange(same..<openGroups.count)
            }
            for depth in same..<gs.count {
                if !gs[..<depth].contains(where: { isFolded($0) }) {
                    out.append(.header(gs[depth], firstIn(gs[depth]), depth))
                }
                openGroups.append(gs[depth])
            }
            if !gs.contains(where: { isFolded($0) }) {
                out.append(.story(i, gs.count))
            }
        }
        return out
    }

    /// The outermost folded group that hides story `i`'s row, or `group`'s header, if one does.
    private func hiddenBy(_ groups: [String]) -> String? {
        groups.first(where: { isFolded($0) })
    }

    /// After folds change: a selection whose row a fold hid moves to the header that hides it.
    func settle() {
        guard open else { return }
        let hider: String?
        if let h = header {
            var around: [String] = []
            var cur = Self.parent(h)
            while let p = cur {
                around.append(p)
                cur = Self.parent(p)
            }
            around.reverse()
            hider = hiddenBy(around)
        } else if selected < count() {
            hider = hiddenBy(groupsOf(selected))
        } else {
            hider = nil
        }
        if let g = hider {
            header = g
        }
    }

    /// Every group in the list, outermost first, as folds name them.
    func allGroups() -> [String] {
        var out: [String] = []
        for i in order {
            for g in groupsOf(i) {
                if !out.contains(g) {
                    out.append(g)
                }
            }
        }
        return out
    }
}
