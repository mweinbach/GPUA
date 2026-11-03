// Ported from: crates/rune/src/el/handlers.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Handlers: queued, run between frames with `inout S`.

extension El {
    public func onPress<S>(_ f: @escaping (inout S) -> Void) -> El {
        onPressTx { (s: inout S, _: inout Tx) in
            f(&s)
        }
    }

    /// Spine compatibility overload accepting `(inout S, inout Tx) -> Void` directly.
    public func onPress<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        onPressTx(f)
    }

    public func onPressTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onPress = { states, tx in
            states.withDowncast { (state: inout S) in
                f(&state, &tx)
            }
        }
        if copy.roleName == "group" {
            copy.roleName = "button"
        }
        return copy
    }

    /// Runs on the second of two presses on this element, as a double-click does: the second
    /// press lands within the system double-click interval of the first and within 4 pt of it,
    /// and releases inside. `onPress` still runs for each press, the first one right away.
    public func onDoublePress<S>(_ f: @escaping (inout S) -> Void) -> El {
        onDoublePressTx { (s: inout S, _: inout Tx) in
            f(&s)
        }
    }

    public func onDoublePressTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onDoublePress = { states, tx in
            states.withDowncast { (state: inout S) in
                f(&state, &tx)
            }
        }
        return copy
    }

    /// Receives `Down`, `Move`, then `Up`. `Up` also ends a cancelled gesture: always check
    /// ``Drag/cancelled()`` before committing a drop or notifying an application callback.
    public func onDrag<S>(_ f: @escaping (inout S, inout Drag, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onDrag = { states, drag, tx in
            states.withDowncast { (state: inout S) in
                f(&state, &drag, &tx)
            }
        }
        return copy
    }

    /// Drag this element out of the window into another app, as a file, image or text. Once
    /// the pointer travels the drag threshold from the press, `f` reads the state and returns
    /// what to carry (`nil`: no drag this time, the press stays a press).
    public func dragOut<S>(_ f: @escaping (S) -> DragItem?) -> El {
        var copy = self
        copy.handlers.value.dragOut = { statesRef in
            guard let state = statesRef.cast(S.self) else {
                preconditionFailure("handler registered for a different state type than the app's")
            }
            return f(state)
        }
        return copy
    }

    /// How far (points, straight-line) the pointer travels from the press before this
    /// element's ``dragOut(_:)`` starts.
    public func dragThreshold(_ points: Float) -> El {
        var copy = self
        copy.handlers.value.dragThreshold = max(points, 0.0)
        return copy
    }

    /// Called when a ``dragOut(_:)`` drag starts, after the drag image was taken, so the app
    /// can style the source while it's dragged.
    public func onDragStart<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onDragStart = { states, tx in
            states.withDowncast { (state: inout S) in
                f(&state, &tx)
            }
        }
        return copy
    }

    /// Called once when a ``dragOut(_:)`` drag ends, with what the drop did.
    public func onDragEnd<S>(_ f: @escaping (inout S, DragOutcome, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onDragEnd = { states, outcome, tx in
            states.withDowncast { (state: inout S) in
                f(&state, outcome, &tx)
            }
        }
        return copy
    }
}
