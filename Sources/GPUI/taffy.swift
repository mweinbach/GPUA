// Ported from: crates/gpui/src/taffy.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Refineable

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

// MARK: - LayoutId

/// A unique identifier for a layout node, generated when requesting a layout from Taffy.
public struct LayoutId: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public var description: String {
        "LayoutId(\(rawValue))"
    }
}

// MARK: - Internal Taffy Styling & Primitives (ADR-0005)

enum TaffyDimension: Sendable, Equatable {
    case length(Float)
    case percent(Float)
    case auto

    func resolve(parentSize: Float?) -> Float? {
        switch self {
        case .length(let val):
            return val
        case .percent(let pct):
            if let parent = parentSize {
                return parent * pct
            }
            return nil
        case .auto:
            return nil
        }
    }

    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }

    var isDefinite: Bool {
        if case .length = self { return true }
        return false
    }
}

enum TaffyLengthPercentage: Sendable, Equatable {
    case length(Float)
    case percent(Float)

    func resolve(parentSize: Float?) -> Float {
        switch self {
        case .length(let val):
            return val
        case .percent(let pct):
            return (parentSize ?? 0.0) * pct
        }
    }
}

struct TaffyRect<T: Sendable>: Sendable {
    var top: T
    var right: T
    var bottom: T
    var left: T
}

struct TaffyStyle: Sendable {
    var display: Display
    var position: Position
    var size: Size<TaffyDimension>
    var minSize: Size<TaffyDimension>
    var maxSize: Size<TaffyDimension>
    var aspectRatio: Float?
    var margin: TaffyRect<TaffyDimension>
    var padding: TaffyRect<TaffyLengthPercentage>
    var border: TaffyRect<Float>
    var gap: Size<TaffyLengthPercentage>
    var alignItems: AlignItems?
    var alignSelf: AlignSelf?
    var alignContent: AlignContent?
    var justifyContent: JustifyContent?
    var flexDirection: FlexDirection
    var flexWrap: FlexWrap
    var flexBasis: TaffyDimension
    var flexGrow: Float
    var flexShrink: Float
    var gridRows: GridTemplate?
    var gridCols: GridTemplate?
    var gridLocation: GridLocation?
    var inset: TaffyRect<TaffyDimension>
}

// MARK: - Style Conversion Helpers (ToTaffy)

private func toTaffyPixels(_ length: AbsoluteLength, remSize: Pixels, scaleFactor: Float) -> Float {
    switch length {
    case .pixels(let px):
        return px.value * scaleFactor
    case .rems(let rems):
        return rems.value * remSize.value * scaleFactor
    }
}

private func toTaffyDimension(_ length: Length, remSize: Pixels, scaleFactor: Float) -> TaffyDimension {
    switch length {
    case .definite(let def):
        return toTaffyDimension(def, remSize: remSize, scaleFactor: scaleFactor)
    case .auto:
        return .auto
    }
}

private func toTaffyDimension(_ length: DefiniteLength, remSize: Pixels, scaleFactor: Float) -> TaffyDimension {
    switch length {
    case .absolute(let abs):
        return .length(toTaffyPixels(abs, remSize: remSize, scaleFactor: scaleFactor))
    case .fraction(let frac):
        return .percent(frac)
    }
}

private func toTaffyLengthPercentage(_ length: DefiniteLength, remSize: Pixels, scaleFactor: Float) -> TaffyLengthPercentage {
    switch length {
    case .absolute(let abs):
        return .length(toTaffyPixels(abs, remSize: remSize, scaleFactor: scaleFactor))
    case .fraction(let frac):
        return .percent(frac)
    }
}

private func toTaffyRect(_ edges: Edges<Length>, remSize: Pixels, scaleFactor: Float) -> TaffyRect<TaffyDimension> {
    TaffyRect(
        top: toTaffyDimension(edges.top, remSize: remSize, scaleFactor: scaleFactor),
        right: toTaffyDimension(edges.right, remSize: remSize, scaleFactor: scaleFactor),
        bottom: toTaffyDimension(edges.bottom, remSize: remSize, scaleFactor: scaleFactor),
        left: toTaffyDimension(edges.left, remSize: remSize, scaleFactor: scaleFactor)
    )
}

private func toTaffyRect(_ edges: Edges<DefiniteLength>, remSize: Pixels, scaleFactor: Float) -> TaffyRect<TaffyLengthPercentage> {
    TaffyRect(
        top: toTaffyLengthPercentage(edges.top, remSize: remSize, scaleFactor: scaleFactor),
        right: toTaffyLengthPercentage(edges.right, remSize: remSize, scaleFactor: scaleFactor),
        bottom: toTaffyLengthPercentage(edges.bottom, remSize: remSize, scaleFactor: scaleFactor),
        left: toTaffyLengthPercentage(edges.left, remSize: remSize, scaleFactor: scaleFactor)
    )
}

private func toTaffyRect(_ edges: Edges<AbsoluteLength>, remSize: Pixels, scaleFactor: Float) -> TaffyRect<Float> {
    TaffyRect(
        top: toTaffyPixels(edges.top, remSize: remSize, scaleFactor: scaleFactor),
        right: toTaffyPixels(edges.right, remSize: remSize, scaleFactor: scaleFactor),
        bottom: toTaffyPixels(edges.bottom, remSize: remSize, scaleFactor: scaleFactor),
        left: toTaffyPixels(edges.left, remSize: remSize, scaleFactor: scaleFactor)
    )
}

private func toTaffyGap(_ gap: Size<DefiniteLength>, remSize: Pixels, scaleFactor: Float) -> Size<TaffyLengthPercentage> {
    Size(
        width: toTaffyLengthPercentage(gap.width, remSize: remSize, scaleFactor: scaleFactor),
        height: toTaffyLengthPercentage(gap.height, remSize: remSize, scaleFactor: scaleFactor)
    )
}

extension Style {
    fileprivate func toTaffy(remSize: Pixels, scaleFactor: Float) -> TaffyStyle {
        TaffyStyle(
            display: self.display,
            position: self.position,
            size: Size(
                width: toTaffyDimension(self.size.width, remSize: remSize, scaleFactor: scaleFactor),
                height: toTaffyDimension(self.size.height, remSize: remSize, scaleFactor: scaleFactor)
            ),
            minSize: Size(
                width: toTaffyDimension(self.minSize.width, remSize: remSize, scaleFactor: scaleFactor),
                height: toTaffyDimension(self.minSize.height, remSize: remSize, scaleFactor: scaleFactor)
            ),
            maxSize: Size(
                width: toTaffyDimension(self.maxSize.width, remSize: remSize, scaleFactor: scaleFactor),
                height: toTaffyDimension(self.maxSize.height, remSize: remSize, scaleFactor: scaleFactor)
            ),
            aspectRatio: self.aspectRatio,
            margin: toTaffyRect(self.margin, remSize: remSize, scaleFactor: scaleFactor),
            padding: toTaffyRect(self.padding, remSize: remSize, scaleFactor: scaleFactor),
            border: toTaffyRect(self.borderWidths, remSize: remSize, scaleFactor: scaleFactor),
            gap: toTaffyGap(self.gap, remSize: remSize, scaleFactor: scaleFactor),
            alignItems: self.alignItems,
            alignSelf: self.alignSelf,
            alignContent: self.alignContent,
            justifyContent: self.justifyContent,
            flexDirection: self.flexDirection,
            flexWrap: self.flexWrap,
            flexBasis: toTaffyDimension(self.flexBasis, remSize: remSize, scaleFactor: scaleFactor),
            flexGrow: self.flexGrow,
            flexShrink: self.flexShrink,
            gridRows: self.gridRows,
            gridCols: self.gridCols,
            gridLocation: self.gridLocation,
            inset: toTaffyRect(self.inset, remSize: remSize, scaleFactor: scaleFactor)
        )
    }
}

// MARK: - Layout Node Data Structures

struct NodeLayout: Sendable {
    var location: Point<Float> = Point(x: 0, y: 0)
    var size: Size<Float> = Size(width: 0, height: 0)
}

public typealias LayoutMeasureFn = @Sendable (
    Size<Pixels?>,
    Size<AvailableSpace>,
    inout Window,
    inout App
) -> Size<Pixels>

struct LayoutNode: Sendable {
    var id: LayoutId
    var style: TaffyStyle
    var children: [LayoutId]
    var parentId: LayoutId?
    var measure: LayoutMeasureFn?
    var layout: NodeLayout = NodeLayout()
}

// MARK: - TaffyLayoutEngine

private let EXPECT_MESSAGE = "we should avoid taffy layout errors by construction if possible"

/// Swift port of GPUI's layout engine wrapping Taffy 0.9.0 layout solving per ADR-0005.
public struct TaffyLayoutEngine: Sendable {
    private var nodes: [LayoutId: LayoutNode] = [:]
    private var absoluteLayoutBounds: [LayoutId: Bounds<Pixels>] = [:]
    private var computedLayouts: Set<LayoutId> = []
    private var nextId: UInt64 = 0

    public init() {}

    public static func new() -> TaffyLayoutEngine {
        TaffyLayoutEngine()
    }

    public mutating func clear() {
        nodes.removeAll()
        absoluteLayoutBounds.removeAll()
        computedLayouts.removeAll()
        nextId = 0
    }

    public mutating func requestLayout(
        style: Style,
        remSize: Pixels,
        scaleFactor: Float,
        children: [LayoutId] = []
    ) -> LayoutId {
        let taffyStyle = style.toTaffy(remSize: remSize, scaleFactor: scaleFactor)
        let id = LayoutId(nextId)
        nextId += 1
        let node = LayoutNode(id: id, style: taffyStyle, children: children)
        for childId in children {
            if var childNode = nodes[childId] {
                childNode.parentId = id
                nodes[childId] = childNode
            }
        }
        nodes[id] = node
        return id
    }

    public mutating func requestMeasuredLayout(
        style: Style,
        remSize: Pixels,
        scaleFactor: Float,
        measure: @escaping LayoutMeasureFn
    ) -> LayoutId {
        let taffyStyle = style.toTaffy(remSize: remSize, scaleFactor: scaleFactor)
        let id = LayoutId(nextId)
        nextId += 1
        let node = LayoutNode(id: id, style: taffyStyle, children: [], measure: measure)
        nodes[id] = node
        return id
    }

    public mutating func computeLayout(
        id: LayoutId,
        availableSpace: Size<AvailableSpace>,
        window: inout Window,
        cx: inout App
    ) {
        // Cache invalidation: if this layout was previously computed,
        // evict this node and all of its descendants from absoluteLayoutBounds.
        if !computedLayouts.insert(id).inserted {
            var stack = [id]
            while let currentId = stack.popLast() {
                absoluteLayoutBounds.removeValue(forKey: currentId)
                if let current = nodes[currentId] {
                    stack.append(contentsOf: current.children)
                }
            }
        }

        let scaleFactor = window.scaleFactor
        let transform = { (v: AvailableSpace) -> AvailableSpace in
            switch v {
            case .definite(let px):
                return .definite(Pixels(px.value * scaleFactor))
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

        _ = computeNode(
            id: id,
            availableWidth: scaledAvailableSpace.width,
            availableHeight: scaledAvailableSpace.height,
            scaleFactor: scaleFactor,
            window: &window,
            cx: &cx
        )
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

        guard let node = nodes[id] else {
            fatalError(EXPECT_MESSAGE)
        }

        var bounds = Bounds(
            origin: point(
                Pixels(node.layout.location.x / scaleFactor),
                Pixels(node.layout.location.y / scaleFactor)
            ),
            size: size(
                Pixels(node.layout.size.width / scaleFactor),
                Pixels(node.layout.size.height / scaleFactor)
            )
        )

        if let parentId = node.parentId {
            let parentBounds = layoutBounds(id: parentId, scaleFactor: scaleFactor)
            bounds.origin += parentBounds.origin
        }

        absoluteLayoutBounds[id] = bounds
        return bounds
    }

    // MARK: - Internal Recursive Layout Solver (ADR-0005)

    private mutating func computeNode(
        id: LayoutId,
        availableWidth: AvailableSpace,
        availableHeight: AvailableSpace,
        scaleFactor: Float,
        window: inout Window,
        cx: inout App
    ) -> Size<Float> {
        guard var node = nodes[id] else {
            return Size(width: 0, height: 0)
        }

        if node.style.display == .none {
            node.layout.size = Size(width: 0, height: 0)
            node.layout.location = Point(x: 0, y: 0)
            nodes[id] = node
            return Size(width: 0, height: 0)
        }

        let availW: Float? = {
            if case .definite(let px) = availableWidth { return px.value }
            return nil
        }()
        let availH: Float? = {
            if case .definite(let px) = availableHeight { return px.value }
            return nil
        }()

        let padLeft = node.style.padding.left.resolve(parentSize: availW)
        let padRight = node.style.padding.right.resolve(parentSize: availW)
        let padTop = node.style.padding.top.resolve(parentSize: availH)
        let padBottom = node.style.padding.bottom.resolve(parentSize: availH)

        let borderLeft = node.style.border.left
        let borderRight = node.style.border.right
        let borderTop = node.style.border.top
        let borderBottom = node.style.border.bottom

        let explicitWidth = node.style.size.width.resolve(parentSize: availW)
        let explicitHeight = node.style.size.height.resolve(parentSize: availH)

        // Leaf Node with Custom Measure Function
        if let measureFn = node.measure {
            let knownW: Pixels? = explicitWidth.map { Pixels($0 / scaleFactor) }
            let knownH: Pixels? = explicitHeight.map { Pixels($0 / scaleFactor) }
            let knownDimensions = Size<Pixels?>(width: knownW, height: knownH)

            let untransform = { (v: AvailableSpace) -> AvailableSpace in
                switch v {
                case .definite(let px):
                    return .definite(Pixels(px.value / scaleFactor))
                case .minContent:
                    return .minContent
                case .maxContent:
                    return .maxContent
                }
            }
            let unscaledAvailableSpace = Size<AvailableSpace>(
                width: untransform(availableWidth),
                height: untransform(availableHeight)
            )

            let measured = measureFn(knownDimensions, unscaledAvailableSpace, &window, &cx)
            var w = measured.width.value * scaleFactor
            var h = measured.height.value * scaleFactor

            if let ew = explicitWidth { w = ew }
            if let eh = explicitHeight { h = eh }

            let totalW = w + padLeft + padRight + borderLeft + borderRight
            let totalH = h + padTop + padBottom + borderTop + borderBottom

            let clampedW = clampDimension(totalW, minDim: node.style.minSize.width, maxDim: node.style.maxSize.width, parentSize: availW)
            let clampedH = clampDimension(totalH, minDim: node.style.minSize.height, maxDim: node.style.maxSize.height, parentSize: availH)

            node.layout.size = Size(width: clampedW.rounded(), height: clampedH.rounded())
            nodes[id] = node
            return node.layout.size
        }

        // Layout container with children
        switch node.style.display {
        case .flex:
            solveFlex(
                id: id,
                availW: availW,
                availH: availH,
                explicitWidth: explicitWidth,
                explicitHeight: explicitHeight,
                padLeft: padLeft,
                padRight: padRight,
                padTop: padTop,
                padBottom: padBottom,
                borderLeft: borderLeft,
                borderRight: borderRight,
                borderTop: borderTop,
                borderBottom: borderBottom,
                scaleFactor: scaleFactor,
                window: &window,
                cx: &cx
            )

        case .grid:
            solveGrid(
                id: id,
                availW: availW,
                availH: availH,
                explicitWidth: explicitWidth,
                explicitHeight: explicitHeight,
                padLeft: padLeft,
                padRight: padRight,
                padTop: padTop,
                padBottom: padBottom,
                borderLeft: borderLeft,
                borderRight: borderRight,
                borderTop: borderTop,
                borderBottom: borderBottom,
                scaleFactor: scaleFactor,
                window: &window,
                cx: &cx
            )

        case .block, .none:
            solveBlock(
                id: id,
                availW: availW,
                availH: availH,
                explicitWidth: explicitWidth,
                explicitHeight: explicitHeight,
                padLeft: padLeft,
                padRight: padRight,
                padTop: padTop,
                padBottom: padBottom,
                borderLeft: borderLeft,
                borderRight: borderRight,
                borderTop: borderTop,
                borderBottom: borderBottom,
                scaleFactor: scaleFactor,
                window: &window,
                cx: &cx
            )
        }

        return nodes[id]?.layout.size ?? Size(width: 0, height: 0)
    }

    // MARK: - Flexbox Layout Solver (ADR-0005)

    private struct FlexItem {
        var id: LayoutId
        var hypotheticalMain: Float
        var resolvedMain: Float
        var resolvedCross: Float
        var marginMainStart: Float
        var marginMainEnd: Float
        var marginCrossStart: Float
        var marginCrossEnd: Float
        var flexGrow: Float
        var flexShrink: Float
        var minMain: Float
        var maxMain: Float
        var minCross: Float
        var maxCross: Float
        var alignSelf: AlignSelf?
        var hasAutoCross: Bool
    }

    private mutating func solveFlex(
        id: LayoutId,
        availW: Float?,
        availH: Float?,
        explicitWidth: Float?,
        explicitHeight: Float?,
        padLeft: Float,
        padRight: Float,
        padTop: Float,
        padBottom: Float,
        borderLeft: Float,
        borderRight: Float,
        borderTop: Float,
        borderBottom: Float,
        scaleFactor: Float,
        window: inout Window,
        cx: inout App
    ) {
        guard var node = nodes[id] else { return }

        let isRow = (node.style.flexDirection == .row || node.style.flexDirection == .rowReverse)
        let isReverse = (node.style.flexDirection == .rowReverse || node.style.flexDirection == .columnReverse)

        let mainPadBorderStart = isRow ? (padLeft + borderLeft) : (padTop + borderTop)
        let mainPadBorderEnd = isRow ? (padRight + borderRight) : (padBottom + borderBottom)
        let crossPadBorderStart = isRow ? (padTop + borderTop) : (padLeft + borderLeft)
        let crossPadBorderEnd = isRow ? (padBottom + borderBottom) : (padRight + borderRight)

        let mainGap = isRow ? node.style.gap.width.resolve(parentSize: availW) : node.style.gap.height.resolve(parentSize: availH)
        let crossGap = isRow ? node.style.gap.height.resolve(parentSize: availH) : node.style.gap.width.resolve(parentSize: availW)

        let explicitMain = isRow ? explicitWidth : explicitHeight
        let explicitCross = isRow ? explicitHeight : explicitWidth

        let containerInnerMain: Float? = {
            if let em = explicitMain {
                return Swift.max(0, em - mainPadBorderStart - mainPadBorderEnd)
            } else if let pMain = (isRow ? availW : availH) {
                return Swift.max(0, pMain - mainPadBorderStart - mainPadBorderEnd)
            }
            return nil
        }()

        var flowItems: [FlexItem] = []
        var absoluteChildren: [LayoutId] = []

        for childId in node.children {
            guard let child = nodes[childId] else { continue }
            if child.style.position == .absolute {
                absoluteChildren.append(childId)
                continue
            }

            let childMarginLeft = child.style.margin.left.resolve(parentSize: containerInnerMain) ?? 0
            let childMarginRight = child.style.margin.right.resolve(parentSize: containerInnerMain) ?? 0
            let childMarginTop = child.style.margin.top.resolve(parentSize: containerInnerMain) ?? 0
            let childMarginBottom = child.style.margin.bottom.resolve(parentSize: containerInnerMain) ?? 0

            let mMainStart = isRow ? childMarginLeft : childMarginTop
            let mMainEnd = isRow ? childMarginRight : childMarginBottom
            let mCrossStart = isRow ? childMarginTop : childMarginLeft
            let mCrossEnd = isRow ? childMarginBottom : childMarginRight

            let childMainDim = isRow ? child.style.size.width : child.style.size.height
            let childCrossDim = isRow ? child.style.size.height : child.style.size.width
            let childMinMain = isRow ? child.style.minSize.width : child.style.minSize.height
            let childMaxMain = isRow ? child.style.maxSize.width : child.style.maxSize.height
            let childMinCross = isRow ? child.style.minSize.height : child.style.minSize.width
            let childMaxCross = isRow ? child.style.maxSize.height : child.style.maxSize.width

            let minMainVal = childMinMain.resolve(parentSize: containerInnerMain) ?? 0
            let maxMainVal = childMaxMain.resolve(parentSize: containerInnerMain) ?? Float.infinity
            let minCrossVal = childMinCross.resolve(parentSize: nil) ?? 0
            let maxCrossVal = childMaxCross.resolve(parentSize: nil) ?? Float.infinity

            var hypotheticalMain: Float = 0
            if let basis = child.style.flexBasis.resolve(parentSize: containerInnerMain) {
                hypotheticalMain = basis
            } else if let explicitChildMain = childMainDim.resolve(parentSize: containerInnerMain) {
                hypotheticalMain = explicitChildMain
            } else {
                let availWChild = isRow ? AvailableSpace.minContent : (containerInnerMain.map { AvailableSpace.definite(Pixels($0)) } ?? .minContent)
                let availHChild = isRow ? (containerInnerMain.map { AvailableSpace.definite(Pixels($0)) } ?? .minContent) : AvailableSpace.minContent
                let initialSize = computeNode(
                    id: childId,
                    availableWidth: availWChild,
                    availableHeight: availHChild,
                    scaleFactor: scaleFactor,
                    window: &window,
                    cx: &cx
                )
                hypotheticalMain = isRow ? initialSize.width : initialSize.height
            }
            hypotheticalMain = Swift.max(minMainVal, Swift.min(maxMainVal, hypotheticalMain))

            flowItems.append(FlexItem(
                id: childId,
                hypotheticalMain: hypotheticalMain,
                resolvedMain: hypotheticalMain,
                resolvedCross: 0,
                marginMainStart: mMainStart,
                marginMainEnd: mMainEnd,
                marginCrossStart: mCrossStart,
                marginCrossEnd: mCrossEnd,
                flexGrow: child.style.flexGrow,
                flexShrink: child.style.flexShrink,
                minMain: minMainVal,
                maxMain: maxMainVal,
                minCross: minCrossVal,
                maxCross: maxCrossVal,
                alignSelf: child.style.alignSelf,
                hasAutoCross: childCrossDim.isAuto
            ))
        }

        // Flex lines collection
        var lines: [[FlexItem]] = []
        var currentLine: [FlexItem] = []
        var currentLineMain: Float = 0

        for item in flowItems {
            let itemOuter = item.hypotheticalMain + item.marginMainStart + item.marginMainEnd
            let nextLineMain = currentLine.isEmpty ? itemOuter : (currentLineMain + mainGap + itemOuter)

            if (node.style.flexWrap == .wrap || node.style.flexWrap == .wrapReverse),
               let maxMain = containerInnerMain,
               !currentLine.isEmpty,
               nextLineMain > maxMain {
                lines.append(currentLine)
                currentLine = [item]
                currentLineMain = itemOuter
            } else {
                currentLine.append(item)
                currentLineMain = nextLineMain
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        if lines.isEmpty {
            lines.append([])
        }

        // Resolve flexible lengths per line (Flex Grow & Shrink)
        for lineIdx in 0..<lines.count {
            let lineItems = lines[lineIdx]
            let sumHypothetical = lineItems.reduce(0.0) { $0 + $1.hypotheticalMain + $1.marginMainStart + $1.marginMainEnd }
            let totalLineMain = sumHypothetical + Float(Swift.max(0, lineItems.count - 1)) * mainGap

            if let innerMain = containerInnerMain {
                let freeSpace = innerMain - totalLineMain
                if freeSpace > 0.0001 {
                    let totalGrow = lineItems.reduce(0.0) { $0 + $1.flexGrow }
                    if totalGrow > 0 {
                        for i in 0..<lines[lineIdx].count {
                            let share = (lines[lineIdx][i].flexGrow / totalGrow) * freeSpace
                            lines[lineIdx][i].resolvedMain = Swift.min(lines[lineIdx][i].maxMain, lines[lineIdx][i].hypotheticalMain + share)
                        }
                    }
                } else if freeSpace < -0.0001 {
                    let totalShrinkWeighted = lineItems.reduce(0.0) { $0 + $1.flexShrink * $1.hypotheticalMain }
                    if totalShrinkWeighted > 0 {
                        for i in 0..<lines[lineIdx].count {
                            let shrinkAmount = ((lines[lineIdx][i].flexShrink * lines[lineIdx][i].hypotheticalMain) / totalShrinkWeighted) * (-freeSpace)
                            lines[lineIdx][i].resolvedMain = Swift.max(lines[lineIdx][i].minMain, lines[lineIdx][i].hypotheticalMain - shrinkAmount)
                        }
                    } else {
                        let totalShrink = lineItems.reduce(0.0) { $0 + $1.flexShrink }
                        if totalShrink > 0 {
                            for i in 0..<lines[lineIdx].count {
                                let shrinkAmount = (lines[lineIdx][i].flexShrink / totalShrink) * (-freeSpace)
                                lines[lineIdx][i].resolvedMain = Swift.max(lines[lineIdx][i].minMain, lines[lineIdx][i].hypotheticalMain - shrinkAmount)
                            }
                        }
                    }
                }
            }
        }

        // Cross sizing items and lines
        var lineCrossSizes: [Float] = []
        for lineIdx in 0..<lines.count {
            var maxCross: Float = 0
            for i in 0..<lines[lineIdx].count {
                let item = lines[lineIdx][i]
                let childAvailW = isRow ? AvailableSpace.definite(Pixels(item.resolvedMain)) : (availW.map { AvailableSpace.definite(Pixels($0)) } ?? .minContent)
                let childAvailH = isRow ? (availH.map { AvailableSpace.definite(Pixels($0)) } ?? .minContent) : AvailableSpace.definite(Pixels(item.resolvedMain))
                let childSize = computeNode(
                    id: item.id,
                    availableWidth: childAvailW,
                    availableHeight: childAvailH,
                    scaleFactor: scaleFactor,
                    window: &window,
                    cx: &cx
                )
                let resolvedCross = isRow ? childSize.height : childSize.width
                lines[lineIdx][i].resolvedCross = resolvedCross
                let outerCross = resolvedCross + item.marginCrossStart + item.marginCrossEnd
                maxCross = Swift.max(maxCross, outerCross)
            }
            lineCrossSizes.append(maxCross)
        }

        // AlignItems: stretch
        for lineIdx in 0..<lines.count {
            let lineCross = lineCrossSizes[lineIdx]
            for i in 0..<lines[lineIdx].count {
                let alignment = lines[lineIdx][i].alignSelf ?? node.style.alignItems ?? .flexStart
                if alignment == .stretch, lines[lineIdx][i].hasAutoCross {
                    let availCross = Swift.max(lines[lineIdx][i].minCross, Swift.min(lines[lineIdx][i].maxCross, lineCross - lines[lineIdx][i].marginCrossStart - lines[lineIdx][i].marginCrossEnd))
                    if availCross != lines[lineIdx][i].resolvedCross {
                        lines[lineIdx][i].resolvedCross = availCross
                        let childAvailW = isRow ? AvailableSpace.definite(Pixels(lines[lineIdx][i].resolvedMain)) : AvailableSpace.definite(Pixels(availCross))
                        let childAvailH = isRow ? AvailableSpace.definite(Pixels(availCross)) : AvailableSpace.definite(Pixels(lines[lineIdx][i].resolvedMain))
                        _ = computeNode(
                            id: lines[lineIdx][i].id,
                            availableWidth: childAvailW,
                            availableHeight: childAvailH,
                            scaleFactor: scaleFactor,
                            window: &window,
                            cx: &cx
                        )
                    }
                }
            }
        }

        // Container sizing
        var maxLineResolvedMain: Float = 0
        for line in lines {
            let lineItemsWidth: Float = line.reduce(Float(0.0)) { (sum: Float, item) -> Float in
                sum + item.resolvedMain + item.marginMainStart + item.marginMainEnd
            }
            let gaps: Float = Float(Swift.max(0, line.count - 1)) * mainGap
            maxLineResolvedMain = Swift.max(maxLineResolvedMain, lineItemsWidth + gaps)
        }

        let sumLinesCross: Float = lineCrossSizes.reduce(Float(0.0), +) + Float(Swift.max(0, lines.count - 1)) * crossGap

        let resolvedInnerMain = explicitMain ?? (containerInnerMain ?? maxLineResolvedMain)
        let resolvedInnerCross = explicitCross ?? sumLinesCross

        let totalWidth = isRow
            ? (resolvedInnerMain + mainPadBorderStart + mainPadBorderEnd)
            : (resolvedInnerCross + crossPadBorderStart + crossPadBorderEnd)
        let totalHeight = isRow
            ? (resolvedInnerCross + crossPadBorderStart + crossPadBorderEnd)
            : (resolvedInnerMain + mainPadBorderStart + mainPadBorderEnd)

        let clampedWidth = clampDimension(totalWidth, minDim: node.style.minSize.width, maxDim: node.style.maxSize.width, parentSize: availW)
        let clampedHeight = clampDimension(totalHeight, minDim: node.style.minSize.height, maxDim: node.style.maxSize.height, parentSize: availH)
        node.layout.size = Size(width: clampedWidth.rounded(), height: clampedHeight.rounded())

        // Positioning items on lines
        var lineCrossStart = crossPadBorderStart
        if node.style.flexWrap == .wrapReverse {
            lineCrossStart = (isRow ? clampedHeight : clampedWidth) - crossPadBorderEnd - sumLinesCross
        }

        for lineIdx in 0..<lines.count {
            let line = lines[lineIdx]
            let lineCrossSize = lineCrossSizes[lineIdx]
            let lineItemsMain = line.reduce(0.0) { $0 + $1.resolvedMain + $1.marginMainStart + $1.marginMainEnd }
            let freeMain = Swift.max(0, resolvedInnerMain - lineItemsMain - Float(Swift.max(0, line.count - 1)) * mainGap)

            var mainOffset = mainPadBorderStart
            var extraItemGap: Float = 0
            let justify = node.style.justifyContent ?? .flexStart
            switch justify {
            case .flexStart, .start:
                mainOffset = mainPadBorderStart
            case .flexEnd, .end:
                mainOffset = mainPadBorderStart + freeMain
            case .center:
                mainOffset = mainPadBorderStart + freeMain / 2.0
            case .spaceBetween:
                extraItemGap = line.count > 1 ? (freeMain / Float(line.count - 1)) : 0
            case .spaceAround:
                extraItemGap = line.count > 0 ? (freeMain / Float(line.count)) : 0
                mainOffset = mainPadBorderStart + extraItemGap / 2.0
            case .spaceEvenly:
                extraItemGap = line.count > 0 ? (freeMain / Float(line.count + 1)) : 0
                mainOffset = mainPadBorderStart + extraItemGap
            default:
                mainOffset = mainPadBorderStart
            }

            for item in line {
                let itemAlignment = item.alignSelf ?? node.style.alignItems ?? .flexStart
                var crossOffset = lineCrossStart + item.marginCrossStart
                switch itemAlignment {
                case .flexStart, .start, .stretch:
                    crossOffset = lineCrossStart + item.marginCrossStart
                case .flexEnd, .end:
                    crossOffset = lineCrossStart + lineCrossSize - item.marginCrossEnd - item.resolvedCross
                case .center:
                    crossOffset = lineCrossStart + item.marginCrossStart + (lineCrossSize - (item.resolvedCross + item.marginCrossStart + item.marginCrossEnd)) / 2.0
                default:
                    crossOffset = lineCrossStart + item.marginCrossStart
                }

                if var childNode = nodes[item.id] {
                    let childX: Float
                    let childY: Float
                    if isRow {
                        if isReverse {
                            childX = clampedWidth - mainPadBorderEnd - (mainOffset - mainPadBorderStart) - item.resolvedMain - item.marginMainEnd
                        } else {
                            childX = mainOffset + item.marginMainStart
                        }
                        childY = crossOffset
                    } else {
                        childX = crossOffset
                        if isReverse {
                            childY = clampedHeight - mainPadBorderEnd - (mainOffset - mainPadBorderStart) - item.resolvedMain - item.marginMainEnd
                        } else {
                            childY = mainOffset + item.marginMainStart
                        }
                    }
                    childNode.layout.location = Point(x: childX.rounded(), y: childY.rounded())
                    childNode.layout.size = Size(
                        width: (isRow ? item.resolvedMain : item.resolvedCross).rounded(),
                        height: (isRow ? item.resolvedCross : item.resolvedMain).rounded()
                    )
                    nodes[item.id] = childNode
                }

                mainOffset += item.resolvedMain + item.marginMainStart + item.marginMainEnd + mainGap + extraItemGap
            }

            lineCrossStart += lineCrossSize + crossGap
        }

        // Layout absolute children
        for absId in absoluteChildren {
            if var childNode = nodes[absId] {
                let childSize = computeNode(
                    id: absId,
                    availableWidth: .definite(Pixels(clampedWidth)),
                    availableHeight: .definite(Pixels(clampedHeight)),
                    scaleFactor: scaleFactor,
                    window: &window,
                    cx: &cx
                )
                var posX = padLeft + borderLeft
                if case .length(let left) = childNode.style.inset.left {
                    posX = padLeft + borderLeft + left
                } else if case .length(let right) = childNode.style.inset.right {
                    posX = clampedWidth - padRight - borderRight - childSize.width - right
                }

                var posY = padTop + borderTop
                if case .length(let top) = childNode.style.inset.top {
                    posY = padTop + borderTop + top
                } else if case .length(let bottom) = childNode.style.inset.bottom {
                    posY = clampedHeight - padBottom - borderBottom - childSize.height - bottom
                }

                childNode.layout.location = Point(x: posX.rounded(), y: posY.rounded())
                nodes[absId] = childNode
            }
        }

        nodes[id] = node
    }

    // MARK: - CSS Grid Layout Solver (ADR-0005)

    private mutating func solveGrid(
        id: LayoutId,
        availW: Float?,
        availH: Float?,
        explicitWidth: Float?,
        explicitHeight: Float?,
        padLeft: Float,
        padRight: Float,
        padTop: Float,
        padBottom: Float,
        borderLeft: Float,
        borderRight: Float,
        borderTop: Float,
        borderBottom: Float,
        scaleFactor: Float,
        window: inout Window,
        cx: inout App
    ) {
        guard var node = nodes[id] else { return }

        let colGap = node.style.gap.width.resolve(parentSize: availW)
        let rowGap = node.style.gap.height.resolve(parentSize: availH)

        var colCount = Int(node.style.gridCols?.repeat ?? 0)
        for childId in node.children {
            if let child = nodes[childId], let loc = child.style.gridLocation, !loc.column.isEmpty {
                colCount = Swift.max(colCount, loc.column.upperBound)
            }
        }
        if colCount <= 0 { colCount = Swift.max(1, node.children.count) }

        var rowCount = Int(node.style.gridRows?.repeat ?? 0)
        for childId in node.children {
            if let child = nodes[childId], let loc = child.style.gridLocation, !loc.row.isEmpty {
                rowCount = Swift.max(rowCount, loc.row.upperBound)
            }
        }
        if rowCount <= 0 { rowCount = Swift.max(1, (node.children.count + colCount - 1) / colCount) }

        // Grid item placement
        var placedItems: [(id: LayoutId, row: Range<Int>, col: Range<Int>)] = []
        var occupied = Array(repeating: Array(repeating: false, count: colCount), count: Swift.max(100, rowCount + 10))

        for childId in node.children {
            guard let child = nodes[childId] else { continue }
            if let loc = child.style.gridLocation, !loc.row.isEmpty, !loc.column.isEmpty {
                placedItems.append((id: childId, row: loc.row, col: loc.column))
                for r in loc.row {
                    while occupied.count <= r { occupied.append(Array(repeating: false, count: colCount)) }
                    for c in loc.column where c < colCount {
                        occupied[r][c] = true
                    }
                }
            } else {
                var autoRow = 0
                var autoCol = 0
                findCell: while true {
                    while occupied.count <= autoRow { occupied.append(Array(repeating: false, count: colCount)) }
                    if !occupied[autoRow][autoCol] {
                        break findCell
                    }
                    autoCol += 1
                    if autoCol >= colCount {
                        autoCol = 0
                        autoRow += 1
                    }
                }
                occupied[autoRow][autoCol] = true
                placedItems.append((id: childId, row: autoRow..<(autoRow + 1), col: autoCol..<(autoCol + 1)))
            }
        }

        for item in placedItems {
            rowCount = Swift.max(rowCount, item.row.upperBound)
        }

        let innerW = Swift.max(0, (explicitWidth ?? availW ?? 0) - padLeft - padRight - borderLeft - borderRight - Float(colCount - 1) * colGap)
        let innerH = Swift.max(0, (explicitHeight ?? availH ?? 0) - padTop - padBottom - borderTop - borderBottom - Float(rowCount - 1) * rowGap)

        var colWidths: [Float] = []
        let singleColW = innerW / Float(colCount)
        for _ in 0..<colCount {
            colWidths.append(singleColW)
        }

        var rowHeights: [Float] = []
        if explicitHeight != nil || availH != nil {
            let singleRowH = innerH / Float(rowCount)
            for _ in 0..<rowCount {
                rowHeights.append(singleRowH)
            }
        } else {
            // Measure row heights from child content
            rowHeights = Array(repeating: 0, count: rowCount)
            for item in placedItems {
                let spanColsW = (item.col.lowerBound..<Swift.min(colCount, item.col.upperBound)).reduce(0.0) { $0 + colWidths[$1] }
                let measured = computeNode(
                    id: item.id,
                    availableWidth: .definite(Pixels(spanColsW)),
                    availableHeight: .minContent,
                    scaleFactor: scaleFactor,
                    window: &window,
                    cx: &cx
                )
                let itemSpan = Float(Swift.max(1, item.row.count))
                let perRowH = measured.height / itemSpan
                for r in item.row where r < rowCount {
                    rowHeights[r] = Swift.max(rowHeights[r], perRowH)
                }
            }
        }

        var colX = [padLeft + borderLeft]
        for c in 0..<colCount {
            colX.append(colX[c] + colWidths[c] + colGap)
        }
        var rowY = [padTop + borderTop]
        for r in 0..<rowCount {
            rowY.append(rowY[r] + rowHeights[r] + rowGap)
        }

        for item in placedItems {
            if var child = nodes[item.id] {
                let startC = Swift.min(colCount - 1, Swift.max(0, item.col.lowerBound))
                let endC = Swift.min(colCount, Swift.max(startC + 1, item.col.upperBound))
                let startR = Swift.min(rowCount - 1, Swift.max(0, item.row.lowerBound))
                let endR = Swift.min(rowCount, Swift.max(startR + 1, item.row.upperBound))

                let itemW = (startC..<endC).reduce(0.0) { $0 + colWidths[$1] } + Float(endC - startC - 1) * colGap
                let itemH = (startR..<endR).reduce(0.0) { $0 + rowHeights[$1] } + Float(endR - startR - 1) * rowGap

                _ = computeNode(
                    id: item.id,
                    availableWidth: .definite(Pixels(itemW)),
                    availableHeight: .definite(Pixels(itemH)),
                    scaleFactor: scaleFactor,
                    window: &window,
                    cx: &cx
                )
                child.layout.location = Point(x: colX[startC].rounded(), y: rowY[startR].rounded())
                child.layout.size = Size(width: itemW.rounded(), height: itemH.rounded())
                nodes[item.id] = child
            }
        }

        let totalGridW = (0..<colCount).reduce(0.0) { $0 + colWidths[$1] } + Float(colCount - 1) * colGap + padLeft + padRight + borderLeft + borderRight
        let totalGridH = (0..<rowCount).reduce(0.0) { $0 + rowHeights[$1] } + Float(rowCount - 1) * rowGap + padTop + padBottom + borderTop + borderBottom

        let clampedW = clampDimension(totalGridW, minDim: node.style.minSize.width, maxDim: node.style.maxSize.width, parentSize: availW)
        let clampedH = clampDimension(totalGridH, minDim: node.style.minSize.height, maxDim: node.style.maxSize.height, parentSize: availH)
        node.layout.size = Size(width: clampedW.rounded(), height: clampedH.rounded())
        nodes[id] = node
    }

    // MARK: - Block Layout Solver (ADR-0005)

    private mutating func solveBlock(
        id: LayoutId,
        availW: Float?,
        availH: Float?,
        explicitWidth: Float?,
        explicitHeight: Float?,
        padLeft: Float,
        padRight: Float,
        padTop: Float,
        padBottom: Float,
        borderLeft: Float,
        borderRight: Float,
        borderTop: Float,
        borderBottom: Float,
        scaleFactor: Float,
        window: inout Window,
        cx: inout App
    ) {
        guard var node = nodes[id] else { return }

        let childAvailW = Swift.max(0, (explicitWidth ?? availW ?? 0) - padLeft - padRight - borderLeft - borderRight)
        var currentY = padTop + borderTop
        var maxChildW: Float = 0

        for childId in node.children {
            guard var child = nodes[childId] else { continue }
            if child.style.position == .absolute {
                continue
            }

            let mTop = child.style.margin.top.resolve(parentSize: childAvailW) ?? 0
            let mBottom = child.style.margin.bottom.resolve(parentSize: childAvailW) ?? 0
            let mLeft = child.style.margin.left.resolve(parentSize: childAvailW) ?? 0
            let mRight = child.style.margin.right.resolve(parentSize: childAvailW) ?? 0

            let innerChildAvailW = Swift.max(0, childAvailW - mLeft - mRight)
            let childSize = computeNode(
                id: childId,
                availableWidth: .definite(Pixels(innerChildAvailW)),
                availableHeight: .minContent,
                scaleFactor: scaleFactor,
                window: &window,
                cx: &cx
            )

            child.layout.location = Point(
                x: (padLeft + borderLeft + mLeft).rounded(),
                y: (currentY + mTop).rounded()
            )
            nodes[childId] = child

            currentY += childSize.height + mTop + mBottom
            maxChildW = Swift.max(maxChildW, childSize.width + mLeft + mRight)
        }

        let innerW = explicitWidth ?? maxChildW
        let innerH = explicitHeight ?? (currentY - (padTop + borderTop))

        let totalW = innerW + padLeft + padRight + borderLeft + borderRight
        let totalH = innerH + padTop + padBottom + borderTop + borderBottom

        let clampedW = clampDimension(totalW, minDim: node.style.minSize.width, maxDim: node.style.maxSize.width, parentSize: availW)
        let clampedH = clampDimension(totalH, minDim: node.style.minSize.height, maxDim: node.style.maxSize.height, parentSize: availH)
        node.layout.size = Size(width: clampedW.rounded(), height: clampedH.rounded())
        nodes[id] = node
    }
}

// MARK: - Clamping Helper

private func clampDimension(_ value: Float, minDim: TaffyDimension, maxDim: TaffyDimension, parentSize: Float?) -> Float {
    var result = value
    if let minVal = minDim.resolve(parentSize: parentSize) {
        result = Swift.max(minVal, result)
    }
    if let maxVal = maxDim.resolve(parentSize: parentSize) {
        result = Swift.min(maxVal, result)
    }
    return result
}
