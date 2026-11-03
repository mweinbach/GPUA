// Ported from: crates/rune/src/runtime/types.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Retained node representation, text line/layout structures, scroll/reveal/loop/stack states,
//! exiting node snapshots, and FNV-1a `NodeId` hashing.

import RuneMotion
import Taffy

/// Deterministic 64-bit FNV-1a hash mapping a node's keyed path to a `RuneMotion.NodeId`.
func fnvNodeId(_ path: String) -> RuneMotion.NodeId {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in path.utf8 {
        h ^= UInt64(b)
        h &*= 0x0000_0100_0000_01b3
    }
    if h == 0 {
        h = 1
    }
    return RuneMotion.NodeId(h)
}

func fnvTextHash(_ text: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in text.utf8 {
        h ^= UInt64(b)
        h &*= 0x0000_0100_0000_01b3
    }
    return h
}

/// One laid-out line of text in node-local points.
struct RtTextLine: Sendable, Equatable {
    var byteStart: Int
    var byteEnd: Int
    var x: Float
    var y: Float
    var width: Float
    var height: Float
    var truncated: Bool
    var glyphs: [RtGlyph]
}

/// One positioned character/cluster glyph in node-local points.
struct RtGlyph: Sendable, Equatable {
    var byteOffset: Int
    var byteLen: Int
    var x: Float
    var y: Float
    var advance: Float
    var height: Float
    var color: Color
    var bg: Color?
    var bgPad: Float
    var underline: Color?
    var alpha: Float
    var isEllipsis: Bool
}

/// Cached laid-out text block for a committed node.
struct RtTextLayout: Sendable, Equatable {
    var text: String
    var displayText: String
    var lines: [RtTextLine]
    var width: Float
    var height: Float
    var lineHeight: Float
    var truncated: Bool
    var truncatedFadeWidth: Float
    var caseSource: TextCaseSource?
    var caseUp: Bool
}

struct GlyphReplayLineKey: Hashable, Sendable {
    var nodeId: RuneMotion.NodeId
    var lineIdx: Int
    var textHash: UInt64
    var widthBits: UInt32
    var sizeBits: UInt32
}

struct CachedReplayGlyph: Sendable, Equatable {
    var byteOffset: UInt32
    var relX: Float
    var relY: Float
    var gw: Float
    var gh: Float
    var color: Color
    var alpha: Float
}

/// Per-line flattened glyph replay cache so scrolling back over already-drawn paragraphs skips re-walking lines.
public struct GlyphReplayCache: Sendable {
    public internal(set) var flattened: UInt64 = 0
    var lines: [GlyphReplayLineKey: [CachedReplayGlyph]] = [:]

    public init() {}

    public func len() -> Int {
        lines.count
    }

    public var isEmpty: Bool {
        lines.isEmpty
    }

    mutating func prune(keeping ids: Set<RuneMotion.NodeId>) {
        lines = lines.filter { ids.contains($0.key.nodeId) }
    }
}

/// Retained vertical scroll state per keyed scroll container.
struct ScrollState: Sendable {
    var offset: Float = 0.0
    var target: Float = 0.0
    var vel: Float = 0.0
    var maxScroll: Float = 0.0
    var viewportH: Float = 0.0
    var contentH: Float = 0.0
    var stuckBottom: Bool = false
    var stickBottomSpec: Bool = false
    var spring: Spring? = nil
    var wheelTime: Double = -100.0
    var anchorKey: String? = nil
    var anchorRelY: Float = 0.0
    var overscroll: Float = 0.0
    var thumbVisibleUntil: Double = -100.0
    var direct: Bool = false
    var scrolling: Bool = false
    var hoverHeld: Bool = false

    var isMoving: Bool {
        abs(target - offset) > 0.05 || abs(vel) > 1.0 || abs(overscroll) > 0.25
    }

    var isScrollingOrMoving: Bool {
        direct || scrolling || isMoving
    }
}

/// Retained horizontal scroll state per keyed scroll container.
struct ScrollXState: Sendable {
    var offset: Float = 0.0
    var target: Float = 0.0
    var vel: Float = 0.0
    var maxScroll: Float = 0.0
    var viewportW: Float = 0.0
    var contentW: Float = 0.0
    var spring: Spring? = nil
    var overscroll: Float = 0.0

    var isMoving: Bool {
        abs(target - offset) > 0.05 || abs(vel) > 1.0 || abs(overscroll) > 0.25
    }
}

/// Reveal / content-slide state for streaming text or fold glides.
struct RevealState: Sendable {
    var progress: Float = 1.0
    var target: Float = 1.0
    var lastTextLen: Int = 0
}

/// Active looping animation entry on a node.
struct LoopEntry: Sendable {
    var spec: LoopSpec
    var startTime: Double
    var phase: Double = 0.0
    var sleeping: Bool = false
}

/// Retained stack / z-order state for overlapping animated siblings.
struct StackState: Sendable {
    var lastTouchedFrame: UInt64 = 0
    var zBoost: Int = 0
}

/// Snapshot of a node that was removed from the view tree while its exit transition plays out in `Scene`.
struct ExitingNode {
    var nodeId: RuneMotion.NodeId
    var path: String
    var key: String?
    var parentPath: String?
    var parentNodeId: RuneMotion.NodeId?
    var role: String
    var label: String?
    var vis: Visual
    var textSpec: TextSpec?
    var textLayout: RtTextLayout?
    var scale: Float
    var localRect: [Float]
    var worldRect: [Float]
    var clipRect: [Float]
    var clipRadii: Corners
    var children: [ExitingNode]
}

/// Dispatchable action resolved during input handling.
enum RtAction {
    case none
    case press(Int)
    case secondaryPress(Int, PointerEvent)
    case focus(String?)
    case toggleLink(Int, Int)
}

/// One flattened, laid-out node in the retained tree for the current commit.
struct Node {
    var index: Int
    var nodeId: RuneMotion.NodeId
    var taffyId: Taffy.NodeId?
    var path: String
    var key: String?
    var rawKey: String?
    var parent: Int?
    var children: [Int] = []

    var traceName: String?
    var traceNamespace: (String, String)?
    var role: String
    var label: String?
    var helpText: String?
    var helpCut: Bool

    var style: Taffy.Style<String>
    var vis: Visual
    var focusSpec: FocusSpec
    var loopingSpec: LoopSpec?
    var liveBindings: [LiveBound]
    @ColdOpt var textSpec: TextSpec? = nil
    @ColdOpt var textLayout: RtTextLayout? = nil
    var aboveAnchor: Anchor?
    var resolvedAnchorSide: Side?
    var motionSpring: Spring?
    var opacityMotionAnim: Anim?
    var animateLayout: Bool
    var instantChanges: Bool
    var transitionSpec: Transition?
    var matchedId: String?
    var scrollSpec: ScrollSpec?
    var scrollXEnabled: Bool = false
    var growthSpec: GrowthSpec?
    var streaming: Bool
    var whole: Bool
    var glideSpec: FoldGlide?
    @ColdOpt var input: InputSpec? = nil
    var windowDrag: Bool
    var imeCursor: Bool
    var scale: Float
    var cumulativeScale: Float = 1.0
    var timeScale: Float
    var cumulativeTimeScale: Float = 1.0
    var materialSpec: SystemMaterial?
    var aspectFit: Float
    var selectionGroup: Bool
    var a11yLevel: UInt32?
    var a11yExpanded: Bool?
    var a11ySecure: Bool
    var inert: Bool
    var virtualExtent: Bool = false
    var stickyTop: Float? = nil
    var stuckAmount: Float = 0.0
    var rotate: Float = 0.0

    // Handlers copied from `El`
    var onPressHandler: ((States, inout Tx) -> Void)?
    var onSecondaryPressHandler: ((States, PointerEvent, inout Tx) -> Void)?
    var onKeyHandler: ((States, KeyEvent, inout Tx) -> Bool)?
    var onDragHandler: ((States, inout Drag, inout Tx) -> Void)?
    var onHoverHandler: ((States, Bool, inout Tx) -> Void)?

    // Computed layout geometry
    /// Local layout rect `[x, y, w, h]` relative to parent node.
    var localRect: [Float] = [0, 0, 0, 0]
    /// Target world rect `[x, y, w, h]` before scroll/motion offsets.
    var layoutRect: [Float] = [0, 0, 0, 0]
    /// Presented world rect `[x, y, w, h]` as of the latest frame (including scroll & scene pose).
    var presentedRect: [Float] = [0, 0, 0, 0]
    /// Visible clipped rect `[x, y, w, h]` inside ancestor clips/scrollports.
    var visibleRect: [Float] = [0, 0, 0, 0]
    /// Active ancestor clip `[x0, y0, x1, y1]` in world points.
    var clipBounds: [Float] = NO_CLIP
    var clipRadii: Corners = .zero
    var scrollAncestor: Int? = nil
    var scrollOffsetApplied: [Float] = [0, 0]
    var inGrowingRow: Bool = false
    var turn: Turn = .none
    var groupOpacityAccum: Float = 1.0
}
