// Ported from: crates/rune/src/runtime/event_log.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Ring buffer of input/commit/trace event markers for motion diagnostics and test assertions.

public struct EventMarker: Sendable, Equatable {
    public var t: Double
    public var frame: UInt64
    public var kind: String
    public var detail: String

    public init(t: Double, frame: UInt64, kind: String, detail: String = "") {
        self.t = t
        self.frame = frame
        self.kind = kind
        self.detail = detail
    }
}

struct EventLog: Sendable {
    static let capacity = 256
    private var entries: [EventMarker] = []
    var enabled: Bool = true

    init() {}

    mutating func push(t: Double, frame: UInt64, kind: String, detail: String = "", force: Bool = false) {
        guard enabled || force else { return }
        if entries.count >= Self.capacity {
            entries.removeFirst(entries.count - Self.capacity + 1)
        }
        entries.append(EventMarker(t: t, frame: frame, kind: kind, detail: detail))
    }

    func all() -> [EventMarker] {
        entries
    }

    mutating func take() -> [EventMarker] {
        let out = entries
        entries.removeAll(keepingCapacity: true)
        return out
    }

    mutating func clear() {
        entries.removeAll(keepingCapacity: true)
    }
}

extension Runtime {
    func pushEventMarker(kind: String, detail: String = "") {
        eventLog.push(t: t, frame: frameIndex, kind: kind, detail: detail, force: scene.tracing())
    }

    public func setEventMarkersEnabled(_ enabled: Bool) {
        eventLog.enabled = enabled
    }

    public func eventMarkers() -> [EventMarker] {
        eventLog.all()
    }

    public func takeEventMarkers() -> [EventMarker] {
        eventLog.take()
    }

    public func clearEventMarkers() {
        eventLog.clear()
    }
}
