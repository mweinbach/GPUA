// Ported from: crates/rune/src/live.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Latest-wins property values. Sources outlive views and may be shared by windows.

#if !os(WASI)
import Foundation
#endif
import RuneMotion

public typealias Waker = @Sendable () -> Void

/// Packed 128-bit lane carrier (`4 × UInt32`) for ``LiveValue``.
public struct PackedLiveBits: Sendable, Equatable, Hashable {
    public var l0: UInt32
    public var l1: UInt32
    public var l2: UInt32
    public var l3: UInt32

    public static let zero = PackedLiveBits(0, 0, 0, 0)

    public init(_ l0: UInt32 = 0, _ l1: UInt32 = 0, _ l2: UInt32 = 0, _ l3: UInt32 = 0) {
        self.l0 = l0
        self.l1 = l1
        self.l2 = l2
        self.l3 = l3
    }

    subscript(_ lane: Int) -> UInt32 {
        get {
            switch lane {
            case 0: return l0
            case 1: return l1
            case 2: return l2
            default: return l3
            }
        }
        set {
            switch lane {
            case 0: l0 = newValue
            case 1: l1 = newValue
            case 2: l2 = newValue
            default: l3 = newValue
            }
        }
    }
}

/// The small, coherently published values supported by ``Live``.
public protocol LiveValue: Sendable {
    func encodeLive() -> PackedLiveBits?
    static func decodeLive(_ bits: PackedLiveBits) -> Self
}

@inline(__always)
private func encodeLane(_ v: Float) -> UInt32? {
    if v.isNaN { return nil }
    let x: Float = (v == 0.0) ? 0.0 : min(max(v, -Float.greatestFiniteMagnitude), Float.greatestFiniteMagnitude)
    return x.bitPattern
}

extension Float: LiveValue {
    public func encodeLive() -> PackedLiveBits? {
        guard let b0 = encodeLane(self) else { return nil }
        return PackedLiveBits(b0, 0, 0, 0)
    }

    public static func decodeLive(_ bits: PackedLiveBits) -> Float {
        Float(bitPattern: bits.l0)
    }
}

extension Array: LiveValue where Element == Float {
    public func encodeLive() -> PackedLiveBits? {
        if count == 2 {
            guard let b0 = encodeLane(self[0]), let b1 = encodeLane(self[1]) else { return nil }
            return PackedLiveBits(b0, b1, 0, 0)
        } else if count >= 4 {
            guard let b0 = encodeLane(self[0]),
                  let b1 = encodeLane(self[1]),
                  let b2 = encodeLane(self[2]),
                  let b3 = encodeLane(self[3])
            else { return nil }
            return PackedLiveBits(b0, b1, b2, b3)
        }
        return nil
    }

    public static func decodeLive(_ bits: PackedLiveBits) -> [Float] {
        [
            Float(bitPattern: bits.l0),
            Float(bitPattern: bits.l1),
            Float(bitPattern: bits.l2),
            Float(bitPattern: bits.l3),
        ]
    }
}

extension Color: LiveValue {
    public func encodeLive() -> PackedLiveBits? {
        guard let b0 = encodeLane(r),
              let b1 = encodeLane(g),
              let b2 = encodeLane(b),
              let b3 = encodeLane(a)
        else { return nil }
        return PackedLiveBits(b0, b1, b2, b3)
    }

    public static func decodeLive(_ bits: PackedLiveBits) -> Color {
        Color(
            r: Float(bitPattern: bits.l0),
            g: Float(bitPattern: bits.l1),
            b: Float(bitPattern: bits.l2),
            a: Float(bitPattern: bits.l3)
        )
    }
}

// PORT NOTE: Synchronizes `LiveSource` / `LiveWake` / `LiveText` with `NSLock` on multi-threaded platforms
// and direct access on single-threaded WASI, preserving tear-free 4-lane publication without unsafe raw pointers.
final class LiveLock: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif

    @inline(__always)
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return try body()
    }
}

final class LiveClockToken: Sendable {
    init() {}
}

// PORT NOTE: Guarded by `lock` so weak runtime clock start times are thread-safe across windows.
final class LiveLinear: @unchecked Sendable {
    let from: PackedLiveBits
    let duration: Double
    private let lock = LiveLock()
    private var starts: [(weakToken: WeakClockRef, start: Double)] = []

    struct WeakClockRef {
        weak var value: LiveClockToken?
    }

    init(from: PackedLiveBits, duration: Double) {
        self.from = from
        self.duration = duration
    }

    func start(_ clock: LiveClockToken, _ now: Double) -> Double {
        lock.withLock {
            starts.removeAll { $0.weakToken.value == nil }
            if let existing = starts.first(where: { $0.weakToken.value === clock }) {
                return existing.start
            }
            starts.append((WeakClockRef(value: clock), now))
            return now
        }
    }

    func sample(_ to: PackedLiveBits, _ elapsed: Double) -> (PackedLiveBits, Bool) {
        let t: Double = duration == 0.0 ? 1.0 : min(max(elapsed / duration, 0.0), 1.0)
        if t >= 1.0 { return (to, false) }
        if t <= 0.0 { return (from, true) }
        var out = PackedLiveBits.zero
        for lane in 0..<4 {
            let a = Double(Float(bitPattern: from[lane]))
            let b = Double(Float(bitPattern: to[lane]))
            let mixed = Float(a * (1.0 - t) + b * t)
            out[lane] = encodeLane(mixed) ?? 0
        }
        return (out, true)
    }
}

// PORT NOTE: Coalesces notifications and respects window visibility under `lock`, matching `live::Wake` in upstream.
final class LiveWake: @unchecked Sendable {
    private let lock = LiveLock()
    private var _pending: Bool = false
    private var _visible: Bool = true
    private let callback: Waker

    init(_ callback: @escaping Waker) {
        self.callback = callback
    }

    var pending: Bool {
        get { lock.withLock { _pending } }
        set { lock.withLock { _pending = newValue } }
    }

    func setVisible(_ visible: Bool) {
        let shouldFire: Bool = lock.withLock {
            let was = _visible
            _visible = visible
            return visible && !was && _pending
        }
        if shouldFire {
            callback()
        }
    }

    func notify() {
        let shouldFire: Bool = lock.withLock {
            if !_pending {
                _pending = true
                return _visible
            }
            return false
        }
        if shouldFire {
            callback()
        }
    }
}

// PORT NOTE: Thread-safe subscription cell referencing `LiveWake` weakly, matching `live::Subscription`.
final class LiveSubscription: @unchecked Sendable {
    let sourceId: UInt64
    private let lock = LiveLock()
    private var _active: Bool = true
    weak var wake: LiveWake?

    init(sourceId: UInt64, wake: LiveWake) {
        self.sourceId = sourceId
        self.wake = wake
    }

    var active: Bool {
        get { lock.withLock { _active } }
        set { lock.withLock { _active = newValue } }
    }
}

// PORT NOTE: Thread-safe 128-bit lane publication and listener registry guarded by `LiveLock`.
final class LiveSource: @unchecked Sendable {
    private static let idLock = LiveLock()
    // PORT NOTE: Protected by `idLock`.
    nonisolated(unsafe) private static var nextId: UInt64 = 1

    let id: UInt64
    var linear: LiveLinear?
    private let lock = LiveLock()
    private var bits: PackedLiveBits
    private var generationCounter: UInt64 = 0
    private var listeners: [LiveSubscription] = []

    init(_ initial: PackedLiveBits, linear: LiveLinear? = nil) {
        self.id = Self.idLock.withLock {
            let v = Self.nextId
            Self.nextId &+= 1
            return v
        }
        self.bits = initial
        self.linear = linear
    }

    func load() -> PackedLiveBits {
        lock.withLock { bits }
    }

    func swap(_ newBits: PackedLiveBits) -> PackedLiveBits {
        lock.withLock {
            let old = bits
            bits = newBits
            return old
        }
    }

    func bumpGeneration() -> UInt64 {
        lock.withLock {
            generationCounter &+= 1
            return generationCounter
        }
    }

    func currentGeneration() -> UInt64 {
        lock.withLock { generationCounter }
    }

    func subscribe(_ wake: LiveWake) -> LiveSubscription {
        lock.withLock {
            listeners.removeAll { $0.wake == nil }
            if let existing = listeners.first(where: { $0.wake === wake }) {
                existing.active = true
                return existing
            }
            let sub = LiveSubscription(sourceId: id, wake: wake)
            listeners.append(sub)
            return sub
        }
    }

    func notify() {
        let targets: [LiveWake] = lock.withLock {
            listeners.removeAll { $0.wake == nil }
            return listeners.compactMap { $0.active ? $0.wake : nil }
        }
        for w in targets {
            w.notify()
        }
    }
}

/// Latest-wins text for a fixed layout box. Equal strings do not wake subscribers.
// PORT NOTE: Synchronized via `LiveLock` for cross-thread publication parity with `Arc<Mutex<Arc<str>>>`.
public final class LiveText: @unchecked Sendable {
    private let lock = LiveLock()
    private var currentText: String
    let source: LiveSource

    public init(_ text: String) {
        self.currentText = text
        self.source = LiveSource(.zero)
    }

    public static func new(_ text: String) -> LiveText {
        LiveText(text)
    }

    public func get() -> String {
        lock.withLock { currentText }
    }

    @discardableResult
    public func set(_ text: String) -> Bool {
        let changed: Bool = lock.withLock {
            if currentText == text { return false }
            currentText = text
            _ = source.bumpGeneration()
            return true
        }
        if changed {
            source.notify()
        }
        return changed
    }

    func read(_ seen: inout UInt64?) -> String? {
        let gen = source.currentGeneration()
        if seen == gen { return nil }
        let value = lock.withLock { currentText }
        seen = source.currentGeneration()
        return value
    }
}

/// Cloneable, thread-safe, coherent latest value. Equal bit patterns do not wake a window.
public struct Live<T: LiveValue>: Sendable {
    let source: LiveSource

    public init(_ value: T) {
        self.source = LiveSource(value.encodeLive() ?? .zero)
    }

    public static func new(_ value: T) -> Live<T> {
        Live(value)
    }

    @discardableResult
    public func set(_ value: T) -> Bool {
        guard let encoded = value.encodeLive() else { return false }
        if source.swap(encoded) == encoded {
            return false
        }
        source.notify()
        return true
    }

    public func get() -> T {
        T.decodeLive(source.load())
    }

    public func smooth(_ spring: Spring) -> Binding<T> {
        Binding(live: self, spring: spring)
    }
}

public struct Binding<T: LiveValue>: Sendable {
    public let live: Live<T>
    public let spring: Spring?

    public init(live: Live<T>, spring: Spring? = nil) {
        self.live = live
        self.spring = spring
    }
}

/// A linear, render-time track. Keep it in app state and bind it like a ``Live`` value.
public struct Tween<T: LiveValue>: Sendable {
    public let live: Live<T>

    public static func linear(_ from: T, _ to: T, _ duration: Duration) -> Tween<T> {
        let secs = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        let lin = LiveLinear(from: from.encodeLive() ?? .zero, duration: secs)
        let source = LiveSource(to.encodeLive() ?? .zero, linear: lin)
        return Tween(live: Live(source: source))
    }
}

extension Live {
    init(source: LiveSource) {
        self.source = source
    }
}

enum LiveProperty: Sendable, Equatable {
    case opacity
    case offset
    case scale
    case fill
    case rect
    case blur
}

struct LiveBound: Sendable {
    let source: LiveSource
    let property: LiveProperty
    let spring: Spring?
    var seen: PackedLiveBits?

    init<T: LiveValue>(_ binding: Binding<T>, _ property: LiveProperty) {
        self.source = binding.live.source
        self.property = property
        self.spring = binding.spring
        self.seen = nil
    }

    func attach(_ clock: LiveClockToken, _ now: Double) {
        if let linear = source.linear {
            _ = linear.start(clock, now)
        }
    }

    mutating func read(_ clock: LiveClockToken, _ now: Double) -> (PackedLiveBits?, Bool) {
        let raw = source.load()
        let (sampled, active): (PackedLiveBits, Bool)
        if let linear = source.linear {
            sampled = linear.sample(raw, now - linear.start(clock, now)).0
            active = linear.sample(raw, now - linear.start(clock, now)).1
        } else {
            sampled = raw
            active = false
        }
        if seen == sampled {
            return (nil, active)
        }
        seen = sampled
        return (sampled, active)
    }
}
