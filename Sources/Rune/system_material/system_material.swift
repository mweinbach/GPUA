// Ported from: crates/rune/src/system_material/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! System backdrop materials (`El.material` / `El.systemMaterial`): the platform blurs what is
//! behind the window under an element's rounded rect. On macOS a native view per material sits
//! under the transparent Metal layer and moves in the same Core Animation transaction as the
//! drawable, so the material, Rune's shadow and the content on top present together. Everywhere
//! else, in opaque windows and in headless renders, the element's fill (or a neutral tint)
//! stands in.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#endif

import RuneMotion

/// Native material views per window. Elements past this many draw their fallback instead.
public let MAX_NATIVE_MATERIALS: Int = 4

/// A backdrop material the system composites behind a window.
public enum SystemMaterial: Sendable, Equatable, Hashable {
    /// Liquid Glass (`NSGlassEffectView`, regular style) on macOS 26 and later; the popover
    /// material on earlier macOS.
    case glass
    /// The popover vibrancy material (`NSVisualEffectView`, `.popover`, behind window).
    case popover
    // PORT NOTE: Additional AppKit vibrancy materials retained for `El.material(_:)` compatibility.
    case sidebar
    case hudWindow
    case menu
    case underWindowBackground
    case titlebar

    public static let Glass: SystemMaterial = .glass
    public static let Popover: SystemMaterial = .popover
    public static let Sidebar: SystemMaterial = .sidebar
    public static let HudWindow: SystemMaterial = .hudWindow
    public static let Menu: SystemMaterial = .menu
    public static let UnderWindowBackground: SystemMaterial = .underWindowBackground
    public static let Titlebar: SystemMaterial = .titlebar
}

/// One material element as built this frame, in physical pixels like the instances.
public struct MaterialDraw: Sendable, Equatable {
    public var id: NodeId
    public var material: SystemMaterial
    /// `x, y, width, height` in physical pixels.
    public var rect: [Float]
    /// Corner radius in physical pixels, already clamped to half the shorter side.
    public var radius: Float
    /// Continuous corners (`El.continuousCorners`).
    public var continuous: Bool
    /// The element's effective opacity, ancestors included.
    public var opacity: Float

    public init(
        id: NodeId,
        material: SystemMaterial,
        rect: [Float],
        radius: Float,
        continuous: Bool,
        opacity: Float
    ) {
        self.id = id
        self.material = material
        self.rect = rect
        self.radius = radius
        self.continuous = continuous
        self.opacity = opacity
    }

    /// The native view's frame (`x, y, width, height` from the top left) and corner radius, in points.
    public func points(_ scale: Float) -> ([Double], Double) {
        let s = Double(max(scale, 1e-3))
        let pts = rect.map { Double($0) / s }
        return (pts, Double(radius) / s)
    }
}

/// Which existing view each draw takes: the view that showed the same element, else a free view
/// of the same material, else `nil` (the caller makes one). `views` holds each view's material
/// and the element it showed last; `draws` each draw's material and element.
func assignMaterialViews(
    _ views: [(SystemMaterial, NodeId?)],
    _ draws: [(SystemMaterial, NodeId)]
) -> [Int?] {
    var taken = [Bool](repeating: false, count: views.count)
    var out = [Int?](repeating: nil, count: draws.count)

    for (slotIdx, draw) in draws.enumerated() {
        let (material, id) = draw
        if let v = (0..<views.count).first(where: { !taken[$0] && views[$0].0 == material && views[$0].1 == id }) {
            taken[v] = true
            out[slotIdx] = v
        }
    }
    for (slotIdx, draw) in draws.enumerated() {
        if out[slotIdx] != nil { continue }
        let (material, _) = draw
        if let v = (0..<views.count).first(where: { !taken[$0] && views[$0].0 == material }) {
            taken[v] = true
            out[slotIdx] = v
        }
    }
    return out
}

/// The Metal layer's `presentsWithTransaction`, which native materials, a moving window frame
/// and a live resize all need. One owner, so none turns it off under another.
struct PresentFlag: Sendable, Equatable {
    private var movingFlag: Bool = false
    private var materialsFlag: Bool = false
    private var liveFlag: Bool = false
    private var writtenFlag: Bool = false

    init() {}

    /// Whether the layer presents with transactions.
    func written() -> Bool {
        writtenFlag
    }

    /// A window frame animation started or stopped. Returns the value to write when it changed.
    mutating func moving(_ on: Bool) -> Bool? {
        movingFlag = on
        return write()
    }

    /// Native materials synced with the drawable switched on or off. Returns the value to write when it changed.
    mutating func materials(_ on: Bool) -> Bool? {
        materialsFlag = on
        return write()
    }

    /// The user started or stopped dragging the window's edge. Returns the value to write when it changed.
    mutating func live(_ on: Bool) -> Bool? {
        liveFlag = on
        return write()
    }

    private mutating func write() -> Bool? {
        let on = movingFlag || materialsFlag || liveFlag
        guard on != writtenFlag else { return nil }
        writtenFlag = on
        return on
    }
}

/// One corner radius for a rect: native materials take a single radius, so this uses the
/// largest corner, clamped to half the shorter side as Rune's own rounded rects are.
func clampMaterialRadius(_ radii: [Float], _ width: Float, _ height: Float) -> Float {
    let largest = radii.reduce(Float(0.0)) { max($0, $1) }
    return max(min(largest, min(width, height) * 0.5), 0.0)
}

/// What a material element paints in Rune's own surface when no native view backs it: its
/// fill, or a neutral tint close to the material's average look when it has none.
func fallbackMaterialFill(_ fill: Color, _ dark: Bool) -> Color {
    if fill.a > 0.0 { return fill }
    if dark {
        return Color(0.16, 0.16, 0.17, 0.94)
    } else {
        return Color(0.96, 0.96, 0.97, 0.94)
    }
}

/// How the shell hosts materials, from `RUNE_SYSTEM_MATERIAL`: unset for native views synced
/// with the drawable; `legacy` forces the pre-26 `NSVisualEffectView` path; `unsynced` moves
/// native views outside the drawable's transaction (to compare); `off` draws the fallback.
enum SystemMaterialMode: Sendable, Equatable {
    case synced
    case legacy
    case unsynced
    case off

    static func parse(_ value: String?) -> SystemMaterialMode {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .synced
        }
        switch trimmed {
        case "legacy": return .legacy
        case "unsynced": return .unsynced
        case "off", "0": return .off
        default: return .synced
        }
    }

    static func fromEnv() -> SystemMaterialMode {
        #if os(WASI)
        return .off
        #else
        guard let raw = getenv("RUNE_SYSTEM_MATERIAL") else { return .synced }
        return parse(String(cString: raw))
        #endif
    }
}

/// Namespace mirroring `crate::system_material` helpers.
enum system_material {
    typealias Mode = SystemMaterialMode

    static func assign(
        _ views: [(SystemMaterial, NodeId?)],
        _ draws: [(SystemMaterial, NodeId)]
    ) -> [Int?] {
        assignMaterialViews(views, draws)
    }

    static func clampRadius(_ radii: [Float], _ width: Float, _ height: Float) -> Float {
        clampMaterialRadius(radii, width, height)
    }

    static func fallbackFill(_ fill: Color, _ dark: Bool) -> Color {
        fallbackMaterialFill(fill, dark)
    }
}
