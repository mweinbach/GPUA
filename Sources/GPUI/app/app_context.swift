// Ported from: crates/gpui/src/app/context.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// The context protocol, allowing different contexts in GPUI to be used
/// interchangeably for fundamental entity and global operations.
public protocol AppContext: AnyObject {
    @MainActor
    func new<T>(_ buildEntity: (inout Context<T>) -> T) -> Entity<T>

    @MainActor
    func reserveEntity<T>(_ type: T.Type) -> Reservation<T>

    @MainActor
    func insertEntity<T>(
        _ reservation: Reservation<T>,
        _ buildEntity: (inout Context<T>) -> T
    ) -> Entity<T>

    @MainActor
    func updateEntity<T, R>(
        _ handle: Entity<T>,
        _ update: (inout T, inout Context<T>) -> R
    ) -> R

    @MainActor
    func asMut<T>(_ handle: Entity<T>) -> GpuiBorrow<T>

    @MainActor
    func readEntity<T, R>(
        _ handle: Entity<T>,
        _ read: (T, App) -> R
    ) -> R

    @MainActor
    func readGlobal<G: Global, R>(_ callback: (G, App) -> R) -> R
}

extension AppContext {
    @MainActor
    public func reserveEntity<T>() -> Reservation<T> {
        reserveEntity(T.self)
    }
}

/// A helper protocol for contexts that allow setting and updating globals.
public protocol BorrowAppContext {
    @MainActor
    func setGlobal<G: Global>(_ global: G)

    @MainActor
    func updateGlobal<G: Global, R>(_ update: (inout G, App) -> R) -> R

    @MainActor
    func updateDefaultGlobal<G: Global & Default, R>(_ update: (inout G, App) -> R) -> R
}

/// A protocol for tying together an entity and the events it can emit.
public protocol EventEmitter<Event> {
    associatedtype Event: Sendable
}

/// A protocol for visual contexts that have an associated window.
public protocol VisualContext: AppContext {
    // Window-related operations will be expanded in Batch 3.2
}

/// A token returned by `reserveEntity` to later be passed to `insertEntity`.
public struct Reservation<T>: Sendable {
    public let slot: Slot<T>

    public init(slot: Slot<T>) {
        self.slot = slot
    }

    public var entityId: EntityId {
        slot.entityId
    }
}

/// An entity-specialized context passed to entity update callbacks.
@MainActor
public struct Context<T> {
    public var app: App
    public let entityState: WeakEntity<T>

    public init(app: App, entityState: WeakEntity<T>) {
        self.app = app
        self.entityState = entityState
    }

    /// The entity id of the entity backing this context.
    public var entityId: EntityId {
        entityState.entityId
    }

    /// Returns a strong handle to the entity belonging to this context.
    public func entity() -> Entity<T> {
        guard let strong = weakEntity().upgrade() else {
            fatalError("The entity must be alive if we have an entity context")
        }
        return strong
    }

    /// Returns a weak handle to the entity belonging to this context.
    public func weakEntity() -> WeakEntity<T> {
        entityState
    }

    /// Tells GPUI that this entity has changed and observers of it should be notified.
    public func notify() {
        app.notify(entityState.entityId)
    }

    /// Arranges for the given function to be called whenever `notify` is called on the given entity.
    public func observe<W>(
        _ entity: Entity<W>,
        _ onNotify: @escaping (inout T, Entity<W>, inout Context<T>) -> Void
    ) -> Subscription {
        let this = weakEntity()
        return app.observe(entity) { e, app in
            guard let strongThis = this.upgrade() else { return false }
            strongThis.update(app) { state, cx in
                onNotify(&state, e, &cx)
            }
            return true
        }
    }

    /// Observe changes to this entity itself.
    public func observeSelf(
        _ onEvent: @escaping (inout T, inout Context<T>) -> Void
    ) -> Subscription {
        let this = entity()
        return app.observe(this) { e, app in
            e.update(app) { state, cx in
                onEvent(&state, &cx)
            }
            return true
        }
    }

    /// Subscribe to an event emitted by another entity.
    public func subscribe<T2: EventEmitter<Evt>, Evt>(
        _ entity: Entity<T2>,
        _ onEvent: @escaping (inout T, Entity<T2>, Evt, inout Context<T>) -> Void
    ) -> Subscription {
        let this = weakEntity()
        return app.subscribe(entity) { (e: Entity<T2>, event: Evt, app: App) -> Bool in
            guard let strongThis = this.upgrade() else { return false }
            strongThis.update(app) { state, cx in
                onEvent(&state, e, event, &cx)
            }
            return true
        }
    }

    /// Subscribe to an event emitted by this entity itself.
    public func subscribeSelf<Evt>(
        _ onEvent: @escaping (inout T, Evt, inout Context<T>) -> Void
    ) -> Subscription where T: EventEmitter<Evt> {
        let this = entity()
        return app.subscribe(this) { (e: Entity<T>, event: Evt, app: App) -> Bool in
            e.update(app) { state, cx in
                onEvent(&state, event, &cx)
            }
            return true
        }
    }

    /// Register a callback to be invoked when GPUI releases this entity.
    public func onRelease(_ onRelease: @escaping (inout T, App) -> Void) -> Subscription {
        let (subscription, activate) = app.releaseListeners.insert(
            entityState.entityId,
            { (boxed: inout Any, app: App) in
                if var typed = boxed as? T {
                    onRelease(&typed, app)
                    boxed = typed
                }
            }
        )
        activate()
        return subscription
    }

    /// Register a callback to be run on the release of another entity.
    public func observeRelease<T2>(
        _ entity: Entity<T2>,
        _ onRelease: @escaping (inout T, inout T2, inout Context<T>) -> Void
    ) -> Subscription {
        let entityId = entity.entityId
        let this = weakEntity()
        let (subscription, activate) = app.releaseListeners.insert(
            entityId,
            { [weak app] (boxed: inout Any, appParam: App) in
                guard var target = boxed as? T2 else { return }
                if let strongThis = this.upgrade(), let app = app ?? Optional(appParam) {
                    strongThis.update(app) { thisState, cx in
                        onRelease(&thisState, &target, &cx)
                    }
                }
                boxed = target
            }
        )
        activate()
        return subscription
    }

    /// Register a callback for updates to the given global.
    public func observeGlobal<G: Global>(
        _ type: G.Type = G.self,
        _ f: @escaping (inout T, inout Context<T>) -> Void
    ) -> Subscription {
        let this = weakEntity()
        let (subscription, activate) = app.globalObservers.insert(
            ObjectIdentifier(G.self),
            { [weak app] (appParam: App) -> Bool in
                guard let strongThis = this.upgrade() else { return false }
                guard let app = app ?? Optional(appParam) else { return false }
                strongThis.update(app) { state, cx in
                    f(&state, &cx)
                }
                return true
            }
        )
        app.defer { _ in activate() }
        return subscription
    }

    /// Emit an event of the specified type.
    public func emit<Evt>(_ event: Evt) where T: EventEmitter<Evt> {
        app.emit(emitter: entityState.entityId, eventType: ObjectIdentifier(Evt.self), event: event)
    }

    /// Schedules a callback to be run during the current effect flush.
    public func `defer`(_ callback: @escaping (App) -> Void) {
        app.defer(callback)
    }

    /// Creates an `AsyncApp` that can be held across await points.
    public func toAsync() -> AsyncApp {
        app.toAsync()
    }

    // Forwarding to AppContext
    public func new<U>(_ buildEntity: (inout Context<U>) -> U) -> Entity<U> {
        app.new(buildEntity)
    }

    public func reserveEntity<U>(_ type: U.Type = U.self) -> Reservation<U> {
        app.reserveEntity(type)
    }

    public func insertEntity<U>(
        _ reservation: Reservation<U>,
        _ buildEntity: (inout Context<U>) -> U
    ) -> Entity<U> {
        app.insertEntity(reservation, buildEntity)
    }

    public func updateEntity<U, R>(
        _ handle: Entity<U>,
        _ update: (inout U, inout Context<U>) -> R
    ) -> R {
        app.updateEntity(handle, update)
    }

    public func asMut<E>(_ handle: Entity<E>) -> GpuiBorrow<E> {
        app.asMut(handle)
    }

    public func readEntity<U, R>(
        _ handle: Entity<U>,
        _ read: (U, App) -> R
    ) -> R {
        app.readEntity(handle, read)
    }

    public func global<G: Global>(_ type: G.Type = G.self) -> G {
        app.global(type)
    }

    public func tryGlobal<G: Global>(_ type: G.Type = G.self) -> G? {
        app.tryGlobal(type)
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        app.hasGlobal(type)
    }

    public func setGlobal<G: Global>(_ global: G) {
        app.setGlobal(global)
    }

    public mutating func updateGlobal<G: Global, R>(_ update: (inout G, inout Self) -> R) -> R {
        var g: G = app.leaseGlobal()
        let result = update(&g, &self)
        app.endGlobalLease(g)
        return result
    }

    public func updateGlobal<G: Global, R>(_ update: (inout G, App) -> R) -> R {
        app.updateGlobal(update)
    }

    public mutating func updateDefaultGlobal<G: Global & Default, R>(_ update: (inout G, inout Self) -> R) -> R {
        if !hasGlobal(G.self) {
            setGlobal(G.default())
        }
        return updateGlobal(update)
    }

    public func updateDefaultGlobal<G: Global & Default, R>(_ update: (inout G, App) -> R) -> R {
        app.updateDefaultGlobal(update)
    }

    public func readGlobal<G: Global, R>(_ callback: (G, App) -> R) -> R {
        app.readGlobal(callback)
    }
}

extension Context: BorrowAppContext {}
