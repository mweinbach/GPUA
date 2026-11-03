// Ported from: crates/rune/src/runtime/input/drop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! External file/text drop hover & drop dispatch onto window elements.

public struct DroppedPayload: Sendable, Equatable {
    public var paths: [String]
    public var text: String?
    public var x: Float
    public var y: Float

    public init(paths: [String] = [], text: String? = nil, x: Float = 0.0, y: Float = 0.0) {
        self.paths = paths
        self.text = text
        self.x = x
        self.y = y
    }
}

extension Runtime {
    public func dropHover(_ x: Float, _ y: Float) {
        dropHoverPoint = (x, y)
        updateHoverAt(x, y, commitIfChanged: true)
    }

    public func dropLeave() {
        dropHoverPoint = nil
    }

    public func dropFiles(_ paths: [String], at x: Float, _ y: Float) {
        dropHoverPoint = nil
        lastDroppedPayload = DroppedPayload(paths: paths, text: nil, x: x, y: y)
        eventLog.push(t: t, frame: frameIndex, kind: "drop", detail: "\(paths.count) files")
        markDirty(CommitWhy.DROP)
    }

    public func lastDrop() -> DroppedPayload? {
        lastDroppedPayload
    }
}
