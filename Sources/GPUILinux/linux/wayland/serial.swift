// Ported from: crates/gpui_linux/src/linux/wayland/serial.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation

public enum SerialKind: Hashable, Sendable {
    case dataDevice
    case inputMethod
    case mouseEnter
    case mousePress
    case keyPress
}

struct SerialData: Sendable {
    var serial: UInt32

    init(serial: UInt32) {
        self.serial = serial
    }

    static func new(_ value: UInt32) -> SerialData {
        SerialData(serial: value)
    }
}

/// Helper for tracking of different serial kinds.
public struct SerialTracker: Sendable {
    private var serials: [SerialKind: SerialData]

    public init() {
        self.serials = [:]
    }

    public static func new() -> SerialTracker {
        SerialTracker()
    }

    public mutating func update(_ kind: SerialKind, _ value: UInt32) {
        serials[kind] = SerialData.new(value)
    }

    /// Returns the latest tracked serial of the provided [`SerialKind`]
    ///
    /// Will return 0 if not tracked.
    public func get(_ kind: SerialKind) -> UInt32 {
        serials[kind]?.serial ?? 0
    }

    /// Returns the latest tracked serial of the provided [`SerialKind`]s
    ///
    /// Will return 0 if not tracked.
    public func latestOf(_ kinds: [SerialKind]) -> UInt32 {
        kinds
            .compactMap { serials[$0]?.serial }
            .max() ?? 0
    }
}
#endif
