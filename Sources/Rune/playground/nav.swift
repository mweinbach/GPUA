// Ported from: crates/rune/src/playground/nav.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The open playground's keys.

extension PlaygroundLive {
    /// What `ev` does in the open playground, with the keyboard in `region`. The stage's keys
    /// are its own, so it only gets here from the list or the side column.
    func nav(_ ev: KeyEvent, _ region: PlaygroundRegion) -> PlaygroundNav {
        let m = ev.mods
        // Control on macOS, the Windows key elsewhere: never the playground's.
        #if os(macOS)
        let other = m.alt || m.ctrl
        #else
        let other = m.alt || m.logo
        #endif
        if !open || other || region == .stage {
            return .pass
        }
        let letter: Character?
        if case .text(let t) = ev.key, !m.cmd, t.count == 1, let ch = t.first {
            letter = Character(String(ch).lowercased())
        } else {
            letter = nil
        }
        let inSide = region == .side
        if inSide {
            switch ev.key {
            case .tab, .escape, .left:
                return .outOfSide
            case .up where !m.cmd:
                return .sideStep(-1)
            case .down where !m.cmd:
                return .sideStep(1)
            default:
                break
            }
            // Digits pick a variant only here, where the keyboard is on the story's controls.
            if let c = letter, let req = variantKey(c) {
                return .request(req)
            }
        }
        // In the side column, Space presses the focused control.
        if let c = letter, !(inSide && c == " "), let req = triggerRequest(c) {
            return .request(req)
        }
        if inSide {
            return .pass
        }
        if letter == "/" {
            return .filter
        }
        let result = listNav(ev, letter)
        if result == .pass && !m.cmd {
            switch ev.key {
            case .up, .down, .left, .right, .enter:
                return .stay
            default:
                break
            }
        }
        return result
    }

    /// Keys in the story list: along it, into and out of groups, and on to the other columns.
    private func listNav(_ ev: KeyEvent, _ letter: Character?) -> PlaygroundNav {
        let m = ev.mods
        if ev.key == .tab {
            return m.shift ? .intoStage : .intoSide
        }
        let rowList = rows()
        func isStory(_ r: PlaygroundRow) -> Bool {
            if case .story = r { return true }
            return false
        }
        guard let lastStory = rowList.last(where: isStory) else {
            return .pass
        }
        let at = rowList.firstIndex { r in
            switch (r, header) {
            case (.header(let g, _, _), let h?):
                return g == h
            case (.story(let i, _), nil):
                return i == selected
            default:
                return false
            }
        }
        let n = rowList.count
        let firstStoryIdx = rowList.firstIndex(where: isStory) ?? 0

        let to: PlaygroundRow
        if ev.key == .up && !m.cmd && !query().isEmpty && (at == nil || at! <= firstStoryIdx) {
            // Filtering, ↑ from the first match goes back up to the field.
            return .filter
        } else if ev.key == .up && m.cmd {
            to = rowList.first(where: isStory) ?? lastStory
        } else if ev.key == .down && m.cmd {
            to = lastStory
        } else if m.cmd {
            return .pass
        } else if ev.key == .up {
            to = rowList[at.map { ($0 + n - 1) % n } ?? 0]
        } else if ev.key == .down {
            to = rowList[at.map { ($0 + 1) % n } ?? 0]
        } else if let c = letter, (c == "j" || c == "k") {
            let step = (c == "j") ? 1 : (n - 1)
            let from = at ?? 0
            var found: PlaygroundRow? = nil
            for k in 1...n {
                let candidate = rowList[(from + k * step) % n]
                if isStory(candidate) {
                    found = candidate
                    break
                }
            }
            to = found ?? lastStory
        } else if ev.key == .left, let g = header, !isFolded(g) && query().isEmpty {
            return .request(.fold(g, true))
        } else if ev.key == .left, let g = header {
            guard let up = Self.parent(g) else { return .pass }
            return .request(.header(up))
        } else if ev.key == .left, header == nil, selected < count() {
            return .request(.header(group(selected)))
        } else if ev.key == .right, !m.shift, let g = header, isFolded(g) {
            return .request(.fold(g, false))
        } else if ev.key == .right, !m.shift, header != nil {
            guard let a = at, a + 1 < rowList.count else { return .pass }
            let next = rowList[a + 1]
            if case .header(_, _, let d) = next, d == 0 {
                return .pass
            }
            to = next
        } else if ev.key == .enter, let g = header {
            return .request(.fold(g, nil))
        } else if ev.key == .right, !m.shift, header == nil {
            return .intoSide
        } else {
            return .pass
        }

        switch to {
        case .header(let g, _, _):
            return .request(.header(g))
        case .story(let i, _):
            return .request(.select(i))
        }
    }

    /// Whether the open story's side controls take keys: ``Story/sideKeys(_:_:)``, or
    /// ``Playground/sideKeys(_:_:_:)`` for a scene.
    func sideKeys() -> Bool {
        if scene != nil {
            return sides.contains { entry in
                guard entry.0 == selected else { return false }
                if case .keys = entry.1 { return true }
                return false
            }
        }
        if let (ownStory, _) = own() {
            return ownStory.sideKeys()
        }
        return false
    }

    /// Keys while the keyboard is on the open story's side controls that take keys: true when
    /// the story's hook took `ev`, or it's ←, which stays rather than leaving.
    func sideKey(_ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        guard open else { return false }
        let took: Bool
        if let scene {
            var handler: ((inout S, KeyEvent, inout Tx) -> Bool)? = nil
            for (s, sideItem) in sides where s == selected {
                if case .keys(_, let k) = sideItem {
                    handler = k
                    break
                }
            }
            if let handler {
                took = handler(&scene.state, ev, &tx)
            } else {
                took = false
            }
        } else {
            let pageIdx = selected - scenes.count
            if pageIdx >= 0 && pageIdx < pages.count,
               case .own(let ownStory) = pages[pageIdx].kind,
               let stageBox = owned[pageIdx]
            {
                took = ownStory.sideKey(stageBox, ev, &tx)
            } else {
                took = false
            }
        }
        return took || ev.key == .left
    }

    /// Notes whether the keyboard is on the open story's side controls, which their view
    /// shows; true when that changed.
    func setSideActive(_ active: Bool) -> Bool {
        let prev = sideActive
        sideActive = active
        return prev != active
    }

    /// What the open story's trigger on `c` asks for, as its letter does: R replays.
    func triggerRequest(_ c: Character) -> PlaygroundRequest? {
        guard triggers().contains(where: { $0.0 == c }) else { return nil }
        return c == "r" ? .replay : .trigger(c)
    }
}
