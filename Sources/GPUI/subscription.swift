// Ported from: crates/gpui/src/subscription.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// A handle to a subscription created by GPUI. When dropped (or released),
/// the subscription is cancelled and the callback will no longer be invoked.
public final class Subscription: @unchecked Sendable, CustomDebugStringConvertible {
    private let lock = NSLock()
    private var unsubscribe: (@Sendable () -> Void)?

    public init(_ unsubscribe: @escaping @Sendable () -> Void = {}) {
        self.unsubscribe = unsubscribe
    }

    /// Detaches the subscription from this handle. The callback will
    /// continue to be invoked until the entities it has been
    /// subscribed to are dropped.
    public func detach() {
        lock.lock()
        defer { lock.unlock() }
        self.unsubscribe = nil
    }

    /// Joins two subscriptions into a single subscription. Detach will
    /// detach both interior subscriptions.
    public static func join(_ subscriptionA: Subscription, _ subscriptionB: Subscription) -> Subscription {
        let aUnsub = subscriptionA.takeUnsubscribe()
        let bUnsub = subscriptionB.takeUnsubscribe()
        return Subscription {
            if let aUnsub {
                aUnsub()
            }
            if let bUnsub {
                bUnsub()
            }
        }
    }

    private func takeUnsubscribe() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let unsub = self.unsubscribe
        self.unsubscribe = nil
        return unsub
    }

    deinit {
        takeUnsubscribe()?()
    }

    public var debugDescription: String {
        "Subscription"
    }
}

final class Subscriber<Callback>: @unchecked Sendable {
    let active: AtomicBool
    let dropped: AtomicBool
    var callback: Callback

    init(active: Bool, dropped: Bool, callback: Callback) {
        self.active = AtomicBool(active)
        self.dropped = AtomicBool(dropped)
        self.callback = callback
    }
}

final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) {
        self._value = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

public final class SubscriberSet<EmitterKey: Hashable & Sendable, Callback>: @unchecked Sendable {
    private final class State {
        var subscribers: [EmitterKey: [Int: Subscriber<Callback>]] = [:]
        var nextSubscriberId: Int = 0
    }
    private let lock = NSLock()
    private let state = State()

    public init() {}

    /// Inserts a new `Subscription` for the given `emitterKey`. By default, subscriptions
    /// are inert, meaning that they won't be listed when calling `remove` or `retain`.
    /// Returns a tuple of a `Subscription` and a closure to activate it.
    public func insert(
        _ emitterKey: EmitterKey,
        _ callback: Callback
    ) -> (Subscription, @Sendable () -> Void) {
        lock.lock()
        let subscriberId = state.nextSubscriberId
        state.nextSubscriberId += 1

        let subscriber = Subscriber(active: false, dropped: false, callback: callback)
        if state.subscribers[emitterKey] == nil {
            state.subscribers[emitterKey] = [:]
        }
        state.subscribers[emitterKey]![subscriberId] = subscriber
        lock.unlock()

        let subscription = Subscription { [weak self] in
            subscriber.dropped.value = true
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if var subs = self.state.subscribers[emitterKey] {
                subs.removeValue(forKey: subscriberId)
                if subs.isEmpty {
                    self.state.subscribers.removeValue(forKey: emitterKey)
                } else {
                    self.state.subscribers[emitterKey] = subs
                }
            }
        }

        let activate: @Sendable () -> Void = {
            subscriber.active.value = true
        }

        return (subscription, activate)
    }

    /// Removes all subscribers for the given emitter, returning active and non-dropped callbacks.
    public func remove(_ emitter: EmitterKey) -> [Callback] {
        lock.lock()
        let subs = state.subscribers.removeValue(forKey: emitter)
        lock.unlock()

        guard let subs else { return [] }
        // PORT NOTE: Upstream uses BTreeMap<usize, Subscriber>, preserving insertion order by subscriber ID
        let sortedIds = subs.keys.sorted()
        return sortedIds.compactMap { id in
            guard let subscriber = subs[id] else { return nil }
            if subscriber.active.value && !subscriber.dropped.value {
                return subscriber.callback
            }
            return nil
        }
    }

    /// Call the given callback for each subscriber to the given emitter.
    /// If the callback returns false, the subscriber is removed.
    public func retain(_ emitter: EmitterKey, _ f: (inout Callback) -> Bool) {
        lock.lock()
        guard var subs = state.subscribers.removeValue(forKey: emitter) else {
            lock.unlock()
            return
        }
        lock.unlock()

        var toRemove: [Int] = []
        // PORT NOTE: Upstream uses BTreeMap<usize, Subscriber>, preserving insertion order by subscriber ID
        let sortedIds = subs.keys.sorted()
        for id in sortedIds {
            guard let subscriber = subs[id] else { continue }
            if !subscriber.active.value {
                continue
            }
            if subscriber.dropped.value {
                toRemove.append(id)
                continue
            }
            let keep = f(&subscriber.callback)
            if !keep || subscriber.dropped.value {
                toRemove.append(id)
            }
        }

        for id in toRemove {
            subs.removeValue(forKey: id)
        }

        lock.lock()
        if let newSubs = state.subscribers.removeValue(forKey: emitter) {
            for (k, v) in newSubs {
                subs[k] = v
            }
        }
        if !subs.isEmpty {
            state.subscribers[emitter] = subs
        }
        lock.unlock()
    }

    public func clone() -> SubscriberSet<EmitterKey, Callback> {
        self
    }
}
