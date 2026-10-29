// Ported from: crates/gpui/src/taffy.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

// MARK: - AvailableSpace

/// The space available for an element to be laid out in.
public enum AvailableSpace: Sendable, Equatable, Hashable {
    /// The amount of space available is the specified number of pixels.
    case definite(Pixels)
    /// The amount of space available is indefinite and the node should be laid out under a min-content constraint.
    case minContent
    /// The amount of space available is indefinite and the node should be laid out under a max-content constraint.
    case maxContent

    public init() {
        self = .minContent
    }

    /// Returns a `Size` with both width and height set to `AvailableSpace.minContent`.
    ///
    /// This function is useful when you want to create a `Size` with the minimum content constraints
    /// for both dimensions.
    public static func minSize() -> Size<AvailableSpace> {
        Size(width: .minContent, height: .minContent)
    }

    /// Returns a `Size` with both width and height set to `AvailableSpace.maxContent`.
    public static func maxSize() -> Size<AvailableSpace> {
        Size(width: .maxContent, height: .maxContent)
    }

    public init(_ pixels: Pixels) {
        self = .definite(pixels)
    }
}

extension AvailableSpace: DefaultInitializable {}

extension Size where T == AvailableSpace {
    public init(_ size: Size<Pixels>) {
        self.init(
            width: .definite(size.width),
            height: .definite(size.height)
        )
    }
}

// MARK: - Conversions between GPUI.AvailableSpace and Taffy.AvailableSpace

extension AvailableSpace {
    @inlinable
    public func toTaffy() -> Taffy.AvailableSpace {
        switch self {
        case .definite(let pixels):
            return .definite(pixels.value)
        case .minContent:
            return .minContent
        case .maxContent:
            return .maxContent
        }
    }

    @inlinable
    public init(_ taffySpace: Taffy.AvailableSpace) {
        switch taffySpace {
        case .definite(let value):
            self = .definite(Pixels(value))
        case .minContent:
            self = .minContent
        case .maxContent:
            self = .maxContent
        }
    }
}

extension Size where T == AvailableSpace {
    @inlinable
    public func toTaffy() -> Taffy.Size<Taffy.AvailableSpace> {
        Taffy.Size(
            width: width.toTaffy(),
            height: height.toTaffy()
        )
    }

    @inlinable
    public init(_ taffySize: Taffy.Size<Taffy.AvailableSpace>) {
        self.init(
            width: AvailableSpace(taffySize.width),
            height: AvailableSpace(taffySize.height)
        )
    }
}

// MARK: - LayoutId

/// A unique identifier for a layout node, generated when requesting a layout from Taffy.
public struct LayoutId: Copyable, Sendable, Equatable, Hashable, CustomDebugStringConvertible, CustomStringConvertible {
    public let rawValue: NodeId

    @inlinable
    public init(_ rawValue: NodeId) {
        self.rawValue = rawValue
    }

    public var debugDescription: String {
        "LayoutId(\(rawValue.debugDescription))"
    }

    public var description: String {
        "LayoutId(\(rawValue.rawValue))"
    }

    @inlinable
    public static func toTaffySlice(_ nodeIds: [LayoutId]) -> [NodeId] {
        nodeIds.map(\.rawValue)
    }
}

extension LayoutId: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: UInt64) {
        self.rawValue = NodeId(value)
    }
}

// MARK: - NodeContext & Measurement Callbacks

public typealias LayoutMeasureFn = @Sendable (
    Size<Pixels?>,
    Size<AvailableSpace>,
    inout Window,
    inout App
) -> Size<Pixels>

// PORT NOTE: NodeContext holds the synchronous layout measurement callback.
// Synchronous layout execution occurs sequentially on the active thread, matching upstream's Box<dyn FnMut(...)>.
// Marked @unchecked Sendable to satisfy TaffyTree's Sendable constraint.
public final class NodeContext: @unchecked Sendable {
    var measure: LayoutMeasureFn

    public init(measure: @escaping LayoutMeasureFn) {
        self.measure = measure
    }
}

// PORT NOTE: Reference boxes to allow synchronous inout mutation of Window and App
// across the @Sendable escaping closure barrier in computeLayoutWithMeasure.
private final class WindowRef: @unchecked Sendable {
    var window: Window
    init(_ window: Window) { self.window = window }
}

// PORT NOTE: Reference box to allow synchronous inout mutation of App across @Sendable closure barrier.
private final class AppRef: @unchecked Sendable {
    var app: App
    init(_ app: App) { self.app = app }
}

// MARK: - Conversions: GPUI Types to Taffy Types

extension AbsoluteLength {
    @inlinable
    public func toTaffy(remSize: Pixels, scaleFactor: Float) -> Float {
        switch self {
        case .pixels(let pixels):
            return pixels.value * scaleFactor
        case .rems(let rems):
            return (rems.value * remSize.value) * scaleFactor
        }
    }

    @inlinable
    public func toTaffyLengthPercentage(remSize: Pixels, scaleFactor: Float) -> Taffy.LengthPercentage {
        return .length(toTaffy(remSize: remSize, scaleFactor: scaleFactor))
    }
}

extension DefiniteLength {
    @inlinable
    public func toTaffyDimension(remSize: Pixels, scaleFactor: Float) -> Taffy.Dimension {
        switch self {
        case .absolute(let length):
            return .length(length.toTaffy(remSize: remSize, scaleFactor: scaleFactor))
        case .fraction(let fraction):
            return .percent(fraction)
        }
    }

    @inlinable
    public func toTaffyLengthPercentage(remSize: Pixels, scaleFactor: Float) -> Taffy.LengthPercentage {
        switch self {
        case .absolute(let length):
            return .length(length.toTaffy(remSize: remSize, scaleFactor: scaleFactor))
        case .fraction(let fraction):
            return .percent(fraction)
        }
    }

    @inlinable
    public func toTaffyLengthPercentageAuto(remSize: Pixels, scaleFactor: Float) -> Taffy.LengthPercentageAuto {
        switch self {
        case .absolute(let length):
            return .length(length.toTaffy(remSize: remSize, scaleFactor: scaleFactor))
        case .fraction(let fraction):
            return .percent(fraction)
        }
    }
}

extension Length {
    @inlinable
    public func toTaffyDimension(remSize: Pixels, scaleFactor: Float) -> Taffy.Dimension {
        switch self {
        case .definite(let length):
            return length.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor)
        case .auto:
            return .auto()
        }
    }

    @inlinable
    public func toTaffyLengthPercentageAuto(remSize: Pixels, scaleFactor: Float) -> Taffy.LengthPercentageAuto {
        switch self {
        case .definite(let length):
            return length.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor)
        case .auto:
            return .auto()
        }
    }
}

extension Size where T == Length {
    @inlinable
    public func toTaffyDimension(remSize: Pixels, scaleFactor: Float) -> Taffy.Size<Taffy.Dimension> {
        Taffy.Size(
            width: width.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor),
            height: height.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

extension Size where T == DefiniteLength {
    @inlinable
    public func toTaffyLengthPercentage(remSize: Pixels, scaleFactor: Float) -> Taffy.Size<Taffy.LengthPercentage> {
        Taffy.Size(
            width: width.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            height: height.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

extension Edges where T == Length {
    @inlinable
    public func toTaffyLengthPercentageAuto(remSize: Pixels, scaleFactor: Float) -> Taffy.Rect<Taffy.LengthPercentageAuto> {
        Taffy.Rect(
            left: left.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor),
            right: right.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor),
            top: top.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor),
            bottom: bottom.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

extension Edges where T == DefiniteLength {
    @inlinable
    public func toTaffyLengthPercentage(remSize: Pixels, scaleFactor: Float) -> Taffy.Rect<Taffy.LengthPercentage> {
        Taffy.Rect(
            left: left.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            right: right.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            top: top.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            bottom: bottom.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

extension Edges where T == AbsoluteLength {
    @inlinable
    public func toTaffyLengthPercentage(remSize: Pixels, scaleFactor: Float) -> Taffy.Rect<Taffy.LengthPercentage> {
        Taffy.Rect(
            left: left.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            right: right.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            top: top.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            bottom: bottom.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

@inlinable
func toTaffyOverflow(_ overflow: GPUI.Overflow) -> Taffy.Overflow {
    switch overflow {
    case .visible: return .visible
    case .clip: return .clip
    case .hidden: return .hidden
    case .scroll: return .scroll
    }
}

@inlinable
func toTaffyAlignItems(_ align: GPUI.AlignItems) -> Taffy.AlignItems {
    switch align {
    case .start: return .start
    case .end: return .end
    case .flexStart: return .flexStart
    case .flexEnd: return .flexEnd
    case .center: return .center
    case .baseline: return .baseline
    case .stretch: return .stretch
    }
}

@inlinable
func toTaffyAlignContent(_ content: GPUI.AlignContent) -> Taffy.AlignContent {
    switch content {
    case .start: return .start
    case .end: return .end
    case .flexStart: return .flexStart
    case .flexEnd: return .flexEnd
    case .center: return .center
    case .stretch: return .stretch
    case .spaceBetween: return .spaceBetween
    case .spaceEvenly: return .spaceEvenly
    case .spaceAround: return .spaceAround
    }
}

@inlinable
func toGridLine(_ placement: Range<Int>) -> Taffy.Line<Taffy.GridPlacement<String>> {
    let startPlacement: Taffy.GridPlacement<String> = (placement.lowerBound == 0 && placement.upperBound == 0)
        ? .auto
        : .fromLineIndex(Int16(placement.lowerBound))
    let endPlacement: Taffy.GridPlacement<String> = (placement.lowerBound == 0 && placement.upperBound == 0)
        ? .auto
        : .fromLineIndex(Int16(placement.upperBound))
    return Taffy.Line(start: startPlacement, end: endPlacement)
}

func toGridRepeat(unit: GridTemplate?) -> [Taffy.GridTemplateComponent<String>] {
    guard let template = unit else { return [] }
    switch template.minSize {
    case .zero:
        let track: TrackSizingFunction = minmax(length(0.0), fr(1.0))
        return [repeat_(template.repeat, [track])]
    case .minContent:
        let track: TrackSizingFunction = minmax(min_content(), fr(1.0))
        return [repeat_(template.repeat, [track])]
    case .maxContent:
        let track: TrackSizingFunction = minmax(length(0.0), max_content())
        return [repeat_(template.repeat, [track])]
    }
}

extension Style {
    public func toTaffy(remSize: Pixels, scaleFactor: Float) -> Taffy.Style<String> {
        let taffyDisplay: Taffy.Display
        switch self.display {
        case .block: taffyDisplay = .block
        case .flex: taffyDisplay = .flex
        case .grid: taffyDisplay = .grid
        case .none: taffyDisplay = .none
        }

        let taffyPosition: Taffy.Position
        switch self.position {
        case .relative: taffyPosition = .relative
        case .absolute: taffyPosition = .absolute
        }

        let taffyOverflow = Taffy.Point(
            x: toTaffyOverflow(self.overflow.x),
            y: toTaffyOverflow(self.overflow.y)
        )

        let taffyScrollbarWidth = self.scrollbarWidth.toTaffy(remSize: remSize, scaleFactor: scaleFactor)

        let taffyFlexDirection: Taffy.FlexDirection
        switch self.flexDirection {
        case .row: taffyFlexDirection = .row
        case .column: taffyFlexDirection = .column
        case .rowReverse: taffyFlexDirection = .rowReverse
        case .columnReverse: taffyFlexDirection = .columnReverse
        }

        let taffyFlexWrap: Taffy.FlexWrap
        switch self.flexWrap {
        case .noWrap: taffyFlexWrap = .noWrap
        case .wrap: taffyFlexWrap = .wrap
        case .wrapReverse: taffyFlexWrap = .wrapReverse
        }

        let taffyAlignItems = self.alignItems.map(toTaffyAlignItems)
        let taffyAlignSelf = self.alignSelf.map(toTaffyAlignItems)
        let taffyAlignContent = self.alignContent.map(toTaffyAlignContent)
        let taffyJustifyContent = self.justifyContent.map(toTaffyAlignContent)

        let gridRows = toGridRepeat(unit: self.gridRows)
        let gridCols = toGridRepeat(unit: self.gridCols)

        let gridRowPlacement: Taffy.Line<Taffy.GridPlacement<String>>
        let gridColPlacement: Taffy.Line<Taffy.GridPlacement<String>>
        if let location = self.gridLocation {
            gridRowPlacement = toGridLine(location.row)
            gridColPlacement = toGridLine(location.column)
        } else {
            gridRowPlacement = Taffy.Line(start: .auto, end: .auto)
            gridColPlacement = Taffy.Line(start: .auto, end: .auto)
        }

        return Taffy.Style<String>(
            display: taffyDisplay,
            overflow: taffyOverflow,
            scrollbarWidth: taffyScrollbarWidth,
            position: taffyPosition,
            inset: self.inset.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor),
            size: self.size.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor),
            minSize: self.minSize.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor),
            maxSize: self.maxSize.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor),
            aspectRatio: self.aspectRatio,
            margin: self.margin.toTaffyLengthPercentageAuto(remSize: remSize, scaleFactor: scaleFactor),
            padding: self.padding.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            border: self.borderWidths.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            alignItems: taffyAlignItems,
            alignSelf: taffyAlignSelf,
            alignContent: taffyAlignContent,
            justifyContent: taffyJustifyContent,
            gap: self.gap.toTaffyLengthPercentage(remSize: remSize, scaleFactor: scaleFactor),
            flexDirection: taffyFlexDirection,
            flexWrap: taffyFlexWrap,
            flexBasis: self.flexBasis.toTaffyDimension(remSize: remSize, scaleFactor: scaleFactor),
            flexGrow: self.flexGrow,
            flexShrink: self.flexShrink,
            gridTemplateRows: gridRows,
            gridTemplateColumns: gridCols,
            gridRow: gridRowPlacement,
            gridColumn: gridColPlacement
        )
    }
}

// MARK: - Point & Size Conversions

extension Point {
    @inlinable
    public init(_ taffyPoint: Taffy.Point<T>) {
        self.init(x: taffyPoint.x, y: taffyPoint.y)
    }

    @inlinable
    public func toTaffy() -> Taffy.Point<T> {
        Taffy.Point(x: x, y: y)
    }
}

extension Size {
    @inlinable
    public init(_ taffySize: Taffy.Size<T>) {
        self.init(width: taffySize.width, height: taffySize.height)
    }

    @inlinable
    public func toTaffy() -> Taffy.Size<T> {
        Taffy.Size(width: width, height: height)
    }
}

// MARK: - TaffyLayoutEngine

private let EXPECT_MESSAGE = "we should avoid taffy layout errors by construction if possible"

/// Swift port of GPUI's layout engine wrapping TaffyTree<NodeContext> from Taffy 0.9.0.
public struct TaffyLayoutEngine: Sendable {
    private var taffy: TaffyTree<NodeContext>
    private var absoluteLayoutBounds: [LayoutId: Bounds<Pixels>]
    private var computedLayouts: Set<LayoutId>
    private var layoutBoundsScratchSpace: [LayoutId]

    public init() {
        var tree = TaffyTree<NodeContext>()
        tree.enableRounding()
        self.taffy = tree
        self.absoluteLayoutBounds = [:]
        self.computedLayouts = []
        self.layoutBoundsScratchSpace = []
    }

    public static func new() -> TaffyLayoutEngine {
        TaffyLayoutEngine()
    }

    public mutating func clear() {
        taffy.clear()
        absoluteLayoutBounds.removeAll(keepingCapacity: true)
        computedLayouts.removeAll(keepingCapacity: true)
        layoutBoundsScratchSpace.removeAll(keepingCapacity: true)
    }

    public mutating func requestLayout(
        style: Style,
        remSize: Pixels,
        scaleFactor: Float,
        children: [LayoutId] = []
    ) -> LayoutId {
        let taffyStyle = style.toTaffy(remSize: remSize, scaleFactor: scaleFactor)

        if children.isEmpty {
            switch taffy.newLeaf(taffyStyle) {
            case .success(let nodeId):
                return LayoutId(nodeId)
            case .failure(let err):
                fatalError("\(EXPECT_MESSAGE): \(err)")
            }
        } else {
            let childNodeIds = children.map(\.rawValue)
            switch taffy.newWithChildren(taffyStyle, childNodeIds) {
            case .success(let nodeId):
                return LayoutId(nodeId)
            case .failure(let err):
                fatalError("\(EXPECT_MESSAGE): \(err)")
            }
        }
    }

    public mutating func requestMeasuredLayout(
        style: Style,
        remSize: Pixels,
        scaleFactor: Float,
        measure: @escaping LayoutMeasureFn
    ) -> LayoutId {
        let taffyStyle = style.toTaffy(remSize: remSize, scaleFactor: scaleFactor)
        let context = NodeContext(measure: measure)
        switch taffy.newLeafWithContext(taffyStyle, context) {
        case .success(let nodeId):
            return LayoutId(nodeId)
        case .failure(let err):
            fatalError("\(EXPECT_MESSAGE): \(err)")
        }
    }

    public mutating func computeLayout(
        id: LayoutId,
        availableSpace: Size<AvailableSpace>,
        window: inout Window,
        cx: inout App
    ) {
        if !computedLayouts.insert(id).inserted {
            layoutBoundsScratchSpace.append(id)
            while let currentId = layoutBoundsScratchSpace.popLast() {
                absoluteLayoutBounds.removeValue(forKey: currentId)
                switch taffy.children(currentId.rawValue) {
                case .success(let childNodeIds):
                    layoutBoundsScratchSpace.append(contentsOf: childNodeIds.map { LayoutId($0) })
                case .failure(let err):
                    fatalError("\(EXPECT_MESSAGE): \(err)")
                }
            }
        }

        let scaleFactor = window.scaleFactor

        let transform = { (v: AvailableSpace) -> AvailableSpace in
            switch v {
            case .definite(let pixels):
                return .definite(Pixels(pixels.value * scaleFactor))
            case .minContent:
                return .minContent
            case .maxContent:
                return .maxContent
            }
        }
        let scaledAvailableSpace = Size(
            width: transform(availableSpace.width),
            height: transform(availableSpace.height)
        )

        let windowRef = WindowRef(window)
        let cxRef = AppRef(cx)
        defer {
            window = windowRef.window
            cx = cxRef.app
        }

        let taffyAvailableSpace = scaledAvailableSpace.toTaffy()
        let result = taffy.computeLayoutWithMeasure(
            id.rawValue,
            taffyAvailableSpace
        ) { knownDimensions, availableSpace, _id, nodeContext, _style in
            guard let nodeContext = nodeContext else {
                return Taffy.Size<Float>.ZERO
            }

            let knownDimensionsGPUI = Size<Pixels?>(
                width: knownDimensions.width.map { Pixels($0 / scaleFactor) },
                height: knownDimensions.height.map { Pixels($0 / scaleFactor) }
            )

            let untransform = { (ev: Taffy.AvailableSpace) -> AvailableSpace in
                switch ev {
                case .definite(let val):
                    return .definite(Pixels(val / scaleFactor))
                case .minContent:
                    return .minContent
                case .maxContent:
                    return .maxContent
                }
            }
            let availableSpaceGPUI = Size<AvailableSpace>(
                width: untransform(availableSpace.width),
                height: untransform(availableSpace.height)
            )

            let measured = (nodeContext.measure)(
                knownDimensionsGPUI,
                availableSpaceGPUI,
                &windowRef.window,
                &cxRef.app
            )
            return Taffy.Size<Float>(
                width: measured.width.value * scaleFactor,
                height: measured.height.value * scaleFactor
            )
        }

        if case .failure(let err) = result {
            fatalError("\(EXPECT_MESSAGE): \(err)")
        }
    }

    public mutating func computeLayout(
        id: LayoutId,
        availableSpace: Size<AvailableSpace>,
        scaleFactor: Float = 1.0
    ) {
        var dummyWindow = Window(scaleFactor: scaleFactor)
        var dummyApp = App()
        computeLayout(id: id, availableSpace: availableSpace, window: &dummyWindow, cx: &dummyApp)
    }

    public mutating func layoutBounds(id: LayoutId, scaleFactor: Float) -> Bounds<Pixels> {
        if let bounds = absoluteLayoutBounds[id] {
            return bounds
        }

        let layout: Taffy.Layout
        switch taffy.layout(id.rawValue) {
        case .success(let l):
            layout = l
        case .failure(let err):
            fatalError("\(EXPECT_MESSAGE): \(err)")
        }

        var bounds = Bounds(
            origin: point(
                Pixels(layout.location.x / scaleFactor),
                Pixels(layout.location.y / scaleFactor)
            ),
            size: size(
                Pixels(layout.size.width / scaleFactor),
                Pixels(layout.size.height / scaleFactor)
            )
        )

        if let parentId = taffy.parent(id.rawValue) {
            let parentBounds = layoutBounds(id: LayoutId(parentId), scaleFactor: scaleFactor)
            bounds.origin += parentBounds.origin
        }
        absoluteLayoutBounds[id] = bounds

        return bounds
    }

    public mutating func computeLayoutBounds(id: LayoutId, scaleFactor: Float) -> Bounds<Pixels> {
        return layoutBounds(id: id, scaleFactor: scaleFactor)
    }
}
