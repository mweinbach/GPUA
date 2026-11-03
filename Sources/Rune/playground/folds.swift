// Ported from: crates/rune/src/playground/folds.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Which groups the list folds, at any level: kept while the app runs, and through
//! `Playground.folds`' hooks from one run to the next.

struct PlaygroundFolds {
    var load: (() -> [String])? = nil
    var save: (([String]) -> Void)? = nil
    var start: Bool = false
}

extension Playground {
    /// Every group starts folded, at every level, but the ones around the open story.
    public func startFolded(_ on: Bool) -> Playground<S> {
        var copy = self
        copy.foldsConfig.start = on
        return copy
    }

    /// Keeps the folded groups from one run to the next.
    public func folds(
        _ load: @escaping () -> [String],
        _ save: @escaping ([String]) -> Void
    ) -> Playground<S> {
        var copy = self
        copy.foldsConfig = PlaygroundFolds(load: load, save: save, start: copy.foldsConfig.start)
        return copy
    }
}

extension PlaygroundLive {
    /// Folds the groups `Playground.folds`' `load` names, the first time it's called.
    func loadFolds() {
        guard let load = folds.load else { return }
        folds.load = nil
        let names = load()
        let start = folds.start
        folded = allGroups().filter { g in
            names.contains(g) != start
        }
    }

    /// Changes which groups are folded, and saves them if that changed them.
    func refold(_ change: (inout [String]) -> Void) {
        let before = folded
        change(&folded)
        if folded == before { return }
        guard let save = folds.save else { return }
        let names: [String]
        if folds.start {
            names = allGroups().filter { !folded.contains($0) }
        } else {
            names = folded
        }
        save(names)
    }
}
