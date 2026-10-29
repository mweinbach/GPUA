// Ported from: crates/gpui/src/app.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Scheduler

/// A mutable reference to an entity owned by GPUI with RAII auto-notification on drop.
public final class GpuiBorrow<T>: @unchecked Sendable {
    public var value: T {
        get { lease.value }
        set { lease.value = newValue }
    }
    private var lease: Lease<T>
    private unowned let app: App

    @MainActor
    public init(inner: Entity<T>, app: App) {
        self.app = app
        app.startUpdate()
        self.lease = app.entities.lease(inner)
    }

    deinit {
        let app = self.app
        var lease = self.lease
        MainActor.assumeIsolated {
            app.notify(lease.id)
            app.entities.endLease(&lease)
            app.finishUpdate()
        }
    }
}

/// The core application state container in GPUI.
@MainActor
public final class App: AppContext, BorrowAppContext, @unchecked Sendable {
    public var entities: EntityMap
    public let observers = SubscriberSet<EntityId, (App) -> Bool>()
    public let eventListeners = SubscriberSet<EntityId, (ObjectIdentifier, (Any, App) -> Bool)>()
    public let releaseListeners = SubscriberSet<EntityId, (inout Any, App) -> Void>()
    public let globalObservers = SubscriberSet<ObjectIdentifier, (App) -> Bool>()
    public let newEntityObservers = SubscriberSet<ObjectIdentifier, (AnyEntity, App) -> Void>()

    private var globals: [ObjectIdentifier: Any] = [:]

    enum Effect {
        case notify(EntityId)
        case emit(emitter: EntityId, eventType: ObjectIdentifier, event: Any)
        case notifyGlobalObservers(ObjectIdentifier)
        case deferCallback((App) -> Void)
    }

    private var pendingEffects: [Effect] = []
    private var pendingNotifications: Set<EntityId> = []
    private var pendingGlobalNotifications: Set<ObjectIdentifier> = []
    private var pendingUpdates: Int = 0
    private var flushingEffects: Bool = false

    public let backgroundExecutor: BackgroundExecutor?
    public let foregroundExecutor: ForegroundExecutor?

    nonisolated public init(
        backgroundExecutor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil
    ) {
        self.entities = EntityMap()
        self.backgroundExecutor = backgroundExecutor
        self.foregroundExecutor = foregroundExecutor
    }

    public func startUpdate() {
        pendingUpdates += 1
    }

    public func finishUpdate() {
        if !flushingEffects && pendingUpdates == 1 {
            flushingEffects = true
            flushEffects()
            flushingEffects = false
        }
        pendingUpdates -= 1
    }

    /// Invokes the given function in the context of the app, flushing side effects upon completion.
    @discardableResult
    public func update<R>(_ f: (App) -> R) -> R {
        startUpdate()
        defer { finishUpdate() }
        return f(self)
    }

    public func flushEffects() {
        while true {
            releaseDroppedEntities()
            if !pendingEffects.isEmpty {
                let effect = pendingEffects.removeFirst()
                switch effect {
                case .notify(let emitter):
                    applyNotifyEffect(emitter)
                case .emit(let emitter, let eventType, let event):
                    applyEmitEffect(emitter, eventType, event)
                case .notifyGlobalObservers(let typeId):
                    applyNotifyGlobalObserversEffect(typeId)
                case .deferCallback(let callback):
                    callback(self)
                }
            } else {
                releaseDroppedEntities()
                if pendingEffects.isEmpty {
                    break
                }
            }
        }
    }

    public func releaseDroppedEntities() {
        while true {
            let dropped = entities.takeDropped()
            if dropped.isEmpty { break }
            for (entityId, var entity) in dropped {
                _ = observers.remove(entityId)
                _ = eventListeners.remove(entityId)
                let releases = releaseListeners.remove(entityId)
                for releaseCallback in releases {
                    releaseCallback(&entity, self)
                }
            }
        }
    }

    private func applyNotifyEffect(_ emitter: EntityId) {
        pendingNotifications.remove(emitter)
        observers.retain(emitter) { handler in
            handler(self)
        }
    }

    private func applyEmitEffect(_ emitter: EntityId, _ eventType: ObjectIdentifier, _ event: Any) {
        eventListeners.retain(emitter) { entry in
            let (storedType, handler) = entry
            if storedType == eventType {
                return handler(event, self)
            }
            return true
        }
    }

    private func applyNotifyGlobalObserversEffect(_ typeId: ObjectIdentifier) {
        pendingGlobalNotifications.remove(typeId)
        globalObservers.retain(typeId) { handler in
            handler(self)
        }
    }

    public func notify(_ entityId: EntityId) {
        if pendingNotifications.insert(entityId).inserted {
            pendingEffects.append(.notify(entityId))
        }
    }

    public func emit(emitter: EntityId, eventType: ObjectIdentifier, event: Any) {
        pendingEffects.append(.emit(emitter: emitter, eventType: eventType, event: event))
    }

    public func `defer`(_ callback: @escaping (App) -> Void) {
        pendingEffects.append(.deferCallback(callback))
    }

    // AppContext implementation
    public func new<T>(_ buildEntity: (inout Context<T>) -> T) -> Entity<T> {
        let reservation: Reservation<T> = reserveEntity(T.self)
        return insertEntity(reservation, buildEntity)
    }

    public func reserveEntity<T>(_ type: T.Type = T.self) -> Reservation<T> {
        Reservation(slot: entities.reserve())
    }

    public func insertEntity<T>(
        _ reservation: Reservation<T>,
        _ buildEntity: (inout Context<T>) -> T
    ) -> Entity<T> {
        var cx = Context<T>(app: self, entityState: reservation.slot.entity.downgrade())
        let value = buildEntity(&cx)
        return entities.insert(reservation.slot, value)
    }

    public func updateEntity<T, R>(
        _ handle: Entity<T>,
        _ update: (inout T, inout Context<T>) -> R
    ) -> R {
        startUpdate()
        defer { finishUpdate() }
        var lease = entities.lease(handle)
        var cx = Context<T>(app: self, entityState: handle.downgrade())
        let result = update(&lease.value, &cx)
        entities.endLease(&lease)
        return result
    }

    public func asMut<T>(_ handle: Entity<T>) -> GpuiBorrow<T> {
        GpuiBorrow(inner: handle, app: self)
    }

    public func readEntity<T, R>(
        _ handle: Entity<T>,
        _ read: (T, App) -> R
    ) -> R {
        let val = entities.read(handle)
        return read(val, self)
    }

    // Observers and Subscriptions
    public func observe<W>(
        _ entity: Entity<W>,
        _ handler: @escaping (Entity<W>, App) -> Bool
    ) -> Subscription {
        let (subscription, activate) = observers.insert(entity.entityId) { [weak self] app in
            guard let self else { return false }
            return handler(entity, self)
        }
        self.defer { _ in activate() }
        return subscription
    }

    public func subscribe<T2, Evt>(
        _ entity: Entity<T2>,
        _ handler: @escaping (Entity<T2>, Evt, App) -> Bool
    ) -> Subscription {
        let (subscription, activate) = eventListeners.insert(entity.entityId, (
            ObjectIdentifier(Evt.self),
            { [weak self] (eventAny: Any, app: App) -> Bool in
                guard let self, let event = eventAny as? Evt else { return false }
                return handler(entity, event, self)
            }
        ))
        self.defer { _ in activate() }
        return subscription
    }

    // Globals
    public func setGlobal<G: Global>(_ global: G) {
        startUpdate()
        defer { finishUpdate() }
        let typeId = ObjectIdentifier(G.self)
        globals[typeId] = global
        if pendingGlobalNotifications.insert(typeId).inserted {
            pendingEffects.append(.notifyGlobalObservers(typeId))
        }
    }

    public func global<G: Global>(_ type: G.Type = G.self) -> G {
        guard let val = globals[ObjectIdentifier(G.self)] as? G else {
            fatalError("no global of type \(G.self) found")
        }
        return val
    }

    public func tryGlobal<G: Global>(_ type: G.Type = G.self) -> G? {
        globals[ObjectIdentifier(G.self)] as? G
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        globals[ObjectIdentifier(G.self)] != nil
    }

    public func leaseGlobal<G: Global>(_ type: G.Type = G.self) -> G {
        guard let val = globals.removeValue(forKey: ObjectIdentifier(G.self)) as? G else {
            fatalError("no global of type \(G.self) found")
        }
        return val
    }

    public func endGlobalLease<G: Global>(_ global: G) {
        setGlobal(global)
    }

    public func updateGlobal<G: Global, R>(_ update: (inout G, App) -> R) -> R {
        var g: G = leaseGlobal()
        let result = update(&g, self)
        endGlobalLease(g)
        return result
    }

    public func updateDefaultGlobal<G: Global & Default, R>(_ update: (inout G, App) -> R) -> R {
        if !hasGlobal(G.self) {
            globals[ObjectIdentifier(G.self)] = G.default()
        }
        return updateGlobal(update)
    }

    public func readGlobal<G: Global, R>(_ callback: (G, App) -> R) -> R {
        callback(global(), self)
    }

    public func observeGlobal<G: Global>(_ type: G.Type = G.self, _ handler: @escaping (App) -> Bool) -> Subscription {
        let (subscription, activate) = globalObservers.insert(ObjectIdentifier(G.self)) { [weak self] app in
            guard let self else { return false }
            return handler(self)
        }
        self.defer { _ in activate() }
        return subscription
    }

    public func toAsync() -> AsyncApp {
        let bg = backgroundExecutor ?? BackgroundExecutor(scheduler: TestScheduler())
        let fg = foregroundExecutor ?? ForegroundExecutor(sessionId: SessionId(0), scheduler: TestScheduler())
        return AsyncApp(app: self, backgroundExecutor: bg, foregroundExecutor: fg)
    }
}
