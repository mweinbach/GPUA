// Ported from: crates/rune/src/tooling.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Agent tooling: headless deterministic rendering, synthetic input scripts, element-tree dumps,
//! motion-lint traces and frame strips.

public struct AppSpec<S> {
    public var title: String
    public var size: (Float, Float)
    public var minSize: (Float, Float)?
    public var `init`: () -> S
    public var view: (S, Cx<S>) -> El
    public var scenes: [(String, (inout S) -> Void)]
    public var fonts: [[UInt8]]
    public var families: (String, String)
    public var setup: ((inout S, Waker) -> Void)?
    public var poll: ((inout S, Double, inout Tx) -> Bool)?
    public var onKey: ((inout S, KeyEvent, inout Tx) -> Bool)?

    public init(
        title: String,
        size: (Float, Float),
        minSize: (Float, Float)? = nil,
        init initFn: @escaping () -> S,
        view: @escaping (S, Cx<S>) -> El,
        scenes: [(String, (inout S) -> Void)] = [],
        fonts: [[UInt8]] = [],
        families: (String, String) = ("Inter", "Inter"),
        setup: ((inout S, Waker) -> Void)? = nil,
        poll: ((inout S, Double, inout Tx) -> Bool)? = nil,
        onKey: ((inout S, KeyEvent, inout Tx) -> Bool)? = nil
    ) {
        self.title = title
        self.size = size
        self.minSize = minSize
        self.`init` = initFn
        self.view = view
        self.scenes = scenes
        self.fonts = fonts
        self.families = families
        self.setup = setup
        self.poll = poll
        self.onKey = onKey
    }

    public static func new(
        _ title: String,
        _ size: (Float, Float),
        _ initFn: @escaping () -> S,
        _ view: @escaping (S, Cx<S>) -> El
    ) -> AppSpec<S> {
        AppSpec(title: title, size: size, init: initFn, view: view)
    }
}

/// Window frame options.
public struct Chrome: Sendable, Equatable {
    public var fullSizeContent: Bool
    public var trafficLights: (Float, Float)?
    public var dragRegions: Bool

    public static let DEFAULT = Chrome(fullSizeContent: true, trafficLights: nil, dragRegions: false)
    public static let TRAFFIC_LIGHT: Float = 14.0
    public static let TRAFFIC_PITCH: Float = 23.0

    public init(
        fullSizeContent: Bool = true,
        trafficLights: (Float, Float)? = nil,
        dragRegions: Bool = false
    ) {
        self.fullSizeContent = fullSizeContent
        self.trafficLights = trafficLights
        self.dragRegions = dragRegions
    }

    public static func == (lhs: Chrome, rhs: Chrome) -> Bool {
        guard lhs.fullSizeContent == rhs.fullSizeContent,
              lhs.dragRegions == rhs.dragRegions
        else { return false }
        switch (lhs.trafficLights, rhs.trafficLights) {
        case (nil, nil): return true
        case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
        default: return false
        }
    }

    public func trafficLightRects() -> [[Float]]? {
        if !fullSizeContent && trafficLights == nil {
            return nil
        }
        let (x, y) = trafficLights ?? (7.0, 6.0)
        return (0..<3).map { i in
            [x + Float(i) * Self.TRAFFIC_PITCH, y, Self.TRAFFIC_LIGHT, Self.TRAFFIC_LIGHT]
        }
    }

    public func titlebarInset() -> Float {
        guard let rects = trafficLightRects() else { return 0.0 }
        return rects[2][0] + rects[2][2]
    }
}

private let toolingGlobalsLock = LiveLock()
// PORT NOTE: Guarded by `toolingGlobalsLock` for process-wide app ID and unrecognized CLI args.
nonisolated(unsafe) private var globalAppIdValue: String? = nil
// PORT NOTE: Guarded by `toolingGlobalsLock` for process-wide unrecognized CLI args.
nonisolated(unsafe) private var globalExtraArgsValue: [String] = []

public func setAppId(_ id: String) {
    toolingGlobalsLock.withLock {
        if globalAppIdValue == nil {
            globalAppIdValue = id
        }
    }
}

func currentAppId() -> String? {
    toolingGlobalsLock.withLock { globalAppIdValue }
}

public func extraArgs() -> [String] {
    toolingGlobalsLock.withLock { globalExtraArgsValue }
}

public func isHeadless() -> Bool {
    false
}

public func run<S>(_ spec: AppSpec<S>) {
    App.new(spec).run()
}

public func runWith<S>(_ spec: AppSpec<S>, _ configure: (App<S>) -> App<S>) {
    configure(App.new(spec)).run()
}
