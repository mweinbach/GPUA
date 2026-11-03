// Ported from: crates/rune/src/runtime/input/help.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Hover help tooltip resolution (`El.help`, `helpCutFlag`) and warmup delay timer.

public struct ActiveHelpTooltip: Sendable, Equatable {
    public var text: String
    public var targetRect: [Float]
    public var pointer: (Float, Float)

    public init(text: String, targetRect: [Float], pointer: (Float, Float)) {
        self.text = text
        self.targetRect = targetRect
        self.pointer = pointer
    }

    public static func == (lhs: ActiveHelpTooltip, rhs: ActiveHelpTooltip) -> Bool {
        lhs.text == rhs.text && lhs.targetRect == rhs.targetRect
            && lhs.pointer.0 == rhs.pointer.0 && lhs.pointer.1 == rhs.pointer.1
    }
}

let HELP_HOVER_DELAY: Double = 0.5

extension Runtime {
    func updateHelpHover(_ chain: [Int], x: Float, y: Float) {
        var resolvedIdx: Int? = nil
        var resolvedText: String? = nil
        for idx in chain {
            if nodes[idx].helpCut {
                break
            }
            if let txt = nodes[idx].helpText, !txt.isEmpty {
                resolvedIdx = idx
                resolvedText = txt
                break
            }
        }

        guard let idx = resolvedIdx, let text = resolvedText else {
            clearHelpHover()
            return
        }

        let path = nodes[idx].path
        helpHoverPointer = (x, y)
        if helpHoverPath != path {
            let wasWarm = (helpShownAt != nil)
            helpHoverPath = path
            helpHoverText = text
            helpHoverRect = nodes[idx].presentedRect
            if wasWarm {
                helpShownAt = clock
            } else {
                helpHoverStart = clock
                timerWakes.schedule(now: clock, after: HELP_HOVER_DELAY)
            }
        } else {
            helpHoverText = text
            helpHoverRect = nodes[idx].presentedRect
        }
    }

    func clearHelpHover() {
        helpHoverPath = nil
        helpHoverText = nil
        helpHoverStart = nil
        helpShownAt = nil
    }

    func checkHelpTooltipDue() {
        guard let start = helpHoverStart, helpShownAt == nil, helpHoverPath != nil else { return }
        if clock - start >= HELP_HOVER_DELAY - 1e-6 {
            helpShownAt = clock
        }
    }

    public func activeHelp() -> ActiveHelpTooltip? {
        checkHelpTooltipDue()
        guard helpShownAt != nil,
              let txt = helpHoverText,
              let p = helpHoverPointer
        else { return nil }
        return ActiveHelpTooltip(text: txt, targetRect: helpHoverRect, pointer: p)
    }
}
