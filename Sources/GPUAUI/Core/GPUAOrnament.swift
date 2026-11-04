// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#elseif canImport(WASILibc)
import WASILibc
#endif

import GPUI
import Rune
import RuneKit

// MARK: - Variants & Sizes

/// Semantic visual variants modeled after [shadcn/ui](https://ui.shadcn.com).
public enum OrnamentVariant: String, Sendable, Equatable, Hashable, CaseIterable {
    case `default`
    case primary
    case secondary
    case outline
    case ghost
    case destructive
    case link
}

/// Standardized control height and typography density tiers.
public enum OrnamentSize: String, Sendable, Equatable, Hashable, CaseIterable {
    case xs
    case sm
    case md
    case lg
    case icon

    public var heightPx: Float {
        switch self {
        case .xs: return 24.0
        case .sm: return 30.0
        case .md: return 36.0
        case .lg: return 42.0
        case .icon: return 34.0
        }
    }

    public var horizontalPadPx: Float {
        switch self {
        case .xs: return 8.0
        case .sm: return 12.0
        case .md: return 16.0
        case .lg: return 22.0
        case .icon: return 0.0
        }
    }

    public var fontSizePx: Float {
        switch self {
        case .xs: return 11.5
        case .sm: return 12.5
        case .md: return 13.5
        case .lg: return 14.5
        case .icon: return 14.0
        }
    }

    public var iconSizePx: Float {
        switch self {
        case .xs: return 12.0
        case .sm: return 14.0
        case .md: return 15.0
        case .lg: return 16.0
        case .icon: return 16.0
        }
    }
}

// MARK: - Dual-Engine Protocol

/// Every ornament in ``GPUAUI`` conforms to ``GPUAOrnament``, rendering natively on **both**
/// ``GPUI`` (`IntoElement` / `AnyElement`) and ``Rune`` (`Rune.El` + root overlay layer).
public protocol GPUAOrnament: Sendable, GPUI.IntoElement where ElementType == GPUI.AnyElement {
    /// Builds a native ``GPUI/AnyElement`` styled with `theme`.
    func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement

    /// Builds a native ``Rune/El`` styled with `theme`, appending any floating overlays
    /// (popovers, menus, dialogs, tooltips, toasts) to `layer` so the root mounts them above siblings.
    func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El
}

extension GPUAOrnament {
    /// Convenience ``Rune`` entry point that automatically mounts any emitted overlays via ``RuneKit/root(_:_:)``.
    public func renderRune(theme: OrnamentTheme = OrnamentTheme.current) -> Rune.El {
        var overlays: [Rune.El] = []
        let base = renderRune(theme: theme, layer: &overlays)
        if overlays.isEmpty {
            return base
        }
        return RuneKit.root(base, overlays)
    }

    /// ``GPUI/IntoElement`` conformance using ``OrnamentTheme/current``.
    public func intoElement() -> GPUI.AnyElement {
        renderGPUI(theme: OrnamentTheme.current)
    }

    public func intoAnyElement() -> GPUI.AnyElement {
        renderGPUI(theme: OrnamentTheme.current)
    }

    /// Overrides the theme for this ornament subtree on both ``GPUI`` and ``Rune``.
    public func themed(_ theme: OrnamentTheme) -> ThemedOrnament<Self> {
        ThemedOrnament(theme: theme, content: self)
    }

    /// Type-erases this ornament into ``AnyOrnament``.
    public func eraseToAnyOrnament() -> AnyOrnament {
        AnyOrnament(self)
    }
}

/// Scopes an explicit ``OrnamentTheme`` around a child ornament.
public struct ThemedOrnament<Content: GPUAOrnament>: GPUAOrnament {
    public var theme: OrnamentTheme
    public var content: Content

    public init(theme: OrnamentTheme, content: Content) {
        self.theme = theme
        self.content = content
    }

    public func renderGPUI(theme _: OrnamentTheme) -> GPUI.AnyElement {
        OrnamentTheme.withTheme(theme) {
            content.renderGPUI(theme: theme)
        }
    }

    public func renderRune(theme _: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        OrnamentTheme.withTheme(theme) {
            content.renderRune(theme: theme, layer: &layer)
        }
    }
}

/// Type-erased ``GPUAOrnament`` container for heterogeneous ornament layouts.
public struct AnyOrnament: GPUAOrnament {
    private let gpuiBuilder: @Sendable (OrnamentTheme) -> GPUI.AnyElement
    private let runeBuilder: @Sendable (OrnamentTheme, inout [Rune.El]) -> Rune.El

    public init<O: GPUAOrnament>(_ ornament: O) {
        self.gpuiBuilder = { theme in
            ornament.renderGPUI(theme: theme)
        }
        self.runeBuilder = { theme, layer in
            ornament.renderRune(theme: theme, layer: &layer)
        }
    }

    public init(
        gpui: @escaping @Sendable (OrnamentTheme) -> GPUI.AnyElement,
        rune: @escaping @Sendable (OrnamentTheme, inout [Rune.El]) -> Rune.El
    ) {
        self.gpuiBuilder = gpui
        self.runeBuilder = rune
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        gpuiBuilder(theme)
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        runeBuilder(theme, &layer)
    }
}

/// Simple text ornament for composing plain or muted copy inside ornament containers.
public struct UIText: GPUAOrnament {
    public var content: String
    public var sizePx: Float
    public var weight: Float
    public var muted: Bool
    public var mono: Bool

    public init(
        _ content: String,
        sizePx: Float = 13.5,
        weight: Float = 400.0,
        muted: Bool = false,
        mono: Bool = false
    ) {
        self.content = content
        self.sizePx = sizePx
        self.weight = weight
        self.muted = muted
        self.mono = mono
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let color = (muted ? theme.mutedForeground : theme.foreground).toGPUIHsla()
        var el = GPUI.div()
            .textSize(.pixels(GPUI.px(sizePx)))
            .lineHeight(.pixels(GPUI.px((sizePx * 1.42).rounded())))
            .fontWeight(GPUI.FontWeight(weight))
            .textColor(color)
        if mono {
            el = el.fontFamily(GPUI.SharedString(theme.fontMono))
        }
        return el.child(content).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let color = (muted ? theme.mutedForeground : theme.foreground).toRuneColor()
        var ts = Rune.TextStyle.new(sizePx, weight).lh((sizePx * 1.42).rounded())
        if mono {
            ts = ts.mono()
        }
        return Rune.text(content).font(ts).color(color)
    }
}

/// Horizontal dual-engine flex stack (`GPUAOrnament`) for composing ornament rows inside cards, sheets, and dialogs.
public struct UIHStack: GPUAOrnament {
    public var gapPx: Float
    public var wrap: Bool
    public var children: [AnyOrnament]

    public init(gapPx: Float = 8.0, wrap: Bool = false, _ children: [AnyOrnament] = []) {
        self.gapPx = gapPx
        self.wrap = wrap
        self.children = children
    }

    public func child<O: GPUAOrnament>(_ item: O) -> UIHStack {
        var copy = self
        copy.children.append(AnyOrnament(item))
        return copy
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var row = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(gapPx)))
        if wrap { row = row.flexWrap() }
        for c in children {
            row = row.child(c.renderGPUI(theme: theme))
        }
        return row.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var row = Rune.row().centerY().gap(gapPx)
        if wrap { row = row.flexWrap() }
        for c in children {
            row = row.child(c.renderRune(theme: theme, layer: &layer))
        }
        return row
    }
}

/// Vertical dual-engine flex stack (`GPUAOrnament`) for composing ornament columns inside cards, sheets, and dialogs.
public struct UIVStack: GPUAOrnament {
    public var gapPx: Float
    public var children: [AnyOrnament]

    public init(gapPx: Float = 10.0, _ children: [AnyOrnament] = []) {
        self.gapPx = gapPx
        self.children = children
    }

    public func child<O: GPUAOrnament>(_ item: O) -> UIVStack {
        var copy = self
        copy.children.append(AnyOrnament(item))
        return copy
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var col = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(gapPx))).wFull()
        for c in children {
            col = col.child(c.renderGPUI(theme: theme))
        }
        return col.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var col = Rune.col().wFull().gap(gapPx)
        for c in children {
            col = col.child(c.renderRune(theme: theme, layer: &layer))
        }
        return col
    }
}

/// Crisp 1px horizontal or vertical Shadcn `Separator` ornament.
public struct UISeparator: GPUAOrnament {
    public var vertical: Bool

    public init(vertical: Bool = false) {
        self.vertical = vertical
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        if vertical {
            return GPUI.div().w(GPUI.px(1.0)).h(GPUI.px(18.0)).bg(theme.border.toGPUIHsla()).intoAnyElement()
        }
        return GPUI.div().wFull().h(GPUI.px(1.0)).bg(theme.border.toGPUIHsla()).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        if vertical {
            return Rune.el().w(1.0).h(18.0).fill(theme.border.toRuneColor())
        }
        return Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor())
    }
}

// MARK: - Crisp Dual-Engine Vector Icons (Lucide 16x16 Grid)

/// Built-in Lucide-inspired vector icons rendered via native GPU vector paths on both ``GPUI`` and ``Rune``.
public enum OrnamentIcon: String, Sendable, Equatable, Hashable, CaseIterable {
    case sparkles
    case search
    case command
    case check
    case chevronRight
    case chevronDown
    case plus
    case x
    case copy
    case sliders
    case code
    case gitBranch
    case terminal
    case layers
    case sun
    case moon
    case bell
    case settings
    case bolt
    case info
    case warning
    case trash
    case externalLink
    case eye
    case play
    case folder
    case file
    case palette
    case globe

    fileprivate struct StrokePoly: Sendable {
        var points: [[Float]]
        var closed: Bool = false
    }

    @inline(__always)
    private static func circlePoints(cx: Float, cy: Float, r: Float, steps: Int = 16) -> [[Float]] {
        var pts: [[Float]] = []
        pts.reserveCapacity(steps)
        for i in 0..<steps {
            let a = (Float(i) / Float(steps)) * 2.0 * Float.pi
            pts.append([cx + Float(cos(Double(a))) * r, cy + Float(sin(Double(a))) * r])
        }
        return pts
    }

    fileprivate var strokes: [StrokePoly] {
        switch self {
        case .check:
            return [StrokePoly(points: [[3.0, 8.5], [6.5, 12.0], [13.2, 4.5]])]
        case .plus:
            return [
                StrokePoly(points: [[8.0, 3.2], [8.0, 12.8]]),
                StrokePoly(points: [[3.2, 8.0], [12.8, 8.0]]),
            ]
        case .x:
            return [
                StrokePoly(points: [[4.0, 4.0], [12.0, 12.0]]),
                StrokePoly(points: [[12.0, 4.0], [4.0, 12.0]]),
            ]
        case .chevronRight:
            return [StrokePoly(points: [[6.0, 3.8], [10.4, 8.0], [6.0, 12.2]])]
        case .chevronDown:
            return [StrokePoly(points: [[3.8, 6.0], [8.0, 10.4], [12.2, 6.0]])]
        case .search:
            return [
                StrokePoly(points: Self.circlePoints(cx: 7.0, cy: 7.0, r: 4.3), closed: true),
                StrokePoly(points: [[10.2, 10.2], [13.4, 13.4]]),
            ]
        case .command:
            return [
                StrokePoly(points: [[5.5, 5.5], [10.5, 5.5], [10.5, 10.5], [5.5, 10.5]], closed: true),
                StrokePoly(points: Self.circlePoints(cx: 4.2, cy: 4.2, r: 1.5, steps: 12), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 11.8, cy: 4.2, r: 1.5, steps: 12), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 4.2, cy: 11.8, r: 1.5, steps: 12), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 11.8, cy: 11.8, r: 1.5, steps: 12), closed: true),
            ]
        case .sparkles:
            return [
                StrokePoly(points: [[8.0, 2.2], [9.4, 6.6], [13.8, 8.0], [9.4, 9.4], [8.0, 13.8], [6.6, 9.4], [2.2, 8.0], [6.6, 6.6]], closed: true),
                StrokePoly(points: [[12.6, 2.2], [12.6, 4.6]]),
                StrokePoly(points: [[11.4, 3.4], [13.8, 3.4]]),
            ]
        case .copy:
            return [
                StrokePoly(points: [[5.8, 5.8], [13.0, 5.8], [13.0, 13.0], [5.8, 13.0]], closed: true),
                StrokePoly(points: [[3.2, 10.2], [3.2, 3.2], [10.2, 3.2]]),
            ]
        case .sliders:
            return [
                StrokePoly(points: [[2.5, 4.5], [13.5, 4.5]]),
                StrokePoly(points: [[2.5, 8.0], [13.5, 8.0]]),
                StrokePoly(points: [[2.5, 11.5], [13.5, 11.5]]),
                StrokePoly(points: Self.circlePoints(cx: 6.0, cy: 4.5, r: 1.5, steps: 10), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 10.5, cy: 8.0, r: 1.5, steps: 10), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 7.2, cy: 11.5, r: 1.5, steps: 10), closed: true),
            ]
        case .code:
            return [
                StrokePoly(points: [[5.6, 4.5], [2.2, 8.0], [5.6, 11.5]]),
                StrokePoly(points: [[10.4, 4.5], [13.8, 8.0], [10.4, 11.5]]),
            ]
        case .gitBranch:
            return [
                StrokePoly(points: [[4.5, 4.5], [4.5, 11.5]]),
                StrokePoly(points: Self.circlePoints(cx: 4.5, cy: 3.5, r: 1.4, steps: 10), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 4.5, cy: 12.5, r: 1.4, steps: 10), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 11.5, cy: 4.5, r: 1.4, steps: 10), closed: true),
                StrokePoly(points: [[11.5, 5.9], [11.5, 8.2], [4.5, 9.2]]),
            ]
        case .terminal:
            return [
                StrokePoly(points: [[3.0, 4.8], [6.8, 8.0], [3.0, 11.2]]),
                StrokePoly(points: [[8.2, 11.5], [13.0, 11.5]]),
            ]
        case .layers:
            return [
                StrokePoly(points: [[8.0, 2.5], [13.8, 5.5], [8.0, 8.5], [2.2, 5.5]], closed: true),
                StrokePoly(points: [[2.2, 8.2], [8.0, 11.2], [13.8, 8.2]]),
                StrokePoly(points: [[2.2, 10.8], [8.0, 13.8], [13.8, 10.8]]),
            ]
        case .sun:
            return [
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 3.1, steps: 14), closed: true),
                StrokePoly(points: [[8.0, 1.8], [8.0, 3.2]]),
                StrokePoly(points: [[8.0, 12.8], [8.0, 14.2]]),
                StrokePoly(points: [[1.8, 8.0], [3.2, 8.0]]),
                StrokePoly(points: [[12.8, 8.0], [14.2, 8.0]]),
            ]
        case .moon:
            return [
                StrokePoly(points: [[11.8, 10.8], [9.2, 11.5], [6.5, 10.4], [5.0, 7.8], [5.8, 4.6], [7.8, 3.0], [5.2, 3.5], [3.2, 5.8], [3.2, 9.2], [5.5, 12.2], [9.0, 13.0], [11.8, 10.8]], closed: true),
            ]
        case .bell:
            return [
                StrokePoly(points: [[4.2, 10.8], [4.8, 6.2], [6.2, 3.8], [8.0, 3.2], [9.8, 3.8], [11.2, 6.2], [11.8, 10.8], [3.0, 10.8], [13.0, 10.8]]),
                StrokePoly(points: [[6.8, 12.6], [8.0, 13.5], [9.2, 12.6]]),
            ]
        case .settings:
            return [
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 2.3, steps: 12), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 5.2, steps: 8), closed: true),
            ]
        case .bolt:
            return [
                StrokePoly(points: [[8.8, 2.0], [3.8, 8.8], [7.8, 8.8], [7.2, 14.0], [12.2, 7.2], [8.2, 7.2]], closed: true),
            ]
        case .info:
            return [
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 5.6, steps: 16), closed: true),
                StrokePoly(points: [[8.0, 7.4], [8.0, 11.2]]),
                StrokePoly(points: [[8.0, 5.0], [8.0, 5.4]]),
            ]
        case .warning:
            return [
                StrokePoly(points: [[8.0, 2.6], [13.8, 12.8], [2.2, 12.8]], closed: true),
                StrokePoly(points: [[8.0, 6.4], [8.0, 9.6]]),
                StrokePoly(points: [[8.0, 11.1], [8.0, 11.5]]),
            ]
        case .trash:
            return [
                StrokePoly(points: [[3.2, 4.5], [12.8, 4.5]]),
                StrokePoly(points: [[6.0, 4.5], [6.4, 2.8], [9.6, 2.8], [10.0, 4.5]]),
                StrokePoly(points: [[4.5, 4.5], [5.0, 13.2], [11.0, 13.2], [11.5, 4.5]]),
            ]
        case .externalLink:
            return [
                StrokePoly(points: [[9.5, 3.0], [13.0, 3.0], [13.0, 6.5]]),
                StrokePoly(points: [[7.2, 8.8], [13.0, 3.0]]),
                StrokePoly(points: [[11.5, 9.2], [11.5, 12.8], [3.2, 12.8], [3.2, 4.5], [6.8, 4.5]]),
            ]
        case .eye:
            return [
                StrokePoly(points: [[2.0, 8.0], [5.0, 4.6], [8.0, 3.8], [11.0, 4.6], [14.0, 8.0], [11.0, 11.4], [8.0, 12.2], [5.0, 11.4]], closed: true),
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 1.9, steps: 12), closed: true),
            ]
        case .play:
            return [
                StrokePoly(points: [[4.8, 3.4], [12.6, 8.0], [4.8, 12.6]], closed: true),
            ]
        case .folder:
            return [
                StrokePoly(points: [[2.4, 4.2], [6.4, 4.2], [7.8, 5.8], [13.6, 5.8], [13.6, 12.6], [2.4, 12.6]], closed: true),
            ]
        case .file:
            return [
                StrokePoly(points: [[4.0, 2.6], [9.8, 2.6], [12.4, 5.2], [12.4, 13.4], [4.0, 13.4]], closed: true),
                StrokePoly(points: [[9.6, 2.6], [9.6, 5.4], [12.4, 5.4]]),
            ]
        case .palette:
            return [
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 5.7, steps: 16), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 6.0, cy: 6.0, r: 0.9, steps: 8), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 9.6, cy: 5.5, r: 0.9, steps: 8), closed: true),
                StrokePoly(points: Self.circlePoints(cx: 10.6, cy: 8.8, r: 0.9, steps: 8), closed: true),
            ]
        case .globe:
            return [
                StrokePoly(points: Self.circlePoints(cx: 8.0, cy: 8.0, r: 5.8, steps: 18), closed: true),
                StrokePoly(points: [[2.3, 8.0], [13.7, 8.0]]),
                StrokePoly(points: [[8.0, 2.2], [6.0, 5.4], [6.0, 10.6], [8.0, 13.8], [10.0, 10.6], [10.0, 5.4]], closed: true),
            ]
        }
    }

    /// Renders this vector icon at `sizePx` in `color` as a native ``GPUI/AnyElement``.
    public func renderGPUI(sizePx: Float = 15.0, color: OrnamentColor) -> GPUI.AnyElement {
        let polyList = strokes
        let hsla = color.toGPUIHsla()
        let strokeWidth = Swift.max(1.25, sizePx * 0.095)
        return GPUI.canvas(
            { _, _, _ in () },
            { bounds, _, window, _ in
                let ox = bounds.origin.x.value
                let oy = bounds.origin.y.value
                let sx = bounds.size.width.value / 16.0
                let sy = bounds.size.height.value / 16.0
                for poly in polyList where poly.points.count >= 2 {
                    var pb = GPUI.PathBuilder.stroke(GPUI.px(strokeWidth))
                    let p0 = poly.points[0]
                    pb.moveTo(GPUI.point(GPUI.px(ox + p0[0] * sx), GPUI.px(oy + p0[1] * sy)))
                    for pt in poly.points.dropFirst() {
                        pb.lineTo(GPUI.point(GPUI.px(ox + pt[0] * sx), GPUI.px(oy + pt[1] * sy)))
                    }
                    if poly.closed {
                        pb.lineTo(GPUI.point(GPUI.px(ox + p0[0] * sx), GPUI.px(oy + p0[1] * sy)))
                    }
                    if let built = try? pb.build() {
                        window.paintPath(built, color: hsla)
                    }
                }
            }
        )
        .size(GPUI.px(sizePx))
        .flexShrink0()
        .intoAnyElement()
    }

    /// Renders this vector icon at `sizePx` in `color` as a native ``Rune/El``.
    public func renderRune(sizePx: Float = 15.0, color: OrnamentColor) -> Rune.El {
        let rc = color.toRuneColor()
        let strokeWidth: Float = 1.5
        var shape = Rune.Shape.new().viewBox(16.0, 16.0)
        for poly in strokes where poly.points.count >= 2 {
            shape = shape.strokeWith(poly.points, poly.closed, strokeWidth, .round, rc)
        }
        return Rune.canvas(shape).size(sizePx, sizePx)
    }
}
