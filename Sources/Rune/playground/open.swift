// Ported from: crates/rune/src/playground/open.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Finding a story by its path, name or slug, and opening the playground on it: one lookup for
//! `--playground NAME --variant V`, ``Tx/openPlaygroundAt(_:_:)`` and ``Runtime/openPlayground(_:_:)``.

/// A story's path as a link takes it: lowercased, with each run of characters that aren't
/// letters or digits (the `/` between group and name, spaces, punctuation) made one `-`, and
/// none at either end. `"Timeline/Send"` is `"timeline-send"` and `"Lists/Many devices"` is
/// `"lists-many-devices"`. Letters outside ASCII are kept, lowercased.
public func playgroundSlug(_ path: String) -> String {
    var out = ""
    out.reserveCapacity(path.count)
    for c in path {
        if c.isLetter || c.isNumber {
            out.append(contentsOf: String(c).lowercased())
        } else if !out.isEmpty && !out.hasSuffix("-") {
            out.append("-")
        }
    }
    if out.hasSuffix("-") {
        out.removeLast()
    }
    return out
}

extension PlaygroundLive {
    /// The listed story called `name`: its path or just its name, matching case only if need
    /// be, or its path's ``playgroundSlug(_:)``. Where two match, the first in the list.
    func find(_ name: String) -> Int? {
        findIn(name, order)
    }

    /// ``find(_:)`` among `ids`, in order.
    func findIn(_ target: String, _ ids: [Int]) -> Int? {
        if let exact = ids.first(where: { path($0) == target || name($0) == target }) {
            return exact
        }
        if let loose = ids.first(where: {
            asciiCaseInsensitiveEqual(path($0), target) || asciiCaseInsensitiveEqual(name($0), target)
        }) {
            return loose
        }
        return ids.first(where: { playgroundSlug(path($0)) == target })
    }

    /// Checks that story `name` (else the one selected) is there, and picks `variant` of it.
    func openAt(_ storyName: String?, _ variantName: String?) -> Result<Void, ToolingCliError> {
        if let storyName, find(storyName) == nil {
            let names = order.map { path($0) }.joined(separator: ", ")
            return .failure(ToolingCliError("no story \(storyName.debugDescription) in the playground; it has: \(names)"))
        }
        if let variantName {
            return pick(storyName, variantName)
        }
        return .success(())
    }

    /// ``Tx/openPlaygroundAt(_:_:)``'s story, once checked. An app can't stop over a bad link, so
    /// what's wrong is logged: an unknown story opens the list where it was, and a story's
    /// unknown variant opens the story on the variant it was on.
    func resolve(_ storyName: String, _ variantName: String?) -> String? {
        if case .failure(let err) = openAt(storyName, variantName) {
            toolingStderr("rune: Tx::open_playground_at: \(err.message)\n")
            return find(storyName) != nil ? storyName : nil
        }
        return storyName
    }

    /// Opens the playground, on story `name` if it's there; open already, it moves there.
    func openStory(_ storyName: String?, _ real: inout S) {
        let at = storyName.flatMap { find($0) }
        if !open || at != nil {
            open = true
            if let i = at ?? (folds.start ? selected : nil) {
                reveal(i)
            }
            select(at ?? selected, &real)
        }
    }
}

private func asciiCaseInsensitiveEqual(_ a: String, _ b: String) -> Bool {
    guard a.utf8.count == b.utf8.count else { return false }
    for (ba, bb) in zip(a.utf8, b.utf8) {
        let la = (ba >= 0x41 && ba <= 0x5A) ? (ba + 32) : ba
        let lb = (bb >= 0x41 && bb <= 0x5A) ? (bb + 32) : bb
        if la != lb { return false }
    }
    return true
}

extension Tx {
    /// Shows ``App/playground(_:)`` on `story` (its `"Group/Name"` path, its name, or its path's
    /// ``playground/slug(_:)``), on `variant` (by number from 1, or by name) if given, as
    /// `--playground NAME --variant V` does.
    public mutating func openPlaygroundAt(_ story: String, _ variant: String? = nil) {
        pgPush(.openAt(story, variant))
    }

    /// Makes the open story's stage again and runs its `'r'` trigger, as R does.
    public mutating func replayPlayground() {
        pgPush(.replay)
    }

    /// Runs the open story's trigger on `key`, as its letter or its side-column button does;
    /// `'r'` is ``Tx/replayPlayground()``. A key the story has no trigger on does nothing.
    public mutating func playgroundTrigger(_ key: Character) {
        let lower = Character(String(key).lowercased())
        pgPush(lower == "r" ? .replay : .trigger(lower))
    }
}
