// Ported from: crates/rune/src/drag_out/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public struct DragImage: Sendable, Equatable {
    public var width: UInt32
    public var height: UInt32
    public var rgba: [UInt8]

    public init(width: UInt32, height: UInt32, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum DragOperation: Sendable, Equatable, Hashable {
    case copy
    case move
    case link
}

public enum DragOutcome: Sendable, Equatable, Hashable {
    case completed(DragOperation)
    case cancelled
}

public struct DragItem: Sendable, Equatable {
    public var text: String?
    public var paths: [String]
    public var image: DragImage?

    public init(text: String? = nil, paths: [String] = [], image: DragImage? = nil) {
        self.text = text
        self.paths = paths
        self.image = image
    }
}
