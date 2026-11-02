// Ported from: crates/procwatch/src/gauge.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

#if DEBUG || ReleaseGauges
internal let gaugesOn: Bool = true
#else
internal let gaugesOn: Bool = false
#endif

/// Namespace mirroring `procwatch::gauge`.
public enum gauge {
    /// Gauges there's room for; more still count but aren't listed.
    public static let gauges: Int = 64
}

// PORT NOTE: Synchronized via internal NSLock protecting the bounded 64-slot gauge registry.
private final class GaugeRegistry: @unchecked Sendable {
    static let shared = GaugeRegistry()

    private let lock = NSLock()
    private var slots: [Gauge] = []

    func register(_ g: Gauge) {
        lock.lock()
        if slots.count < gauge.gauges {
            slots.append(g)
        }
        lock.unlock()
    }

    func snapshot() -> [(String, Int64)] {
        lock.lock()
        let copy = slots
        lock.unlock()
        var out = copy.map { ($0.name(), $0.get()) }
        out.sort { $0.1 > $1.1 }
        return out
    }
}

/// Byte gauge for memory the allocator never sees: pixel buffers, IOSurfaces, GPU textures,
/// model weights mapped by a C library, or a queue you want named in a warning.
// PORT NOTE: Synchronized via internal NSLock protecting byte counter and one-time registration flag.
public final class Gauge: @unchecked Sendable {
    private let gaugeName: String
    private let lock = NSLock()
    private var currentBytes: Int64 = 0
    private var isRegistered: Bool = false

    public init(_ name: String) {
        self.gaugeName = name
    }

    public static func new(_ name: String) -> Gauge {
        Gauge(name)
    }

    public func name() -> String {
        gaugeName
    }

    /// Current bytes (0 when gauges are compiled out).
    public func get() -> Int64 {
        lock.lock()
        let v = currentBytes
        lock.unlock()
        return v
    }

    @inline(__always)
    public func add(_ bytes: Int) {
        guard gaugesOn else { return }
        registerIfNeeded()
        lock.lock()
        currentBytes += Int64(bytes)
        lock.unlock()
    }

    @inline(__always)
    public func sub(_ bytes: Int) {
        guard gaugesOn else { return }
        lock.lock()
        currentBytes -= Int64(bytes)
        lock.unlock()
    }

    /// Replaces the total, for a size you measure rather than count.
    @inline(__always)
    public func set(_ bytes: Int) {
        guard gaugesOn else { return }
        registerIfNeeded()
        lock.lock()
        currentBytes = Int64(bytes)
        lock.unlock()
    }

    /// Adds `bytes` now and subtracts them when the lease drops.
    @inline(__always)
    public func track(_ bytes: Int) -> Lease {
        add(bytes)
        return Lease(gauge: self, bytes: bytes)
    }

    private func registerIfNeeded() {
        var shouldRegister = false
        lock.lock()
        if !isRegistered {
            isRegistered = true
            shouldRegister = true
        }
        lock.unlock()
        if shouldRegister {
            GaugeRegistry.shared.register(self)
        }
    }
}

/// Bytes counted against a ``Gauge`` until dropped.
// PORT NOTE: Synchronized via internal NSLock ensuring idempotent subtraction on drop/deinit.
public final class Lease: @unchecked Sendable {
    private let gauge: Gauge
    private let leasedBytes: Int
    private let lock = NSLock()
    private var dropped: Bool = false

    init(gauge: Gauge, bytes: Int) {
        self.gauge = gauge
        self.leasedBytes = bytes
    }

    public func bytes() -> Int {
        leasedBytes
    }

    /// Explicitly drops the lease early; subsequent calls or `deinit` are no-ops.
    public func drop() {
        var shouldSub = false
        lock.lock()
        if !dropped {
            dropped = true
            shouldSub = true
        }
        lock.unlock()
        if shouldSub {
            gauge.sub(leasedBytes)
        }
    }

    deinit {
        drop()
    }
}

/// Every gauge used so far, biggest first.
public func gauges() -> [(String, Int64)] {
    GaugeRegistry.shared.snapshot()
}
