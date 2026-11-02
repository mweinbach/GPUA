// Ported from: crates/rune/src/runtime.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! The retained tree: view -> keyed nodes -> Taffy layout at the target state -> `RuneMotion` Scene.

import RuneMotion
import Taffy

public enum TitlebarAction: Sendable, Equatable {
    case zoom
    case minimize
    case none
}

public struct FrameStats: Sendable, Equatable {
    public var instances: Int
    public var layers: Int
    public var animating: Bool

    public init(instances: Int = 0, layers: Int = 0, animating: Bool = false) {
        self.instances = instances
        self.layers = layers
        self.animating = animating
    }
}

public struct SelectedText: Sendable, Equatable {
    public var path: String
    public var key: String?
    public var range: Range<Int>
    public var text: String

    public init(path: String, key: String? = nil, range: Range<Int>, text: String) {
        self.path = path
        self.key = key
        self.range = range
        self.text = text
    }
}

public struct TextSelection: Sendable, Equatable {
    public var items: [SelectedText]
    public var copied: String

    public init(items: [SelectedText] = [], copied: String = "") {
        self.items = items
        self.copied = copied
    }
}

public struct SelectionChange: Sendable, Equatable {
    public var selection: TextSelection?

    public init(selection: TextSelection? = nil) {
        self.selection = selection
    }
}

public struct MotionElement: Sendable, Equatable {
    public var path: String
    public var key: String?
    public var rect: [Float]
    public var opacity: Float

    public init(path: String, key: String? = nil, rect: [Float] = [0, 0, 0, 0], opacity: Float = 1.0) {
        self.path = path
        self.key = key
        self.rect = rect
        self.opacity = opacity
    }
}

struct ScrollReveal: Sendable, Equatable {
    var key: String
    var center: Bool
    var animated: Bool
}

struct ScrollRequest: Sendable, Equatable {
    var key: String
    var x: Float?
    var y: Float?
    var animated: Bool
    var spring: Spring?
}

/// Compute anchored overlay top-left `(x, y)` in `window` `(w, h)` next to `trigger` `[x0, y0, x1, y1]`.
func anchorPosition(
    _ anchor: Anchor,
    _ trigger: [Float],
    _ size: (Float, Float),
    _ window: (Float, Float)
) -> (Float, Float) {
    let margin: Float = 8.0
    let (tw0, ty0, tw1, ty1) = (trigger[0], trigger[1], trigger[2], trigger[3])
    let (ow, oh) = size
    let (ww, wh) = window

    var side = anchor.side

    switch side {
    case .bottom:
        let fitsBelow = ty1 + anchor.gap + oh <= wh - margin
        let fitsAbove = ty0 - anchor.gap - oh >= margin
        if !fitsBelow && fitsAbove {
            side = .top
        }
    case .top:
        let fitsAbove = ty0 - anchor.gap - oh >= margin
        let fitsBelow = ty1 + anchor.gap + oh <= wh - margin
        if !fitsAbove && fitsBelow {
            side = .bottom
        }
    case .right:
        let fitsRight = tw1 + anchor.gap + ow <= ww - margin
        let fitsLeft = tw0 - anchor.gap - ow >= margin
        if !fitsRight && fitsLeft {
            side = .left
        }
    case .left:
        let fitsLeft = tw0 - anchor.gap - ow >= margin
        let fitsRight = tw1 + anchor.gap + ow <= ww - margin
        if !fitsLeft && fitsRight {
            side = .right
        }
    }

    var x: Float
    var y: Float
    switch side {
    case .top, .bottom:
        y = (side == .top) ? (ty0 - anchor.gap - oh) : (ty1 + anchor.gap)
        switch anchor.align {
        case .start: x = tw0
        case .center: x = (tw0 + tw1 - ow) * 0.5
        case .end: x = tw1 - ow
        }
    case .left, .right:
        x = (side == .left) ? (tw0 - anchor.gap - ow) : (tw1 + anchor.gap)
        switch anchor.align {
        case .start: y = ty0
        case .center: y = (ty0 + ty1 - oh) * 0.5
        case .end: y = ty1 - oh
        }
    }

    let maxX = max(margin, ww - margin - ow)
    let maxY = max(margin, wh - margin - oh)
    x = min(max(x, margin), maxX)
    y = min(max(y, margin), maxY)
    return (x, y)
}

/// Retained element runtime driving layout, motion tracks, input, and painter emission.
public final class Runtime<S> {
    public var state: S
    public let view: (S, Cx<S>) -> El
    public var text: TextSystem
    public var images: ImageAtlas
    public var scene: Scene
    public var env: Env
    public var viewport: (Float, Float)
    public var transparent: Bool = false
    var srgbBlend: Bool = true
    public var t: Double = 0.0
    public var reducedMotion: Bool = false
    public var timeScale: Float = 1.0
    public var poll: ((inout S, Double, inout Tx) -> Bool)? = nil
    public var clock: Double = 0.0
    public var onKey: ((inout S, KeyEvent, inout Tx) -> Bool)? = nil
    var memo: MemoCache = MemoCache()
    private var lastElements: [ElementInfo] = []
    private var dirty: Bool = true

    public init(
        _ state: S,
        _ view: @escaping (S, Cx<S>) -> El,
        _ viewport: (Float, Float) = (800, 600),
        _ env: Env = Env()
    ) {
        self.state = state
        self.view = view
        self.text = TextSystem()
        self.images = ImageAtlas()
        self.scene = Scene()
        self.env = env
        self.viewport = viewport
    }

    public static func withText(
        _ state: S,
        _ view: @escaping (S, Cx<S>) -> El,
        _ viewport: (Float, Float),
        _ env: Env,
        _ text: TextSystem
    ) -> Runtime<S> {
        let rt = Runtime(state, view, viewport, env)
        rt.text = text
        return rt
    }

    public func update(_ f: (inout S, inout Tx) -> Void) {
        var tx = Tx()
        f(&state, &tx)
        if !tx.liveOnlyFlag {
            dirty = true
        }
    }

    @discardableResult
    public func frame(_ dt: Double = 1.0 / 60.0) -> ([Instance], [LayerSpec]) {
        clock += dt
        t += dt * Double(timeScale)
        if let pollFn = poll {
            var tx = Tx()
            if pollFn(&state, clock, &tx) {
                dirty = true
            }
        }
        if dirty {
            commit()
            dirty = false
        }
        scene.setTime(t)
        return ([], [])
    }

    private func commit() {
        bumpCommitGeneration()
        let finishMemo = enterMemoScope(memo, env: env, reducedMotion: reducedMotion, srgbBlend: srgbBlend)
        let cx = Cx<S>(env: env, reducedMotion: reducedMotion, timeScale: timeScale)
        var root = view(state, cx)
        _ = finishMemo()
        var infos: [ElementInfo] = []
        flattenForInspection(&root, path: "root", parent: nil, out: &infos)
        lastElements = infos
    }

    private func flattenForInspection(_ el: inout El, path: String, parent: Int?, out: inout [ElementInfo]) {
        el.expandMemo()
        let idx = out.count
        let info = ElementInfo(
            path: path,
            key: el.key,
            role: el.roleName,
            label: el.labelText,
            text: el.textSpec?.value.content,
            rect: [0, 0, viewport.0, viewport.1],
            target: [0, 0, viewport.0, viewport.1],
            opacity: el.vis.opacity,
            scale: el.scaleValue,
            fill: el.vis.fill,
            textColor: el.textSpec?.value.color,
            parent: parent
        )
        out.append(info)
        for i in el.children.indices {
            let childKey = el.children[i].key ?? "\(i)"
            flattenForInspection(&el.children[i], path: "\(path)/\(childKey)", parent: idx, out: &out)
        }
    }

    public func elements() -> [ElementInfo] {
        if dirty {
            commit()
            dirty = false
        }
        return lastElements
    }

    public func elementAt(_ x: Float, _ y: Float) -> Picked? {
        for info in elements().reversed() {
            let r = info.rect
            if x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3] {
                return Picked(path: info.path, key: info.key)
            }
        }
        return nil
    }
}
