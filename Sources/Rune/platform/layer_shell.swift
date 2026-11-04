// Ported from: crates/rune/src/platform/layer_shell.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A Wayland layer-shell surface for overlays (`zwlr_layer_shell_v1`).
//! The surface reserves no space; input regions and the rendered buffer share a commit.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

enum LayerShellInput: Sendable, Equatable {
    case move(Float, Float)
    case leave
    case button(Bool)
    case secondary(Bool)
    case key(KeyEvent)
    case keyUp(KeyEvent)
}

/// What the overlay needs to know after the compositor talked to the surface.
struct LayerShellChanges: Sendable {
    var size: (UInt32, UInt32)?
    var input: [LayerShellInput]
    var scale: Int32?
    var closed: Bool
}

struct LayerShellAnchor: OptionSet, Sendable, Equatable {
    let rawValue: UInt32
    static let top = LayerShellAnchor(rawValue: 1 << 0)
    static let bottom = LayerShellAnchor(rawValue: 1 << 1)
    static let left = LayerShellAnchor(rawValue: 1 << 2)
    static let right = LayerShellAnchor(rawValue: 1 << 3)
}

/// Computed layer-shell anchor, size and margins for a placement request.
struct LayerShellPlacementGeometry: Sendable, Equatable {
    var width: UInt32
    var height: UInt32
    var anchor: LayerShellAnchor
    var margins: (top: Int32, right: Int32, bottom: Int32, left: Int32)

    static func == (lhs: LayerShellPlacementGeometry, rhs: LayerShellPlacementGeometry) -> Bool {
        lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.anchor == rhs.anchor
            && lhs.margins == rhs.margins
    }
}

func computeLayerShellPlacement(
    _ at: OverlayPlacementSpec,
    _ options: OverlayOptions
) -> LayerShellPlacementGeometry {
    switch options.placement {
    case .fullScreen:
        return LayerShellPlacementGeometry(
            width: 0,
            height: 0,
            anchor: [.top, .bottom, .left, .right],
            margins: (0, 0, 0, 0)
        )
    case .rect(let x, let y, let width, let height):
        return LayerShellPlacementGeometry(
            width: UInt32(max(width.rounded(.up), 1.0)),
            height: UInt32(max(height.rounded(.up), 1.0)),
            anchor: [.top, .left],
            margins: (Int32(y.rounded()), 0, 0, Int32(x.rounded()))
        )
    default:
        break
    }

    let resolved: OverlayPlacementSpec
    if case .edge(let edge, let margin, let align, let inset) = options.placement {
        resolved = OverlayPlacementSpec(size: at.size, edge: edge, margin: margin, align: align, inset: inset)
    } else {
        resolved = at
    }
    let margin = Int32(resolved.margin.rounded())
    let inset = Int32(resolved.inset.rounded())
    let vertical: LayerShellAnchor
    let top: Int32
    let bottom: Int32
    switch resolved.edge {
    case .top:
        vertical = .top
        top = margin
        bottom = 0
    case .bottom:
        vertical = .bottom
        top = 0
        bottom = margin
    }
    let horizontal: LayerShellAnchor
    let left: Int32
    let right: Int32
    switch resolved.align {
    case .start:
        horizontal = .left
        left = inset
        right = 0
    case .center:
        horizontal = []
        left = 0
        right = 0
    case .end:
        horizontal = .right
        left = 0
        right = inset
    }
    return LayerShellPlacementGeometry(
        width: UInt32(max(resolved.size.0.rounded(.up), 1.0)),
        height: UInt32(max(resolved.size.1.rounded(.up), 1.0)),
        anchor: vertical.union(horizontal),
        margins: (top, right, bottom, left)
    )
}

/// Wayland `zwlr_layer_shell_v1` overlay surface wrapper.
// PORT NOTE: Wayland C client libraries (`wayland-client`, `wayland-protocols-wlr`) are not linked in SwiftPM without an ADR;
// `LayerSurface.new` returns `nil` when Wayland layer-shell is unavailable, triggering upstream's standard XWayland / unavailable fallback.
final class LayerSurface {
    private var options: OverlayOptions
    private var configuredSizeValue: (UInt32, UInt32)?
    private var lastRegions: [[Int32]]? = []
    private var shownCursor: Cursor? = nil
    private var pendingInputs: [LayerShellInput] = []
    private var pendingScale: Int32? = nil
    private var isClosed: Bool = false
    private let surfaceId: UInt32

    private init(options: OverlayOptions, configuredSize: (UInt32, UInt32), surfaceId: UInt32) {
        self.options = options
        self.configuredSizeValue = configuredSize
        self.surfaceId = surfaceId
    }

    static func new(
        namespace: String,
        at: OverlayPlacementSpec,
        interactive: Bool,
        options: OverlayOptions,
        outputId: UInt32?,
        wake: Waker?
    ) -> LayerSurface? {
        _ = namespace
        _ = at
        _ = interactive
        _ = options
        _ = outputId
        _ = wake
        return nil
    }

    func place(_ at: OverlayPlacementSpec) {
        _ = computeLayerShellPlacement(at, options)
    }

    func configuredSize() -> (UInt32, UInt32)? {
        configuredSizeValue
    }

    func inputRegions(_ regions: [[Float]], interactive: Bool) {
        let next: [[Int32]]?
        switch options.input.resolved(interactive) {
        case .all:
            next = nil
        case .regions:
            next = regions.compactMap { (r: [Float]) -> [Int32]? in
                guard r.count >= 4 else { return nil }
                let x = Int32(r[0].rounded(.down))
                let y = Int32(r[1].rounded(.down))
                let w = Int32(r[2].rounded(.up)) - x
                let h = Int32(r[3].rounded(.up)) - y
                return (w > 0 && h > 0) ? [x, y, w, h] : nil
            }
        case .legacy, .none:
            next = []
        }
        if lastRegions == next { return }
        lastRegions = next
    }

    func setInput(_ input: OverlayInput) {
        options.input = input
    }

    func requestKeys() -> Bool {
        false
    }

    func supportsKeys() -> Bool {
        false
    }

    func setCursor(_ want: Cursor) {
        if shownCursor == want { return }
        shownCursor = want
    }

    func commit() {}

    func setBufferScale(_ scale: Int32) {
        _ = scale
    }

    func dispatch() -> LayerShellChanges {
        let size = configuredSizeValue
        configuredSizeValue = nil
        let inp = pendingInputs
        pendingInputs.removeAll()
        let scale = pendingScale
        pendingScale = nil
        return LayerShellChanges(size: size, input: inp, scale: scale, closed: isClosed)
    }

    deinit {
        waylandActivationForget(surfaceId: surfaceId)
    }
}
