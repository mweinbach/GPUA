// Ported from: crates/gpui_linux/src/linux/wayland/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

public struct ObjectId: Hashable, Sendable {
    public var id: UInt32

    public init(_ id: UInt32 = 0) {
        self.id = id
    }

    public func protocolId() -> UInt32 {
        id
    }
}

// PORT NOTE: WaylandDisplay stores output geometry and identity conforming to PlatformDisplay.
public final class WaylandDisplay: PlatformDisplay, Hashable, @unchecked Sendable {
    public var displayId: ObjectId
    public var name: String?
    public var displayBounds: Bounds<Pixels>

    public init(
        id: ObjectId = ObjectId(0),
        name: String? = nil,
        bounds: Bounds<Pixels> = Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080)))
    ) {
        self.displayId = id
        self.name = name
        self.displayBounds = bounds
    }

    public static func == (lhs: WaylandDisplay, rhs: WaylandDisplay) -> Bool {
        lhs.displayId == rhs.displayId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(displayId)
    }

    public func id() -> DisplayId {
        DisplayId(displayId.protocolId())
    }

    public func uuid() throws -> UUID {
        guard let name = name else {
            throw LinuxError("Wayland display does not have a name")
        }
        var hasher = Hasher()
        hasher.combine(name)
        let hashValue = hasher.finalize()
        return UUID(uuidString: String(format: "%08x-0000-5000-8000-%012x", UInt32(truncatingIfNeeded: hashValue), UInt64(truncatingIfNeeded: hashValue))) ?? UUID()
    }

    public func bounds() -> Bounds<Pixels> {
        displayBounds
    }

    public func visibleBounds() -> Bounds<Pixels> {
        displayBounds
    }
}
#endif
