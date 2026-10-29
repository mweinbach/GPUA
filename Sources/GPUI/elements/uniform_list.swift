// Ported from: crates/gpui/src/elements/uniform_list.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Refineable

/// uniform_list provides lazy rendering for a set of items that are of uniform height.
/// When rendered into a container with overflow-y: hidden and a fixed (or max) height,
/// uniform_list will only render the visible subset of items.
public func uniformList(
    _ id: ElementId,
    _ itemCount: Int,
    _ f: @escaping @Sendable (Range<Int>, inout Window, inout App) -> [AnyElement]
) -> UniformList {
    let id = id
    var baseStyle = StyleRefinement()
    baseStyle.overflow.y = .scroll

    var interactivity = Interactivity()
    interactivity.elementId = id
    interactivity.baseStyle = baseStyle

    return UniformList(
        itemCount: itemCount,
        itemToMeasureIndex: 0,
        renderItems: f,
        decorations: [],
        interactivity: interactivity,
        scrollHandle: nil,
        sizingBehavior: .auto,
        horizontalSizingBehavior: .fitList
    )
}

/// A list element for efficiently laying out and displaying a list of uniform-height elements.
public struct UniformList: Element, IntoElement, Styled, InteractiveElement {
    public typealias RequestLayoutState = UniformListFrameState
    public typealias PrepaintState = Hitbox?

    public var itemCount: Int
    public var itemToMeasureIndex: Int
    public var renderItems: @Sendable (Range<Int>, inout Window, inout App) -> [AnyElement]
    public var decorations: [any UniformListDecoration]
    public var interactivity: Interactivity
    public var scrollHandle: UniformListScrollHandle?
    public var sizingBehavior: ListSizingBehavior
    public var horizontalSizingBehavior: ListHorizontalSizingBehavior

    public init(
        itemCount: Int,
        itemToMeasureIndex: Int = 0,
        renderItems: @escaping @Sendable (Range<Int>, inout Window, inout App) -> [AnyElement],
        decorations: [any UniformListDecoration] = [],
        interactivity: Interactivity = Interactivity(),
        scrollHandle: UniformListScrollHandle? = nil,
        sizingBehavior: ListSizingBehavior = .auto,
        horizontalSizingBehavior: ListHorizontalSizingBehavior = .fitList
    ) {
        self.itemCount = itemCount
        self.itemToMeasureIndex = itemToMeasureIndex
        self.renderItems = renderItems
        self.decorations = decorations
        self.interactivity = interactivity
        self.scrollHandle = scrollHandle
        self.sizingBehavior = sizingBehavior
        self.horizontalSizingBehavior = horizontalSizingBehavior
    }

    public func id() -> ElementId? {
        self.interactivity.elementId
    }

    public func sourceLocation() -> (String, Int)? {
        nil
    }

    /// Selects a specific list item for measurement.
    public func withWidthFromItem(_ itemIndex: Int?) -> Self {
        var copy = self
        copy.itemToMeasureIndex = itemIndex ?? 0
        return copy
    }

    /// Sets the sizing behavior, similar to the `List` element.
    public func withSizingBehavior(_ behavior: ListSizingBehavior) -> Self {
        var copy = self
        copy.sizingBehavior = behavior
        return copy
    }

    /// Sets the horizontal sizing behavior, controlling the way list items laid out horizontally.
    public func withHorizontalSizingBehavior(_ behavior: ListHorizontalSizingBehavior) -> Self {
        var copy = self
        copy.horizontalSizingBehavior = behavior
        switch behavior {
        case .fitList:
            copy.interactivity.baseStyle.overflow.x = nil
        case .unconstrained:
            copy.interactivity.baseStyle.overflow.x = .scroll
        }
        return copy
    }

    /// Adds a decoration element to the list.
    public func withDecoration(_ decoration: any UniformListDecoration) -> Self {
        var copy = self
        copy.decorations.append(decoration)
        return copy
    }

    /// Track and render scroll state of this list with reference to the given scroll handle.
    public func trackScroll(_ handle: UniformListScrollHandle) -> Self {
        var copy = self
        copy.interactivity.trackedScrollHandle = handle.inner.baseHandle
        copy.scrollHandle = handle
        return copy
    }

    /// Sets whether the list is flipped vertically, such that item 0 appears at the bottom.
    public func yFlipped(_ yFlipped: Bool) -> Self {
        if let scrollHandle = self.scrollHandle {
            let offset = scrollHandle.inner.baseHandle.offset()
            if let lastSize = scrollHandle.inner.lastItemSize, scrollHandle.inner.yFlipped != yFlipped {
                let newYOffset = -(offset.y + lastSize.contents.height - lastSize.item.height)
                scrollHandle.inner.baseHandle.setOffset(Point(x: offset.x, y: newYOffset))
                scrollHandle.inner.yFlipped = yFlipped
            } else if scrollHandle.inner.lastItemSize == nil && yFlipped {
                scrollHandle.inner.baseHandle.setOffset(Point(x: offset.x, y: Pixels(-Float.greatestFiniteMagnitude)))
                scrollHandle.inner.yFlipped = yFlipped
            }
        }
        return self
    }

    @MainActor
    private func measureItem(listWidth: Pixels?, window: inout Window, cx: inout App) -> Size<Pixels> {
        if itemCount == 0 {
            return .zero
        }
        let itemIx = min(itemToMeasureIndex, itemCount - 1)
        var items = renderItems(itemIx..<(itemIx + 1), &window, &cx)
        guard var itemToMeasure = items.popLast() else {
            return .zero
        }
        let availableSpace = Size(
            width: listWidth.map { AvailableSpace.definite($0) } ?? AvailableSpace.minContent,
            height: AvailableSpace.minContent
        )
        return itemToMeasure.layoutAsRoot(availableSpace, &window, &cx)
    }

    @MainActor
    public mutating func requestLayout(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, UniformListFrameState) {
        let maxItems = self.itemCount
        let itemSize = self.measureItem(listWidth: nil, window: &window, cx: &cx)

        let layoutId = self.interactivity.requestLayout(globalId, inspectorId, &window, &cx) { style, window, cx in
            switch self.sizingBehavior {
            case .infer:
                return window.withTextStyle(style.textStyle()) { window in
                    window.requestMeasuredLayout(style: style) { knownDimensions, availableSpace, _, _ in
                        let desiredHeight = itemSize.height * Float(maxItems)
                        let width: Pixels
                        if let knownWidth = knownDimensions.width {
                            width = knownWidth
                        } else {
                            switch availableSpace.width {
                            case .definite(let x): width = x
                            case .minContent, .maxContent: width = itemSize.width
                            }
                        }
                        let height: Pixels
                        switch availableSpace.height {
                        case .definite(let h): height = min(desiredHeight, h)
                        case .minContent, .maxContent: height = desiredHeight
                        }
                        return Size(width: width, height: height)
                    }
                }
            case .auto:
                return window.withTextStyle(style.textStyle()) { window in
                    window.requestLayout(style, [], &cx)
                }
            }
        }

        return (layoutId, UniformListFrameState(items: [], decorations: []))
    }

    @MainActor
    public mutating func prepaint(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ frameState: inout UniformListFrameState,
        _ window: inout Window,
        _ cx: inout App
    ) -> Hitbox? {
        let style = self.interactivity.computeStyle(globalId, nil, &window, &cx)
        let border = style.borderWidths.toPixels(remSize: window.remSize)
        let padding = style.padding.toPixels(parentSize: bounds.size, remSize: window.remSize)

        let paddedBounds = Bounds.fromCorners(
            bounds.origin + Point(x: border.left + padding.left, y: border.top + padding.top),
            bounds.bottomRight - Point(x: border.right + padding.right, y: border.bottom + padding.bottom)
        )

        let canScrollHorizontally = (self.horizontalSizingBehavior == .unconstrained)
        let longestItemSize = self.measureItem(listWidth: nil, window: &window, cx: &cx)
        let contentWidth = canScrollHorizontally ? max(paddedBounds.size.width, longestItemSize.width) : paddedBounds.size.width
        let contentSize = Size(
            width: contentWidth,
            height: longestItemSize.height * Float(self.itemCount)
        )

        let itemHeight = longestItemSize.height
        let sharedScrollToItem: DeferredScrollToItem?
        if let handle = self.scrollHandle {
            handle.inner.lastItemSize = ItemSize(item: paddedBounds.size, contents: contentSize)
            sharedScrollToItem = handle.inner.deferredScrollToItem
            handle.inner.deferredScrollToItem = nil
        } else {
            sharedScrollToItem = nil
        }

        let decorationsCopy = self.decorations
        let itemCountCopy = self.itemCount
        let renderItemsCopy = self.renderItems
        let scrollHandleCopy = self.scrollHandle

        return self.interactivity.prepaint(
            globalId,
            inspectorId,
            bounds,
            contentSize,
            &window,
            &cx
        ) { _, scrollOffsetVal, hitbox, window, cx in
            var scrollOffset = scrollOffsetVal
            let yFlipped = scrollHandleCopy?.inner.yFlipped ?? false

            if itemCountCopy > 0 && itemHeight > .zero {
                let contentHeight = itemHeight * Float(itemCountCopy)
                let isScrolledVertically = scrollOffset.y != .zero
                let maxScrollOffset = paddedBounds.size.height - contentHeight

                if isScrolledVertically && scrollOffset.y < maxScrollOffset {
                    scrollOffset.y = maxScrollOffset
                }

                let fullContentWidth = contentSize.width + padding.left + padding.right
                let isScrolledHorizontally = canScrollHorizontally && scrollOffset.x != .zero
                if isScrolledHorizontally && fullContentWidth <= paddedBounds.size.width {
                    scrollOffset.x = .zero
                }

                if var deferred = sharedScrollToItem {
                    if yFlipped {
                        deferred.itemIndex = max(0, itemCountCopy - (deferred.itemIndex + 1))
                    }
                    let listHeight = paddedBounds.size.height
                    let itemTop = itemHeight * Float(deferred.itemIndex)
                    let itemBottom = itemTop + itemHeight
                    let scrollTop = -scrollOffset.y
                    let offsetPixels = itemHeight * Float(deferred.offset)

                    let isAbove = itemTop < scrollTop + offsetPixels
                    let isBelow = itemBottom > scrollTop + listHeight

                    if deferred.scrollStrict || isAbove || isBelow {
                        var strategy = deferred.strategy
                        if strategy == .nearest {
                            if isAbove {
                                strategy = .top
                            } else if isBelow {
                                strategy = .bottom
                            }
                        }

                        let maxScrollOffset = Swift.max(Pixels.zero, contentHeight - listHeight)
                        switch strategy {
                        case .top:
                            let target = -(itemTop - offsetPixels)
                            scrollOffset.y = Swift.min(Pixels.zero, Swift.max(-maxScrollOffset, target))
                        case .center:
                            let itemCenter = itemTop + itemHeight / 2.0
                            let viewportHeight = listHeight - offsetPixels
                            let viewportCenter = offsetPixels + viewportHeight / 2.0
                            let targetScrollTop = itemCenter - viewportCenter
                            let target = -targetScrollTop
                            scrollOffset.y = Swift.min(Pixels.zero, Swift.max(-maxScrollOffset, target))
                        case .bottom:
                            let target = -(itemBottom - listHeight)
                            scrollOffset.y = Swift.min(Pixels.zero, Swift.max(-maxScrollOffset, target))
                        case .nearest:
                            break
                        }
                    }
                }

                if let handle = scrollHandleCopy {
                    handle.inner.baseHandle.setOffset(scrollOffset)
                }

                // Cross-platform math rule: use stdlib rounded(.down)/rounded(.up)
                let firstVal = (-(scrollOffset.y + padding.top) / itemHeight).rounded(.down)
                let firstVisibleElementIx = Swift.max(0, Int(firstVal))
                let lastVal = ((-scrollOffset.y + paddedBounds.size.height) / itemHeight).rounded(.up)
                let lastVisibleElementIx = Swift.max(0, Int(lastVal))

                let visibleRange = firstVisibleElementIx..<min(lastVisibleElementIx, itemCountCopy)

                var items: [AnyElement]
                if yFlipped {
                    let flippedRange = max(0, itemCountCopy - visibleRange.upperBound)..<max(0, itemCountCopy - visibleRange.lowerBound)
                    items = renderItemsCopy(flippedRange, &window, &cx)
                    items.reverse()
                } else {
                    items = renderItemsCopy(visibleRange, &window, &cx)
                }

                let contentMask = ContentMask(bounds: bounds)
                window.withContentMask(contentMask) { window in
                    var elementIndex = 0
                    for ix in visibleRange {
                        if elementIndex >= items.count { break }
                        var item = items[elementIndex]
                        elementIndex += 1

                        let itemOrigin = paddedBounds.origin + scrollOffset + Point(x: .zero, y: itemHeight * Float(ix))
                        let availableWidth = canScrollHorizontally ? paddedBounds.size.width + scrollOffset.x.abs() : paddedBounds.size.width
                        let availableSpace = Size(
                            width: AvailableSpace.definite(availableWidth),
                            height: AvailableSpace.definite(itemHeight)
                        )
                        _ = item.layoutAsRoot(availableSpace, &window, &cx)
                        _ = item.prepaintAt(itemOrigin, &window, &cx)
                        frameState.items.append(item)
                    }

                    let decBounds = Bounds(origin: paddedBounds.origin + scrollOffset, size: paddedBounds.size)
                    for decoration in decorationsCopy {
                        var decElement = decoration.compute(
                            visibleRange: visibleRange,
                            bounds: decBounds,
                            scrollOffset: scrollOffset,
                            itemHeight: itemHeight,
                            itemCount: itemCountCopy,
                            window: &window,
                            cx: &cx
                        )
                        let availSpace = Size(
                            width: AvailableSpace.definite(decBounds.size.width),
                            height: AvailableSpace.definite(decBounds.size.height)
                        )
                        _ = decElement.layoutAsRoot(availSpace, &window, &cx)
                        _ = decElement.prepaintAt(decBounds.origin, &window, &cx)
                        frameState.decorations.append(decElement)
                    }
                }
            }

            return hitbox
        }
    }

    @MainActor
    public mutating func paint(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout UniformListFrameState,
        _ hitbox: inout Hitbox?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        self.interactivity.paint(
            globalId,
            inspectorId,
            bounds,
            hitbox,
            &window,
            &cx
        ) { _, window, cx in
            for index in requestLayout.items.indices {
                requestLayout.items[index].paint(&window, &cx)
            }
            for index in requestLayout.decorations.indices {
                requestLayout.decorations[index].paint(&window, &cx)
            }
        }
    }

    public func intoElement() -> UniformList {
        self
    }

    public var style: StyleRefinement {
        get { self.interactivity.baseStyle }
        set { self.interactivity.baseStyle = newValue }
    }
}

/// Frame state used by the [UniformList].
public struct UniformListFrameState: Sendable {
    public var items: [AnyElement]
    public var decorations: [AnyElement]

    public init(items: [AnyElement] = [], decorations: [AnyElement] = []) {
        self.items = items
        self.decorations = decorations
    }
}

/// Where to place the element scrolled to.
public enum ScrollStrategy: Sendable, Equatable, Hashable {
    case top
    case center
    case bottom
    case nearest
}

public struct DeferredScrollToItem: Sendable {
    public var itemIndex: Int
    public var strategy: ScrollStrategy
    public var offset: Int
    public var scrollStrict: Bool

    public init(itemIndex: Int, strategy: ScrollStrategy, offset: Int = 0, scrollStrict: Bool = false) {
        self.itemIndex = itemIndex
        self.strategy = strategy
        self.offset = offset
        self.scrollStrict = scrollStrict
    }
}

/// The size of the item and its contents.
public struct ItemSize: Sendable, Equatable, Default {
    public var item: Size<Pixels>
    public var contents: Size<Pixels>

    public init(item: Size<Pixels> = .zero, contents: Size<Pixels> = .zero) {
        self.item = item
        self.contents = contents
    }

    public static func `default`() -> ItemSize {
        ItemSize()
    }
}

public struct UniformListScrollState: Sendable, Default {
    public var baseHandle: ScrollHandle
    public var deferredScrollToItem: DeferredScrollToItem?
    public var lastItemSize: ItemSize?
    public var yFlipped: Bool

    public init(
        baseHandle: ScrollHandle = ScrollHandle(),
        deferredScrollToItem: DeferredScrollToItem? = nil,
        lastItemSize: ItemSize? = nil,
        yFlipped: Bool = false
    ) {
        self.baseHandle = baseHandle
        self.deferredScrollToItem = deferredScrollToItem
        self.lastItemSize = lastItemSize
        self.yFlipped = yFlipped
    }

    public static func `default`() -> UniformListScrollState {
        UniformListScrollState()
    }
}

/// A handle for controlling the scroll position of a uniform list.
// PORT NOTE: UniformListScrollHandle wraps an inner reference matching upstream Rc<RefCell<UniformListScrollState>>.
// In GPUI, all view hierarchy modifications and scroll mutations execute on the main actor.
public struct UniformListScrollHandle: @unchecked Sendable {
    final class Inner: @unchecked Sendable {
        var baseHandle: ScrollHandle
        var deferredScrollToItem: DeferredScrollToItem?
        var lastItemSize: ItemSize?
        var yFlipped: Bool

        init() {
            self.baseHandle = ScrollHandle()
            self.deferredScrollToItem = nil
            self.lastItemSize = nil
            self.yFlipped = false
        }
    }

    let inner: Inner

    public init() {
        self.inner = Inner()
    }

    public static func new() -> UniformListScrollHandle {
        UniformListScrollHandle()
    }

    /// Scroll the list so that the given item index is visible.
    public func scrollToItem(_ ix: Int, strategy: ScrollStrategy) {
        self.inner.deferredScrollToItem = DeferredScrollToItem(
            itemIndex: ix,
            strategy: strategy,
            offset: 0,
            scrollStrict: false
        )
    }

    /// Scroll the list so that the given item index is at scroll strategy position strictly.
    public func scrollToItemStrict(_ ix: Int, strategy: ScrollStrategy) {
        self.inner.deferredScrollToItem = DeferredScrollToItem(
            itemIndex: ix,
            strategy: strategy,
            offset: 0,
            scrollStrict: true
        )
    }

    /// Scroll the list to the given item index with an offset in number of items.
    public func scrollToItemWithOffset(_ ix: Int, strategy: ScrollStrategy, offset: Int) {
        self.inner.deferredScrollToItem = DeferredScrollToItem(
            itemIndex: ix,
            strategy: strategy,
            offset: offset,
            scrollStrict: false
        )
    }

    /// Scroll the list so that the given item index is at the exact scroll strategy position with an offset.
    public func scrollToItemStrictWithOffset(_ ix: Int, strategy: ScrollStrategy, offset: Int) {
        self.inner.deferredScrollToItem = DeferredScrollToItem(
            itemIndex: ix,
            strategy: strategy,
            offset: offset,
            scrollStrict: true
        )
    }

    /// Check if the list is flipped vertically.
    public func yFlipped() -> Bool {
        self.inner.yFlipped
    }

    /// Get the index of the topmost visible child.
    public func logicalScrollTopIndex() -> Int {
        if let deferred = self.inner.deferredScrollToItem {
            return deferred.itemIndex
        }
        return self.inner.baseHandle.logicalScrollTop().0
    }

    /// Checks if the list can be scrolled vertically.
    public func isScrollable() -> Bool {
        if let size = self.inner.lastItemSize {
            return size.contents.height > size.item.height
        }
        return false
    }

    /// Scroll to the bottom of the list.
    public func scrollToBottom() {
        self.scrollToItem(Int.max, strategy: .bottom)
    }
}

/// A decoration for a [`UniformList`].
public protocol UniformListDecoration: Sendable {
    @MainActor
    func compute(
        visibleRange: Range<Int>,
        bounds: Bounds<Pixels>,
        scrollOffset: Point<Pixels>,
        itemHeight: Pixels,
        itemCount: Int,
        window: inout Window,
        cx: inout App
    ) -> AnyElement
}

extension Entity: UniformListDecoration where T: UniformListDecoration {
    @MainActor
    public func compute(
        visibleRange: Range<Int>,
        bounds: Bounds<Pixels>,
        scrollOffset: Point<Pixels>,
        itemHeight: Pixels,
        itemCount: Int,
        window: inout Window,
        cx: inout App
    ) -> AnyElement {
        self.update(&cx) { inner, cx in
            inner.compute(
                visibleRange: visibleRange,
                bounds: bounds,
                scrollOffset: scrollOffset,
                itemHeight: itemHeight,
                itemCount: itemCount,
                window: &window,
                cx: &cx.app
            )
        }
    }
}
