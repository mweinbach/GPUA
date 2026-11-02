// Ported from: crates/rune/src/runtime/elements.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Element inspection (`Runtime.elements`, `presented`, `presentedPose`) and point picking (`Runtime.elementAt`).

/// What tools see of one element.
public struct ElementInfo: Sendable, Equatable {
    public var traceName: String?
    public var traceNamespace: (String, String)?
    public var loopPhase: Double?
    public var focusable: Bool
    public var focused: Bool
    public var focusVisible: Bool
    public var inert: Bool
    public var exiting: Bool
    public var path: String
    public var key: String?
    public var role: String
    public var label: String?
    public var text: String?
    public var rect: [Float]
    public var target: [Float]
    public var opacity: Float
    public var scale: Float
    public var blur: Float
    public var radius: Float
    public var fill: Color
    public var textColor: Color?
    public var hover: Float
    public var press: Float
    public var moving: Bool
    public var parent: Int?
    public var visible: [Float]
    public var revealing: Bool
    public var inGrowingRow: Bool
    public var scrolling: Bool
    public var scrolled: [Float]
    public var virtualExtent: Bool
    public var liveIntent: UInt32
    public var caret: [Float]?
    public var dragOut: Bool
    public var help: String?
    public var selected: String?
    public var level: UInt32?
    public var expanded: Bool?
    public var itemSelected: Bool
    public var stuck: Float

    public init(
        path: String,
        key: String? = nil,
        role: String = "group",
        label: String? = nil,
        text: String? = nil,
        rect: [Float] = [0, 0, 0, 0],
        target: [Float] = [0, 0, 0, 0],
        opacity: Float = 1.0,
        scale: Float = 1.0,
        blur: Float = 0.0,
        radius: Float = 0.0,
        fill: Color = .TRANSPARENT,
        textColor: Color? = nil,
        parent: Int? = nil
    ) {
        self.traceName = nil
        self.traceNamespace = nil
        self.loopPhase = nil
        self.focusable = false
        self.focused = false
        self.focusVisible = false
        self.inert = false
        self.exiting = false
        self.path = path
        self.key = key
        self.role = role
        self.label = label
        self.text = text
        self.rect = rect
        self.target = target
        self.opacity = opacity
        self.scale = scale
        self.blur = blur
        self.radius = radius
        self.fill = fill
        self.textColor = textColor
        self.hover = 0
        self.press = 0
        self.moving = false
        self.parent = parent
        self.visible = rect
        self.revealing = false
        self.inGrowingRow = false
        self.scrolling = false
        self.scrolled = [0, 0]
        self.virtualExtent = false
        self.liveIntent = 0
        self.caret = nil
        self.dragOut = false
        self.help = nil
        self.selected = nil
        self.level = nil
        self.expanded = nil
        self.itemSelected = false
        self.stuck = 0
    }

    public static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
        lhs.path == rhs.path && lhs.key == rhs.key && lhs.role == rhs.role
            && lhs.label == rhs.label && lhs.text == rhs.text && lhs.rect == rhs.rect
            && lhs.target == rhs.target && lhs.opacity == rhs.opacity && lhs.scale == rhs.scale
            && lhs.fill == rhs.fill && lhs.focused == rhs.focused && lhs.exiting == rhs.exiting
    }
}

/// An element `Runtime.elementAt` found.
public struct Picked: Sendable, Equatable {
    var pathValue: String
    var keyValue: String?

    public init(path: String, key: String? = nil) {
        self.pathValue = path
        self.keyValue = key
    }

    public func path() -> String { pathValue }
    public func key() -> String? { keyValue }
}

/// Options for `Runtime.elementAtWith` and siblings.
public struct Pick: Sendable, Equatable {
    var includeTransparent: Bool = false

    public init() {}

    public static func new() -> Pick { Pick() }

    public func transparent(_ on: Bool) -> Pick {
        var copy = self
        copy.includeTransparent = on
        return copy
    }
}

/// What an element presents beyond its rect and opacity, as of the last frame.
public struct Pose: Sendable, Equatable {
    var rotationValue: Float
    var scaleValue: Float
    var shadowsList: [Shadow]
    var movingFlag: Bool

    public init(
        rotation: Float = 0,
        scale: Float = 1,
        shadows: [Shadow] = [],
        moving: Bool = false
    ) {
        self.rotationValue = rotation
        self.scaleValue = scale
        self.shadowsList = shadows
        self.movingFlag = moving
    }

    public func rotation() -> Float { rotationValue }
    public func scale() -> Float { scaleValue }
    public func shadows() -> [Shadow] { shadowsList }
    public func moving() -> Bool { movingFlag }
}
