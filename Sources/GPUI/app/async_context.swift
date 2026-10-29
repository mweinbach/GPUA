// Ported from: crates/gpui/src/app/async_context.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

/// An async-friendly version of `App` that can be held across `await` points in asynchronous code.
public struct AsyncApp: @unchecked Sendable {
    public weak var app: App?
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor

    public init(
        app: App?,
        backgroundExecutor: BackgroundExecutor,
        foregroundExecutor: ForegroundExecutor
    ) {
        self.app = app
        self.backgroundExecutor = backgroundExecutor
        self.foregroundExecutor = foregroundExecutor
    }

    /// Invokes the given function on the main thread in the context of the app.
    @MainActor
    public func update<R>(_ f: (App) -> R) throws -> R {
        guard let app else {
            throw GPUIError.message("app was released before async operation completed")
        }
        return app.update(f)
    }

    /// Determines whether global state of the specified type has been assigned.
    @MainActor
    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        guard let app else { return false }
        return app.hasGlobal(type)
    }

    /// Reads global state of the specified type.
    @MainActor
    public func readGlobal<G: Global, R>(_ read: (G, App) -> R) -> R {
        guard let app else {
            fatalError("app was released before async operation completed")
        }
        return app.readGlobal(read)
    }

    /// Reads global state of the specified type if present.
    @MainActor
    public func tryReadGlobal<G: Global, R>(_ read: (G, App) -> R) -> R? {
        guard let app, let g: G = app.tryGlobal() else { return nil }
        return read(g, app)
    }

    /// Updates the global state of the specified type.
    @MainActor
    public func updateGlobal<G: Global, R>(_ update: (inout G, App) -> R) throws -> R {
        guard let app else {
            throw GPUIError.message("app was released before async operation completed")
        }
        var g: G = app.leaseGlobal()
        let result = update(&g, app)
        app.endGlobalLease(g)
        return result
    }

    /// Arranges for the given callback to be invoked whenever the entity emits an event.
    @MainActor
    public func subscribe<T: EventEmitter<Event>, Event>(
        _ entity: Entity<T>,
        _ onEvent: @escaping (Entity<T>, Event, App) -> Void
    ) -> Subscription {
        guard let app else {
            return Subscription {}
        }
        return app.subscribe(entity) { e, evt, app in
            onEvent(e, evt, app)
            return true
        }
    }
}

/// A cloneable handle to an async application context combined with a window.
public struct AsyncWindowContext: @unchecked Sendable {
    public var app: AsyncApp

    public init(app: AsyncApp) {
        self.app = app
    }
}
