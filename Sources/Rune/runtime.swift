// Ported from: crates/rune/src/runtime.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The retained tree: view -> keyed nodes -> Taffy layout at the target state -> `RuneMotion` Scene.
//! Animation samples tracks at frame time; it never re-runs view functions.

import RuneMotion
import Taffy

public enum TitlebarAction: Sendable, Equatable {
    case drag
    case doubleClick
    case zoom
    case minimize
    case none
}

public struct FrameStats: Sendable, Equatable {
    public var instances: Int
    public var layers: Int
    public var animating: Bool
    public var commits: Int
    public var glyphs: Int
    public var shaped: Int

    public init(
        instances: Int = 0,
        layers: Int = 0,
        animating: Bool = false,
        commits: Int = 0,
        glyphs: Int = 0,
        shaped: Int = 0
    ) {
        self.instances = instances
        self.layers = layers
        self.animating = animating
        self.commits = commits
        self.glyphs = glyphs
        self.shaped = shaped
    }
}

public struct SelectedText: Sendable, Equatable {
    public var path: String
    public var key: String?
    public var range: Range<Int>
    public var text: String
    public var len: Int
    public var whole: Bool

    public init(
        path: String,
        key: String? = nil,
        range: Range<Int>,
        text: String,
        len: Int = 0,
        whole: Bool = false
    ) {
        self.path = path
        self.key = key
        self.range = range
        self.text = text
        self.len = len
        self.whole = whole
    }
}

public struct TextSelection: Sendable, Equatable {
    public var items: [SelectedText]
    public var copied: String
    public var backward: Bool

    public init(items: [SelectedText] = [], copied: String = "", backward: Bool = false) {
        self.items = items
        self.copied = copied
        self.backward = backward
    }
}

public struct SelectionChange: Sendable, Equatable {
    public var selection: TextSelection?
    public var was: TextSelection?
    public var dragging: Bool

    public init(
        selection: TextSelection? = nil,
        was: TextSelection? = nil,
        dragging: Bool = false
    ) {
        self.selection = selection
        self.was = was
        self.dragging = dragging
    }
}

public struct MotionElement: Sendable, Equatable {
    public var id: RuneMotion.NodeId
    public var parent: Int?
    public var path: String
    public var key: String?
    public var rect: [Float]
    public var visible: [Float]
    public var opacity: Float
    public var scale: Float
    public var loopPhase: Double?
    public var textHash: UInt64
    public var flags: UInt16

    public init(
        path: String,
        key: String? = nil,
        rect: [Float] = [0, 0, 0, 0],
        opacity: Float = 1.0,
        id: RuneMotion.NodeId = RuneMotion.NodeId(0),
        parent: Int? = nil,
        visible: [Float] = [0, 0, 0, 0],
        scale: Float = 1.0,
        loopPhase: Double? = nil,
        textHash: UInt64 = 0,
        flags: UInt16 = 0
    ) {
        self.id = id
        self.parent = parent
        self.path = path
        self.key = key
        self.rect = rect
        self.visible = visible
        self.opacity = opacity
        self.scale = scale
        self.loopPhase = loopPhase
        self.textHash = textHash
        self.flags = flags
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
    public var t: Double = 0.0
    public var reducedMotion: Bool = false
    public var timeScale: Float = 1.0
    public var poll: ((inout S, Double, inout Tx) -> Bool)? = nil
    public var clock: Double = 0.0
    public var onKey: ((inout S, KeyEvent, inout Tx) -> Bool)? = nil
    public var onIme: ((inout S, Ime, inout Tx) -> Bool)? = nil
    public var instances: [Instance] = []
    public var layers: [LayerSpec] = []
    public var marks: [UInt32] = []
    public var trackMarks: Bool = false
    public var animating: Bool = false
    public var settled: Bool = false
    public var stats: FrameStats = FrameStats()
    public var imeArea: [Float]? = nil
    public var ambient: Float? = nil
    public var doubleClickInterval: Double = 0.5
    public var helpDelay: Double = 0.5
    public var fitHeight: Bool = false
    public var windowResting: Bool = false
    public var windowFrame: FrameRequest? = nil
    public var keyWarnings: [String]? = nil
    var matched: [(String, RuneMotion.NodeId)] = []

    // Internal system & host state
    var srgbBlend: Bool = false
    var systemAccent: SystemAccent = .DEFAULT
    var systemReducedMotion: Bool = false
    var titlebarInset: Float = 0.0
    var nativeTitlebarBand: Float = 0.0
    var pendingTitlebarAction: TitlebarAction? = nil
    var chrome: Chrome = .DEFAULT
    var tabVisitsControls: Bool = false
    var windowVisible: Bool = true
    var windowFocused: Bool? = nil

    // Retained tree, memo, paint & layout caches
    var memo: MemoCache = MemoCache()
    var nodes: [Node] = []
    var exitingNodes: [ExitingNode] = []
    var exitMask: ExitMask = ExitMask()
    var pixelSnap: PixelSnapGlides = PixelSnapGlides()
    var layerCache: LayerCacheStore = LayerCacheStore()
    var surfaces: [SurfaceDraw] = []
    var keyIndex: KeyIndex = KeyIndex()
    var applyScratch: ApplyScratch = ApplyScratch()
    var dirty: Bool = true
    var hasCommittedOnce: Bool = false
    var commitWhy: UInt16 = CommitWhy.INIT
    var pendingCommitWhy: UInt16 = CommitWhy.INIT
    var commitsThisFrame: UInt32 = 0
    var totalCommits: UInt64 = 0
    var frameIndex: UInt64 = 0
    var lastDt: Double = 1.0 / 60.0
    var lastWebTimestampSec: Double? = nil
    var viewportStepped: Bool = false
    var fitAsked: Float? = nil
    var lastCommittedScale: Float = .nan
    var lastCommittedSrgbBlend: Bool? = nil
    var lastCommittedLayoutReadKeys: Set<String> = []
    var lastCommittedCaretRead: Bool = false
    var lastCommittedLayoutPredicates: [LayoutWithCheck] = []
    var rootFillsViewportWidth: Bool = true
    var rootFillsViewportHeight: Bool = true

    // One-shot transaction motion overrides for next commit
    var pendingInstantCommit: Bool = false
    var pendingSettleCommit: Bool = false
    var pendingMotionSpring: Spring? = nil
    var pendingMotionCurve: Anim? = nil
    var pendingColorSpring: Spring? = nil

    // Text shaping & layout caches
    public var glyphCache: GlyphReplayCache = GlyphReplayCache()
    var textLayoutCache: [TextLayoutCacheKey: RtTextLayout] = [:]
    var previousShapedByPath: [String: String] = [:]
    var lastLayoutSnapshot: LayoutReadSnapshot = LayoutReadSnapshot()
    var lastLayoutDiagnostics: [LayoutDiagnostic] = []
    var lastMemoStats: MemoStats = MemoStats()

    // Scroll & virtualized lists
    var scrolls: [String: ScrollState] = [:]
    var scrollsX: [String: ScrollXState] = [:]
    var scrollWatches: [ScrollWatchEntry<S>] = []
    var queuedScrollReveals: [ScrollReveal] = []
    var queuedScrollBottoms: [(String, Bool)] = []
    var queuedScrollPages: [(String, Int32)] = []
    var queuedScrollOffsets: [ScrollRequest] = []
    var queuedKeepOnScreen: [String] = []

    // Render-side motion tracks (growth, reveals, loops, live, flights, timers, idle)
    var growthTracks: [RuneMotion.NodeId: GrowTrack] = [:]
    var growAccumulator: Float = 0.0
    var reveals: [String: RevealState] = [:]
    var loops: [RuneMotion.NodeId: LoopEntry] = [:]
    var groupFading: Set<RuneMotion.NodeId> = []
    var liveClockToken: LiveClockToken = LiveClockToken()
    var liveWake: LiveWake = LiveWake({})
    var liveDirty: Bool = false
    var liveOnlySkips: UInt64 = 0
    var liveOnlyCheck: Bool = true
    var liveOnlyWarningsList: [String] = []
    var lastCommitClock: Double = 0.0
    var liveNodeBindings: [RuneMotion.NodeId: LiveNodeEntry] = [:]
    var queuedTextFlights: [(String, String)] = []
    var pendingCapturedFlights: [PendingTextFlightCapture] = []
    var activeTextFlights: [TextFlight] = []
    var pendingLaunchRects: [String: RuneMotion.Rect] = [:]
    var timerWakes: TimerWakeQueue = TimerWakeQueue()
    var pendingWakes: [Double] = []
    var idleMeter: IdleMeter = IdleMeter()
    var eventLog: EventLog = EventLog()

    // Focus, pointer, drag, keyboard, IME, popups, dialogs, and window requests
    var focusedPath: String? = nil
    var focusVisible: Bool = false
    var pendingFocusKey: String? = nil
    var focusReturnTarget: String? = nil
    var hoveredPaths: Set<String> = []
    var pressedPath: String? = nil
    var secondaryPressedPath: String? = nil
    var pointerLeftInCapture: Bool = false
    var pressedLinkTarget: (String, Int)? = nil
    var lastPointer: (Float, Float)? = nil
    var currentCursor: Cursor = .default
    var heldMods: Mods = Mods()
    var heldModifierKeys: Set<Modifier> = []
    var clickTracker: ClickTracker = ClickTracker()
    var gestureState: ActiveGestureState = ActiveGestureState()

    var activeDragNodePath: String? = nil
    var activeDragOrigin: (Float, Float) = (0, 0)
    var activeDragPrev: (Float, Float) = (0, 0)
    var activeDragStartLocal: (Float, Float) = (0, 0)
    var activeDragData: Float = 0.0
    var activeDragClicks: UInt32 = 1
    var activeDragMoved: Bool = false

    var activeInputDragPath: String? = nil
    var activeInputClickMode: UInt32 = 1
    var inputScrollOffsets: [String: Float] = [:]
    var imeActive: Bool = false
    var appImeComposing: Bool = false
    var editAccessors: [String: (States, (inout TextEdit) -> Void) -> Bool] = [:]

    var popupDismissHandlers: [String: (inout S, inout Tx) -> Void] = [:]
    var linkHandler: ((inout S, String, inout Tx) -> Void)? = nil

    var helpHoverPath: String? = nil
    var helpHoverText: String? = nil
    var helpHoverRect: [Float] = [0, 0, 0, 0]
    var helpHoverPointer: (Float, Float)? = nil
    var helpHoverStart: Double? = nil
    var helpShownAt: Double? = nil

    var dropHoverPoint: (Float, Float)? = nil
    var lastDroppedPayload: DroppedPayload? = nil
    var pendingFileDialog: FileDialogRequest? = nil
    var pendingWindowRequests: WindowRequests = WindowRequests()
    var pendingDragOut: PendingDragOut? = nil
    var activeDragOutCompletion: ((States, DragOutcome, inout Tx) -> Void)? = nil

    // Static & virtualized text selection
    var staticSelectionAnchor: (String, Int)? = nil
    var staticSelectionFocus: (String, Int)? = nil
    var selectionScopeNodeIdx: Int? = nil
    var lastPickedSelectionUnitPath: String? = nil
    var isDraggingTextSelection: Bool = false
    var lastSelectionDragging: Bool = false
    var selectionChangeHandler: ((inout S, SelectionChange, inout Tx) -> Void)? = nil
    var virtualSelection: VirtualSelectionStore = VirtualSelectionStore()

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
        let sc = Scene()
        sc.setPixelScale(max(env.scale, 0.001))
        self.scene = sc
        self.env = env
        self.viewport = viewport
    }

    public static func new(
        _ state: S,
        _ view: @escaping (S, Cx<S>) -> El,
        _ viewport: (Float, Float) = (800, 600),
        _ env: Env = Env()
    ) -> Runtime<S> {
        Runtime(state, view, viewport, env)
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

    /// Mutate `state` outside any input handler; marks the next frame dirty unless `tx.liveOnly()` is set.
    public func update(_ f: (inout S, inout Tx) -> Void) {
        _ = updateIf { s, tx in
            f(&s, &tx)
            return true
        }
    }

    /// Conditional `update` where `f` returns whether view-observable state changed.
    @discardableResult
    public func updateIf(_ f: (inout S, inout Tx) -> Bool) -> Bool {
        var tx = newTx(fromInput: false)
        let changed = f(&state, &tx)
        if changed {
            applyTx(&tx, why: CommitWhy.UPDATE)
        } else {
            var sideTx = tx
            sideTx.liveOnlyFlag = true
            applyTx(&sideTx, why: 0)
        }
        return stale()
    }
}
