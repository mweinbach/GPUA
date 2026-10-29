// Ported from: crates/gpui/src/platform/test/display.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

// PORT NOTE: TestDisplay is an immutable mock display for testing.
public final class TestDisplay: PlatformDisplay, @unchecked Sendable {
    public let idValue: DisplayId
    public let uuidValue: UUID
    public let boundsValue: Bounds<Pixels>

    public init(
        id: DisplayId = DisplayId(1),
        uuid: UUID = UUID(),
        bounds: Bounds<Pixels> = Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(1920), height: px(1080)))
    ) {
        self.idValue = id
        self.uuidValue = uuid
        self.boundsValue = bounds
    }

    public static func new() -> TestDisplay {
        TestDisplay()
    }

    public func id() -> DisplayId {
        idValue
    }

    public func uuid() throws -> UUID {
        uuidValue
    }

    public func bounds() -> Bounds<Pixels> {
        boundsValue
    }

    public func visibleBounds() -> Bounds<Pixels> {
        boundsValue
    }
}
