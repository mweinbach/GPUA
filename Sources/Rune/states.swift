// Ported from: crates/rune/src/states.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What an element's handler is handed. Handlers are stored type-erased and take the state of
//! the type they were built for: the app's, or, while the playground shows a stage, the stage's
//! beside the playground's own controls.

// PORT NOTE: Swift value-type state (`struct AppState`) cannot be mutated through a type-erased
// borrowed reference `&mut dyn Any` without copying or temporary boxing. `States` wraps `app` and
// optional `extra` inside a short-lived box during handler dispatch and writes mutated values back
// into `Runtime<S>.state` cleanly with zero unsafe pointers.
public final class States {
    var app: Any
    var extra: Any?

    init(_ app: Any, extra: Any? = nil) {
        self.app = app
        self.extra = extra
    }

    static func one(_ app: Any) -> States {
        States(app, extra: nil)
    }

    static func two(_ app: Any, _ extra: Any) -> States {
        States(app, extra: extra)
    }

    /// Runs `body` if either `app` or `extra` matches `S`, writing any mutation back.
    func withMutable<S, R>(_ body: (inout S) -> R) -> R? {
        if var typed = app as? S {
            let result = body(&typed)
            app = typed
            return result
        }
        if let ex = extra, var typed = ex as? S {
            let result = body(&typed)
            extra = typed
            return result
        }
        return nil
    }

    /// Runs `body` expecting `S` to match `app` or `extra` (mirroring `states::downcast`).
    func withDowncast<S, R>(_ body: (inout S) -> R) -> R {
        guard let result = withMutable(body) else {
            preconditionFailure("handler registered for a different state type (\(S.self)) than the app's (\(type(of: app)))")
        }
        return result
    }
}

/// Read-only counterpart to ``States`` (`StatesRef` in upstream).
public struct StatesRef {
    let app: Any
    let extra: Any?

    init(_ app: Any, extra: Any? = nil) {
        self.app = app
        self.extra = extra
    }

    static func one(_ app: Any) -> StatesRef {
        StatesRef(app, extra: nil)
    }

    static func two(_ app: Any, _ extra: Any) -> StatesRef {
        StatesRef(app, extra: extra)
    }

    func cast<S>(_ type: S.Type = S.self) -> S? {
        if let typed = app as? S {
            return typed
        }
        return extra as? S
    }
}

/// Scoped mutable lens into a ``TextEdit`` inside app state `S` (Swift port of `edit_access`).
// PORT NOTE: Supports both `WritableKeyPath<S, TextEdit>` and scoped `(inout S, (inout TextEdit) -> Void) -> Void`
// closures so `struct` and `class` app states both mutate `TextEdit` safely without lifetime-escaped references.
public struct EditAccess<S> {
    let mutate: (inout S, (inout TextEdit) -> Void) -> Void

    public init(_ keyPath: WritableKeyPath<S, TextEdit>) {
        self.mutate = { state, body in
            body(&state[keyPath: keyPath])
        }
    }

    public init(_ closure: @escaping (inout S, (inout TextEdit) -> Void) -> Void) {
        self.mutate = closure
    }

    func erase() -> (States, (inout TextEdit) -> Void) -> Bool {
        let mutate = self.mutate
        return { states, body in
            states.withMutable { (s: inout S) in
                mutate(&s, body)
            } != nil
        }
    }
}

public func editAccess<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> EditAccess<S> {
    EditAccess(keyPath)
}

public func editAccess<S>(_ closure: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> EditAccess<S> {
    EditAccess(closure)
}
