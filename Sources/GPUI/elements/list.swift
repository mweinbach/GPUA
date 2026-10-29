// Ported from: crates/gpui/src/elements/list.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Refineable
import SumTree
import protocol SumTree.Dimension

// PORT NOTE: Function signature for rendering an item at an index.
public typealias RenderItemFn = @Sendable (Int, inout Window, inout App) -> AnyElement

/// Construct a new list element.
public func list(
    _ state: ListState,
    _ renderItem: @escaping @Sendable (Int, inout Window, inout App) -> AnyElement
) -> List {
    List(state: state, renderItem: renderItem)
}

/// A list element that can be used to render a large number of differently sized elements efficiently.
public struct List: Element, IntoElement, Styled {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = ListPrepaintState

    public var state: ListState
    public var renderItem: @Sendable (Int, inout Window, inout App) -> AnyElement
    public var style: StyleRefinement
    public var sizingBehavior: ListSizingBehavior

    public init(
        state: ListState,
        renderItem: @escaping @Sendable (Int, inout Window, inout App) -> AnyElement
    ) {
        self.state = state
        self.renderItem = renderItem
        self.style = StyleRefinement()
        self.sizingBehavior = .auto
    }

    /// Set the sizing behavior for the list.
    public func withSizingBehavior(_ behavior: ListSizingBehavior) -> Self {
        var copy = self
        copy.sizingBehavior = behavior
        return copy
    }

    public func id() -> ElementId? {
        nil
    }

    public func sourceLocation() -> (String, Int)? {
        nil
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, Void) {
        let sizing = self.sizingBehavior
        let stateRef = self.state
        let styleRef = self.style
        let renderItemCopy = self.renderItem

        let layoutId: LayoutId
        switch sizing {
        case .infer:
            var computedStyle = Style()
            computedStyle.overflow.y = .scroll
            computedStyle.refine(styleRef)

            layoutId = window.withTextStyle(computedStyle.textStyle()) { window in
                let availableHeight: Pixels
                if let lastBounds = stateRef.inner.lastLayoutBounds {
                    availableHeight = lastBounds.size.height
                } else {
                    availableHeight = stateRef.inner.overdraw
                }

                let padding = computedStyle.padding.toPixels(
                    parentSize: (stateRef.inner.lastLayoutBounds ?? .zero).size,
                    remSize: window.remSize
                )

                var renderCopy = renderItemCopy
                let layoutResponse = stateRef.inner.layoutItems(
                    availableWidth: nil,
                    availableHeight: availableHeight,
                    padding: padding,
                    renderItem: &renderCopy,
                    window: &window,
                    cx: &cx
                )
                let maxElementWidth = layoutResponse.maxItemWidth
                let totalHeight = stateRef.inner.items.summary.height

                return window.requestMeasuredLayout(style: computedStyle) { knownDimensions, availableSpace, _, _ in
                    let width: Pixels
                    if let knownWidth = knownDimensions.width {
                        width = knownWidth
                    } else {
                        switch availableSpace.width {
                        case .definite(let x): width = x
                        case .minContent, .maxContent: width = maxElementWidth
                        }
                    }

                    let height: Pixels
                    switch availableSpace.height {
                    case .definite(let h): height = min(totalHeight, h)
                    case .minContent, .maxContent: height = totalHeight
                    }

                    return Size(width: width, height: height)
                }
            }

        case .auto:
            var computedStyle = Style()
            computedStyle.refine(styleRef)
            layoutId = window.withTextStyle(computedStyle.textStyle()) { window in
                window.requestLayout(computedStyle, children: nil, cx: &cx)
            }
        }

        return (layoutId, ())
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ state: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) -> ListPrepaintState {
        self.state.inner.reset = false

        var computedStyle = Style()
        computedStyle.refine(self.style)

        let hitbox = window.insertHitbox(bounds: bounds, behavior: .normal)

        if let lastBounds = self.state.inner.lastLayoutBounds, lastBounds.size.width != bounds.size.width {
            var newItems = SumTree<ListItem>()
            for item in self.state.inner.items.items(()) {
                newItems.push(
                    ListItem.unmeasured(sizeHint: nil, focusHandle: item.focusHandle),
                    ()
                )
            }
            self.state.inner.items = newItems
            self.state.inner.measuringBehavior.reset()
        }

        let padding = computedStyle.padding.toPixels(parentSize: bounds.size, remSize: window.remSize)
        var renderCopy = self.renderItem
        let layout: LayoutItemsResponse
        switch self.state.inner.prepaintItems(
            bounds: bounds,
            padding: padding,
            autoscroll: true,
            renderItem: &renderCopy,
            window: &window,
            cx: &cx
        ) {
        case .success(let resp):
            layout = resp
        case .failure(let autoscrollRequest):
            self.state.inner.logicalScrollTopVal = autoscrollRequest
            switch self.state.inner.prepaintItems(
                bounds: bounds,
                padding: padding,
                autoscroll: false,
                renderItem: &renderCopy,
                window: &window,
                cx: &cx
            ) {
            case .success(let resp): layout = resp
            case .failure: layout = LayoutItemsResponse(maxItemWidth: .zero, scrollTop: autoscrollRequest, itemLayouts: [])
            }
        }

        self.state.inner.lastLayoutBounds = bounds
        self.state.inner.lastPadding = padding
        return ListPrepaintState(hitbox: hitbox, layout: layout)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ prepaint: inout ListPrepaintState,
        _ window: inout Window,
        _ cx: inout App
    ) {
        let currentView = window.currentView()
        window.withContentMask(ContentMask(bounds: bounds)) { (window: inout Window) in
            for index in prepaint.layout.itemLayouts.indices {
                prepaint.layout.itemLayouts[index].element.paint(&window, &cx)
            }
        }

        let listState = self.state
        let height = bounds.size.height
        let scrollTop = prepaint.layout.scrollTop
        let hitboxId = prepaint.hitbox.id
        let scrollDeltaCell = AccumulatedScrollDeltaCell()

        window.onMouseEvent { (event: ScrollWheelEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
            if phase == .bubble && hitboxId.shouldHandleScroll(window) {
                scrollDeltaCell.delta = scrollDeltaCell.delta.coalesce(event.delta)
                let pixelDelta = scrollDeltaCell.delta.pixelDelta(lineHeight: Pixels(20.0))
                listState.inner.scroll(
                    scrollTop: scrollTop,
                    height: height,
                    delta: pixelDelta,
                    currentView: currentView,
                    window: &window,
                    cx: &cx
                )
            }
        }
    }

    public func intoElement() -> List {
        self
    }
}

// PORT NOTE: Mutable cell to accumulate scroll delta across mouse events on the main thread.
private final class AccumulatedScrollDeltaCell: @unchecked Sendable {
    var delta: ScrollDelta = .lines(.zero)
}

/// The list state that views must hold on behalf of the list element.
// PORT NOTE: ListState wraps an inner mutable reference matching upstream Rc<RefCell<StateInner>>.
// In GPUI, all element layout and rendering occurs on the main thread during window prepaint.
public struct ListState: @unchecked Sendable, CustomStringConvertible {
    final class StateInner: @unchecked Sendable {
        var lastLayoutBounds: Bounds<Pixels>?
        var lastPadding: Edges<Pixels>?
        var items: SumTree<ListItem>
        var logicalScrollTopVal: ListOffset?
        var alignment: ListAlignment
        var overdraw: Pixels
        var reset: Bool
        var scrollHandler: (@Sendable (ListScrollEvent, inout Window, inout App) -> Void)?
        var scrollbarDragStartHeight: Pixels?
        var measuringBehavior: ListMeasuringBehavior
        var pendingScroll: PendingScrollFraction?
        var followState: FollowState

        init(alignment: ListAlignment, overdraw: Pixels) {
            self.lastLayoutBounds = nil
            self.lastPadding = nil
            self.items = SumTree<ListItem>()
            self.logicalScrollTopVal = nil
            self.alignment = alignment
            self.overdraw = overdraw
            self.reset = false
            self.scrollHandler = nil
            self.scrollbarDragStartHeight = nil
            self.measuringBehavior = .visible
            self.pendingScroll = nil
            self.followState = .normal
        }

        func maxScrollOffset() -> Pixels {
            let bounds = lastLayoutBounds ?? .zero
            let height = scrollbarDragStartHeight ?? items.summary.height
            return max(px(0), height - bounds.size.height)
        }

        static func visibleRange(
            items: SumTree<ListItem>,
            height: Pixels,
            scrollTop: ListOffset
        ) -> Range<Int> {
            var cursor = items.cursor(()) as Cursor<ListItem, ListItemSummary>
            _ = cursor.seek(to: CountTarget(scrollTop.itemIx), bias: .right)
            let startY = cursor.start().height + scrollTop.offsetInItem
            _ = cursor.seekForward(to: HeightTarget(startY + height), bias: .left)
            return scrollTop.itemIx..<(cursor.start().count + 1)
        }

        func scroll(
            scrollTop: ListOffset,
            height: Pixels,
            delta: Point<Pixels>,
            currentView: EntityId?,
            window: inout Window,
            cx: inout App
        ) {
            if reset { return }

            let padding = lastPadding ?? .zero
            let scrollMax = max(px(0), items.summary.height + padding.top + padding.bottom - height)
            let newScrollTop = min(scrollMax, max(px(0), self.scrollTop(scrollTop) - delta.y))

            if alignment == .bottom && newScrollTop == scrollMax {
                logicalScrollTopVal = nil
            } else {
                let (start, _, _) = items.find((), target: HeightTarget<ListItemSummary>(newScrollTop), bias: .right)
                let itemIx = start.count
                let offsetInItem = newScrollTop - start.height
                logicalScrollTopVal = ListOffset(itemIx: itemIx, offsetInItem: offsetInItem)
            }

            if case .tail = followState {
                if delta.y > px(0) {
                    followState = .tail(isFollowing: false)
                }
            }

            if let handler = scrollHandler {
                let visRange = Self.visibleRange(items: items, height: height, scrollTop: scrollTop)
                let event = ListScrollEvent(
                    visibleRange: visRange,
                    count: items.summary.count,
                    isScrolled: logicalScrollTopVal != nil,
                    isFollowingTail: followState.isFollowing
                )
                handler(event, &window, &cx)
            }

            if let viewId = currentView {
                MainActor.assumeIsolated {
                    cx.notify(viewId)
                }
            }
        }

        func logicalScrollTop() -> ListOffset {
            if let val = logicalScrollTopVal {
                return val
            }
            switch alignment {
            case .top:
                return ListOffset(itemIx: 0, offsetInItem: px(0))
            case .bottom:
                return ListOffset(itemIx: items.summary.count, offsetInItem: px(0))
            }
        }

        func scrollTop(_ logicalScrollTop: ListOffset) -> Pixels {
            let (start, _, _) = items.find((), target: CountTarget<ListItemSummary>(logicalScrollTop.itemIx), bias: .right)
            return start.height + logicalScrollTop.offsetInItem
        }

        @MainActor
        func layoutAllItems(
            availableWidth: Pixels,
            renderItem: inout RenderItemFn,
            window: inout Window,
            cx: inout App
        ) {
            switch measuringBehavior {
            case .visible:
                return
            case .measure(let hasMeasured):
                if hasMeasured { return }
                measuringBehavior = .measure(true)
            }

            let availableItemSpace = Size(
                width: AvailableSpace.definite(availableWidth),
                height: AvailableSpace.minContent
            )

            var measuredItems: [ListItem] = []
            var cursor = items.cursor(()) as Cursor<ListItem, Count>
            var ix = 0
            while let item = cursor.item() {
                let size: Size<Pixels>
                if let cachedSize = item.size {
                    size = cachedSize
                } else {
                    var element = renderItem(ix, &window, &cx)
                    size = element.layoutAsRoot(availableItemSpace, &window, &cx)
                }
                measuredItems.append(.measured(size: size, focusHandle: item.focusHandle))
                ix += 1
                cursor.next()
            }

            var newTree = SumTree<ListItem>()
            for it in measuredItems {
                newTree.push(it, ())
            }
            self.items = newTree
        }

        @MainActor
        func layoutItems(
            availableWidth: Pixels?,
            availableHeight: Pixels,
            padding: Edges<Pixels>,
            renderItem: inout RenderItemFn,
            window: inout Window,
            cx: inout App
        ) -> LayoutItemsResponse {
            let oldItems = self.items
            var measuredItems: [ListItem] = []
            var itemLayouts: [ItemLayout] = []
            var renderedHeight = padding.top
            var maxItemWidth = px(0)
            var scrollTop = self.logicalScrollTop()

            if followState.isFollowing {
                scrollTop = ListOffset(itemIx: self.items.summary.count, offsetInItem: px(0))
                self.logicalScrollTopVal = scrollTop
            }

            var renderedFocusedItem = false
            let availableItemSpace = Size(
                width: availableWidth.map { AvailableSpace.definite($0) } ?? AvailableSpace.minContent,
                height: AvailableSpace.minContent
            )

            var cursor = oldItems.cursor(()) as Cursor<ListItem, Count>
            _ = cursor.seek(to: CountTarget(scrollTop.itemIx), bias: .right)

            var offsetIx = 0
            while let item = cursor.item() {
                let visibleHeight = renderedHeight - scrollTop.offsetInItem
                if visibleHeight >= availableHeight + self.overdraw {
                    break
                }

                var size = item.size
                if visibleHeight < availableHeight || size == nil {
                    let itemIndex = scrollTop.itemIx + offsetIx
                    var element = renderItem(itemIndex, &window, &cx)
                    let elementSize = element.layoutAsRoot(availableItemSpace, &window, &cx)
                    size = elementSize

                    if offsetIx == 0 {
                        if let pending = self.pendingScroll {
                            self.pendingScroll = nil
                            if pending.itemIx == scrollTop.itemIx {
                                scrollTop.offsetInItem = Pixels(pending.fraction * elementSize.height.value)
                                self.logicalScrollTopVal = scrollTop
                            }
                        }
                    }

                    if visibleHeight < availableHeight {
                        itemLayouts.append(ItemLayout(index: itemIndex, element: element, size: elementSize))
                        if item.containsFocused(window: &window, cx: &cx) {
                            renderedFocusedItem = true
                        }
                    }
                }

                let finalSize = size ?? .zero
                renderedHeight += finalSize.height
                maxItemWidth = max(maxItemWidth, finalSize.width)
                measuredItems.append(.measured(size: finalSize, focusHandle: item.focusHandle))

                offsetIx += 1
                cursor.next()
            }
            renderedHeight += padding.bottom

            // Prepare to start walking upward from the item at the scroll top.
            _ = cursor.seek(to: CountTarget(scrollTop.itemIx), bias: .right)

            // If the rendered items do not fill the visible region, adjust the scroll top upward.
            if renderedHeight - scrollTop.offsetInItem < availableHeight {
                while renderedHeight < availableHeight {
                    cursor.prev()
                    if let item = cursor.item() {
                        let itemIndex = cursor.start().value
                        var element = renderItem(itemIndex, &window, &cx)
                        let elementSize = element.layoutAsRoot(availableItemSpace, &window, &cx)
                        let focusHandle = item.focusHandle
                        renderedHeight += elementSize.height
                        measuredItems.insert(.measured(size: elementSize, focusHandle: focusHandle), at: 0)
                        itemLayouts.insert(ItemLayout(index: itemIndex, element: element, size: elementSize), at: 0)
                        if item.containsFocused(window: &window, cx: &cx) {
                            renderedFocusedItem = true
                        }
                    } else {
                        break
                    }
                }

                scrollTop = ListOffset(
                    itemIx: cursor.start().value,
                    offsetInItem: renderedHeight - availableHeight
                )

                switch self.alignment {
                case .top:
                    scrollTop.offsetInItem = max(px(0), scrollTop.offsetInItem)
                    self.logicalScrollTopVal = scrollTop
                case .bottom:
                    scrollTop = ListOffset(
                        itemIx: cursor.start().value,
                        offsetInItem: renderedHeight - availableHeight
                    )
                    self.logicalScrollTopVal = nil
                }
            }

            // Measure items in the leading overdraw
            var leadingOverdraw = scrollTop.offsetInItem
            while leadingOverdraw < self.overdraw {
                cursor.prev()
                if let item = cursor.item() {
                    let size: Size<Pixels>
                    if let cachedSize = item.size {
                        size = cachedSize
                    } else {
                        var element = renderItem(cursor.start().value, &window, &cx)
                        size = element.layoutAsRoot(availableItemSpace, &window, &cx)
                    }

                    leadingOverdraw += size.height
                    measuredItems.insert(.measured(size: size, focusHandle: item.focusHandle), at: 0)
                } else {
                    break
                }
            }

            let measuredRangeStart = cursor.start().value
            let measuredRangeEnd = measuredRangeStart + measuredItems.count

            var spliceCursor = oldItems.cursor(()) as Cursor<ListItem, Count>
            var newItems = spliceCursor.slice(to: CountTarget(measuredRangeStart), bias: .right)
            for it in measuredItems {
                newItems.push(it, ())
            }
            _ = spliceCursor.seek(to: CountTarget(measuredRangeEnd), bias: .right)
            newItems.append(spliceCursor.suffix(), ())
            self.items = newItems

            if self.followState.hasStoppedFollowing {
                let padding = self.lastPadding ?? .zero
                let totalHeight = self.items.summary.height + padding.top + padding.bottom
                let scrollOffset = self.scrollTop(scrollTop)
                if scrollOffset + availableHeight >= totalHeight - px(1.0) {
                    self.followState.startFollowing()
                }
            }

            if !renderedFocusedItem {
                var findCursor = self.items.cursor(()) as Cursor<ListItem, ListItemSummary>
                while let item = findCursor.item() {
                    if item.containsFocused(window: &window, cx: &cx) {
                        let itemIndex = findCursor.start().count
                        var element = renderItem(itemIndex, &window, &cx)
                        let size = element.layoutAsRoot(availableItemSpace, &window, &cx)
                        itemLayouts.append(ItemLayout(index: itemIndex, element: element, size: size))
                        break
                    }
                    findCursor.next()
                }
            }

            return LayoutItemsResponse(
                maxItemWidth: maxItemWidth,
                scrollTop: scrollTop,
                itemLayouts: itemLayouts
            )
        }

        @MainActor
        func prepaintItems(
            bounds: Bounds<Pixels>,
            padding: Edges<Pixels>,
            autoscroll: Bool,
            renderItem: inout RenderItemFn,
            window: inout Window,
            cx: inout App
        ) -> Result<LayoutItemsResponse, ListOffset> {
            switch measuringBehavior {
            case .measure(let hasMeasured) where !hasMeasured:
                layoutAllItems(availableWidth: bounds.size.width, renderItem: &renderItem, window: &window, cx: &cx)
            default:
                break
            }

            var layoutResponse = layoutItems(
                availableWidth: bounds.size.width,
                availableHeight: bounds.size.height,
                padding: padding,
                renderItem: &renderItem,
                window: &window,
                cx: &cx
            )

            _ = window.takeAutoscroll()

            if bounds.size.height > padding.top + padding.bottom {
                var itemOrigin = bounds.origin + Point(x: px(0), y: padding.top)
                itemOrigin.y -= layoutResponse.scrollTop.offsetInItem

                for index in layoutResponse.itemLayouts.indices {
                    window.withContentMask(ContentMask(bounds: bounds)) { (window: inout Window) in
                        _ = layoutResponse.itemLayouts[index].element.prepaintAt(itemOrigin, &window, &cx)
                    }

                    if let autoscrollBounds = window.takeAutoscroll(), autoscroll {
                        if autoscrollBounds.top < bounds.top {
                            return .failure(ListOffset(
                                itemIx: layoutResponse.itemLayouts[index].index,
                                offsetInItem: autoscrollBounds.top - itemOrigin.y
                            ))
                        } else if autoscrollBounds.bottom > bounds.bottom {
                            var cursor = items.cursor(()) as Cursor<ListItem, Count>
                            _ = cursor.seek(to: CountTarget(layoutResponse.itemLayouts[index].index), bias: .right)
                            var height = bounds.size.height - padding.top - padding.bottom
                            height -= autoscrollBounds.bottom - itemOrigin.y

                            while height > px(0) {
                                cursor.prev()
                                guard let item = cursor.item() else { break }
                                let size: Size<Pixels>
                                if let cachedSize = item.size {
                                    size = cachedSize
                                } else {
                                    var el = renderItem(cursor.start().value, &window, &cx)
                                    let avail = Size(width: AvailableSpace.definite(bounds.size.width), height: AvailableSpace.minContent)
                                    size = el.layoutAsRoot(avail, &window, &cx)
                                }
                                height -= size.height
                            }

                            return .failure(ListOffset(
                                itemIx: cursor.start().value,
                                offsetInItem: height < px(0) ? -height : px(0)
                            ))
                        }
                    }

                    itemOrigin.y += layoutResponse.itemLayouts[index].size.height
                }
            } else {
                layoutResponse.itemLayouts.removeAll()
            }

            return .success(layoutResponse)
        }

        func setOffsetFromScrollbar(_ point: Point<Pixels>) {
            guard let bounds = lastLayoutBounds else { return }
            let height = bounds.size.height
            let padding = lastPadding ?? .zero
            let contentHeight = items.summary.height
            let scrollMax = max(px(0), contentHeight + padding.top + padding.bottom - height)
            let dragOffset = contentHeight - (scrollbarDragStartHeight ?? contentHeight)
            let newScrollTop = min(scrollMax, max(px(0), (point.y - dragOffset).abs()))

            followState = .normal

            if alignment == .bottom && newScrollTop == scrollMax {
                logicalScrollTopVal = nil
            } else {
                let (start, _, _) = items.find((), target: HeightTarget<ListItemSummary>(newScrollTop), bias: .right)
                let itemIx = start.count
                let offsetInItem = newScrollTop - start.height
                logicalScrollTopVal = ListOffset(itemIx: itemIx, offsetInItem: offsetInItem)
            }
        }
    }

    let inner: StateInner

    public var description: String {
        "ListState"
    }

    /// Construct a new list state, for storage on a view.
    public init(itemCount: Int, alignment: ListAlignment, overdraw: Pixels) {
        self.inner = StateInner(alignment: alignment, overdraw: overdraw)
        self.splice(0..<0, count: itemCount)
    }

    /// Construct a new list state, for storage on a view.
    public static func new(itemCount: Int, alignment: ListAlignment, overdraw: Pixels) -> ListState {
        ListState(itemCount: itemCount, alignment: alignment, overdraw: overdraw)
    }

    /// Construct a new list state with positional arguments matching upstream Rust.
    public static func new(_ itemCount: Int, _ alignment: ListAlignment, _ overdraw: Pixels) -> ListState {
        ListState(itemCount: itemCount, alignment: alignment, overdraw: overdraw)
    }

    /// Set the list to measure all items in the list in the first layout phase.
    public func measureAll() -> Self {
        self.inner.measuringBehavior = .measure(false)
        return self
    }

    /// Reset this instantiation of the list state.
    public func reset(_ elementCount: Int) {
        let oldCount: Int
        self.inner.reset = true
        self.inner.measuringBehavior.reset()
        self.inner.logicalScrollTopVal = nil
        self.inner.scrollbarDragStartHeight = nil
        oldCount = self.inner.items.summary.count

        self.splice(0..<oldCount, count: elementCount)
    }

    /// Remeasure all items while preserving proportional scroll position.
    public func remeasure() {
        let count = self.itemCount()
        self.remeasureItems(0..<count)
    }

    /// Mark items in `range` as needing remeasurement while preserving current scroll position.
    public func remeasureItems(_ range: Range<Int>) {
        if let scrollTop = self.inner.logicalScrollTopVal {
            if range.contains(scrollTop.itemIx) {
                var cursor = self.inner.items.cursor(()) as Cursor<ListItem, Count>
                _ = cursor.seek(to: CountTarget(scrollTop.itemIx), bias: .right)
                if let item = cursor.item(), let size = item.size {
                    let fraction: Float
                    if size.height > .zero {
                        fraction = min(1.0, max(0.0, scrollTop.offsetInItem.value / size.height.value))
                    } else {
                        fraction = 0.0
                    }
                    self.inner.pendingScroll = PendingScrollFraction(itemIx: scrollTop.itemIx, fraction: fraction)
                }
            }
        }

        var cursor = self.inner.items.cursor(()) as Cursor<ListItem, Count>
        var newItems = cursor.slice(to: CountTarget(range.lowerBound), bias: .right)
        let invalidated = cursor.slice(to: CountTarget(range.upperBound), bias: .right)
        for item in invalidated.items(()) {
            newItems.push(ListItem.unmeasured(sizeHint: item.sizeHint, focusHandle: item.focusHandle), ())
        }
        newItems.append(cursor.suffix(), ())
        self.inner.items = newItems
        self.inner.measuringBehavior.reset()
    }

    /// The number of items in this list.
    public func itemCount() -> Int {
        self.inner.items.summary.count
    }

    /// Inform the list state that the items in `oldRange` have been replaced by `count` new items.
    public func splice(_ oldRange: Range<Int>, count: Int) {
        self.spliceFocusable(oldRange, focusHandles: (0..<count).map { _ in FocusHandle?.none })
    }

    /// Register with list state that items in `oldRange` have been replaced by new items with optional focus handles.
    public func spliceFocusable(_ oldRange: Range<Int>, focusHandles: some Sequence<FocusHandle?>) {
        var oldItems = self.inner.items.cursor(()) as Cursor<ListItem, Count>
        var newItems = oldItems.slice(to: CountTarget(oldRange.lowerBound), bias: .right)
        _ = oldItems.seekForward(to: CountTarget(oldRange.upperBound), bias: .right)

        var splicedCount = 0
        for handle in focusHandles {
            splicedCount += 1
            newItems.push(ListItem.unmeasured(sizeHint: nil, focusHandle: handle), ())
        }
        newItems.append(oldItems.suffix(), ())
        self.inner.items = newItems

        if var scrollTop = self.inner.logicalScrollTopVal {
            if oldRange.contains(scrollTop.itemIx) {
                scrollTop.itemIx = oldRange.lowerBound
                scrollTop.offsetInItem = px(0)
                self.inner.logicalScrollTopVal = scrollTop
            } else if oldRange.upperBound <= scrollTop.itemIx {
                scrollTop.itemIx = scrollTop.itemIx - (oldRange.upperBound - oldRange.lowerBound) + splicedCount
                self.inner.logicalScrollTopVal = scrollTop
            }
        }
    }

    /// Set a handler that will be called when the list is scrolled.
    public func setScrollHandler(_ handler: @escaping @Sendable (ListScrollEvent, inout Window, inout App) -> Void) {
        self.inner.scrollHandler = handler
    }

    /// Get the current scroll offset, in terms of the list's items.
    public func logicalScrollTop() -> ListOffset {
        self.inner.logicalScrollTop()
    }

    /// Scroll the list by the given offset.
    public func scrollBy(_ distance: Pixels) {
        if distance == px(0) { return }

        let currentOffset = self.logicalScrollTop()
        if distance < px(0) {
            if case .tail = self.inner.followState {
                self.inner.followState = .tail(isFollowing: false)
            }
        }

        var cursor = self.inner.items.cursor(()) as Cursor<ListItem, ListItemSummary>
        _ = cursor.seek(to: CountTarget(currentOffset.itemIx), bias: .right)

        let startPixelOffset = cursor.start().height + currentOffset.offsetInItem
        let newPixelOffset = max(px(0), startPixelOffset + distance)

        if newPixelOffset > startPixelOffset {
            _ = cursor.seekForward(to: HeightTarget(newPixelOffset), bias: .right)
        } else {
            _ = cursor.seek(to: HeightTarget(newPixelOffset), bias: .right)
        }

        self.inner.logicalScrollTopVal = ListOffset(
            itemIx: cursor.start().count,
            offsetInItem: newPixelOffset - cursor.start().height
        )
    }

    /// Scroll the list to the very end.
    public func scrollToEnd() {
        let count = self.inner.items.summary.count
        self.inner.logicalScrollTopVal = ListOffset(itemIx: count, offsetInItem: px(0))
    }

    /// Set the follow mode for the list.
    public func setFollowMode(_ mode: FollowMode) {
        switch mode {
        case .normal:
            self.inner.followState = .normal
        case .tail:
            self.inner.followState = .tail(isFollowing: true)
            let count = self.inner.items.summary.count
            self.inner.logicalScrollTopVal = ListOffset(itemIx: count, offsetInItem: px(0))
        }
    }

    /// Returns whether the list is currently actively following the tail.
    public func isFollowingTail() -> Bool {
        self.inner.followState.isFollowing
    }

    /// Scroll the list to the given offset.
    public func scrollTo(_ scrollTop: ListOffset) {
        var st = scrollTop
        let count = self.inner.items.summary.count
        if st.itemIx >= count {
            st.itemIx = count
            st.offsetInItem = px(0)
        }

        if st.itemIx < count {
            if case .tail = self.inner.followState {
                self.inner.followState = .tail(isFollowing: false)
            }
        }

        self.inner.logicalScrollTopVal = st
    }

    /// Scroll the list to the given item, such that the item is fully visible.
    public func scrollToRevealItem(_ ix: Int) {
        var scrollTop = self.inner.logicalScrollTop()
        let height = self.inner.lastLayoutBounds?.size.height ?? px(0)
        let padding = self.inner.lastPadding ?? .zero

        if ix <= scrollTop.itemIx {
            scrollTop.itemIx = ix
            scrollTop.offsetInItem = px(0)
        } else {
            var cursor = self.inner.items.cursor(()) as Cursor<ListItem, ListItemSummary>
            _ = cursor.seek(to: CountTarget(ix + 1), bias: .right)
            let bottom = cursor.start().height + padding.top
            let goalTop = max(px(0), bottom - height + padding.bottom)

            _ = cursor.seek(to: HeightTarget(goalTop), bias: .left)
            let startIx = cursor.start().count
            let startItemTop = cursor.start().height

            if startIx >= scrollTop.itemIx {
                scrollTop.itemIx = startIx
                scrollTop.offsetInItem = goalTop - startItemTop
            }
        }

        self.inner.logicalScrollTopVal = scrollTop
    }

    /// Get the bounds for the given item in window coordinates, if it's been rendered.
    public func boundsForItem(_ ix: Int) -> Bounds<Pixels>? {
        let bounds = self.inner.lastLayoutBounds ?? .zero
        let scrollTop = self.inner.logicalScrollTop()
        if ix < scrollTop.itemIx {
            return nil
        }

        var cursor = self.inner.items.cursor(()) as Cursor<ListItem, ListItemSummary>
        _ = cursor.seek(to: CountTarget(scrollTop.itemIx), bias: .right)
        let scrollTopPixels = cursor.start().height + scrollTop.offsetInItem

        _ = cursor.seekForward(to: CountTarget(ix), bias: .right)
        if let item = cursor.item(), case .measured(let size, _) = item {
            if cursor.start().count == ix {
                let top = bounds.top + cursor.start().height - scrollTopPixels
                return Bounds.fromCorners(
                    Point(x: bounds.left, y: top),
                    Point(x: bounds.right, y: top + size.height)
                )
            }
        }
        return nil
    }

    /// Call this method when the user starts dragging the scrollbar.
    public func scrollbarDragStarted() {
        self.inner.scrollbarDragStartHeight = self.inner.items.summary.height
    }

    /// Called when the user stops dragging the scrollbar.
    public func scrollbarDragEnded() {
        self.inner.scrollbarDragStartHeight = nil
    }

    /// Set the offset from the scrollbar.
    public func setOffsetFromScrollbar(_ point: Point<Pixels>) {
        self.inner.setOffsetFromScrollbar(point)
    }

    /// Returns the maximum scroll offset according to the items we have measured.
    public func maxOffsetForScrollbar() -> Point<Pixels> {
        Point(x: px(0), y: self.inner.maxScrollOffset())
    }

    /// Returns the current scroll offset adjusted for the scrollbar.
    public func scrollPxOffsetForScrollbar() -> Point<Pixels> {
        if self.inner.logicalScrollTopVal == nil && self.inner.alignment == .bottom {
            return Point(x: px(0), y: -self.inner.maxScrollOffset())
        }

        let logicalScrollTop = self.inner.logicalScrollTop()
        var cursor = self.inner.items.cursor(()) as Cursor<ListItem, ListItemSummary>
        _ = cursor.seek(to: CountTarget(logicalScrollTop.itemIx), bias: .right)
        let summary = cursor.start()
        let contentHeight = self.inner.items.summary.height
        let dragOffset = contentHeight - (self.inner.scrollbarDragStartHeight ?? contentHeight)
        let offset = summary.height + logicalScrollTop.offsetInItem - dragOffset

        return Point(x: px(0), y: -offset)
    }

    /// Return the bounds of the viewport in pixels.
    public func viewportBounds() -> Bounds<Pixels> {
        self.inner.lastLayoutBounds ?? .zero
    }
}

/// Controls whether the list automatically follows new content at the end.
public enum FollowMode: Sendable, Equatable, Hashable, Default {
    case normal
    case tail

    public static func `default`() -> FollowMode { .normal }
}

enum FollowState: Sendable, Equatable {
    case normal
    case tail(isFollowing: Bool)

    var isFollowing: Bool {
        if case .tail(let f) = self { return f }
        return false
    }

    var hasStoppedFollowing: Bool {
        if case .tail(let f) = self { return !f }
        return false
    }

    mutating func startFollowing() {
        if case .tail(false) = self {
            self = .tail(isFollowing: true)
        }
    }
}

/// Whether the list is scrolling from top to bottom or bottom to top.
public enum ListAlignment: Sendable, Equatable, Hashable {
    case top
    case bottom
}

/// A scroll event that has been converted to be in terms of the list's items.
public struct ListScrollEvent: Sendable {
    public var visibleRange: Range<Int>
    public var count: Int
    public var isScrolled: Bool
    public var isFollowingTail: Bool

    public init(visibleRange: Range<Int>, count: Int, isScrolled: Bool, isFollowingTail: Bool) {
        self.visibleRange = visibleRange
        self.count = count
        self.isScrolled = isScrolled
        self.isFollowingTail = isFollowingTail
    }
}

/// The sizing behavior to apply during layout.
public enum ListSizingBehavior: Sendable, Equatable, Hashable, Default {
    case infer
    case auto

    public static func `default`() -> ListSizingBehavior { .auto }
}

/// The measuring behavior to apply during layout.
public enum ListMeasuringBehavior: Sendable, Equatable, Hashable, Default {
    case measure(Bool)
    case visible

    public static func `default`() -> ListMeasuringBehavior { .visible }

    mutating func reset() {
        if case .measure = self {
            self = .measure(false)
        }
    }
}

/// The horizontal sizing behavior to apply during layout.
public enum ListHorizontalSizingBehavior: Sendable, Equatable, Hashable, Default {
    case fitList
    case unconstrained

    public static func `default`() -> ListHorizontalSizingBehavior { .fitList }
}

/// Frame state used by the [List] element after layout.
public struct ListPrepaintState: Sendable {
    public var hitbox: Hitbox
    var layout: LayoutItemsResponse

    init(hitbox: Hitbox, layout: LayoutItemsResponse) {
        self.hitbox = hitbox
        self.layout = layout
    }
}

/// An offset into the list's items, in terms of the item index and the number of pixels off the top left of the item.
public struct ListOffset: Sendable, Equatable, Hashable, Default, Error {
    public var itemIx: Int
    public var offsetInItem: Pixels

    public init(itemIx: Int = 0, offsetInItem: Pixels = .zero) {
        self.itemIx = itemIx
        self.offsetInItem = offsetInItem
    }

    public static func `default`() -> ListOffset {
        ListOffset(itemIx: 0, offsetInItem: .zero)
    }
}

struct LayoutItemsResponse: Sendable {
    var maxItemWidth: Pixels
    var scrollTop: ListOffset
    var itemLayouts: [ItemLayout]
}

struct ItemLayout: Sendable {
    var index: Int
    var element: AnyElement
    var size: Size<Pixels>
}

struct PendingScrollFraction: Sendable {
    var itemIx: Int
    var fraction: Float
}

enum ListItem: Item, Sendable {
    typealias SummaryType = ListItemSummary

    case unmeasured(sizeHint: Size<Pixels>?, focusHandle: FocusHandle?)
    case measured(size: Size<Pixels>, focusHandle: FocusHandle?)

    var size: Size<Pixels>? {
        if case .measured(let size, _) = self { return size }
        return nil
    }

    var sizeHint: Size<Pixels>? {
        switch self {
        case .measured(let size, _): return size
        case .unmeasured(let sizeHint, _): return sizeHint
        }
    }

    var focusHandle: FocusHandle? {
        switch self {
        case .unmeasured(_, let handle), .measured(_, let handle):
            return handle
        }
    }

    func containsFocused(window: inout Window, cx: inout App) -> Bool {
        focusHandle?.containsFocused(window, cx) ?? false
    }

    func summary(cx: Void) -> ListItemSummary {
        switch self {
        case .unmeasured(let hint, let handle):
            return ListItemSummary(
                count: 1,
                renderedCount: 0,
                unrenderedCount: 1,
                height: hint?.height ?? .zero,
                hasFocusHandles: handle != nil
            )
        case .measured(let size, let handle):
            return ListItemSummary(
                count: 1,
                renderedCount: 1,
                unrenderedCount: 0,
                height: size.height,
                hasFocusHandles: handle != nil
            )
        }
    }
}

struct ListItemSummary: ContextLessSummary, Dimension, Sendable, Equatable {
    typealias Context = Void
    typealias SummaryType = ListItemSummary

    var count: Int
    var renderedCount: Int
    var unrenderedCount: Int
    var height: Pixels
    var hasFocusHandles: Bool

    init(
        count: Int = 0,
        renderedCount: Int = 0,
        unrenderedCount: Int = 0,
        height: Pixels = .zero,
        hasFocusHandles: Bool = false
    ) {
        self.count = count
        self.renderedCount = renderedCount
        self.unrenderedCount = unrenderedCount
        self.height = height
        self.hasFocusHandles = hasFocusHandles
    }

    static func zero() -> ListItemSummary {
        ListItemSummary()
    }

    static func zero(cx: Void) -> ListItemSummary {
        ListItemSummary()
    }

    mutating func addSummary(_ other: ListItemSummary) {
        self.count += other.count
        self.renderedCount += other.renderedCount
        self.unrenderedCount += other.unrenderedCount
        self.height += other.height
        self.hasFocusHandles = self.hasFocusHandles || other.hasFocusHandles
    }

    mutating func addSummary(_ other: ListItemSummary, cx: Void) {
        addSummary(other)
    }
}

struct Count: Dimension, Sendable, Equatable, Comparable {
    typealias SummaryType = ListItemSummary
    var value: Int

    init(_ value: Int = 0) {
        self.value = value
    }

    static func zero(cx: Void) -> Count {
        Count(0)
    }

    mutating func addSummary(_ summary: ListItemSummary, cx: Void) {
        self.value += summary.count
    }

    static func < (lhs: Count, rhs: Count) -> Bool {
        lhs.value < rhs.value
    }
}

struct Height: Dimension, Sendable, Equatable {
    typealias SummaryType = ListItemSummary
    var value: Pixels

    init(_ value: Pixels = .zero) {
        self.value = value
    }

    static func zero(cx: Void) -> Height {
        Height(.zero)
    }

    mutating func addSummary(_ summary: ListItemSummary, cx: Void) {
        self.value += summary.height
    }
}

struct CountTarget<D: Dimension<ListItemSummary>>: SeekTarget, Sendable {
    typealias SummaryType = ListItemSummary
    typealias D = D

    let count: Int

    init(_ count: Int) {
        self.count = count
    }

    func cmp(cursorLocation: D, cx: Void) -> Ordering {
        if let location = cursorLocation as? ListItemSummary {
            if count < location.count { return .less }
            if count > location.count { return .greater }
            return .equal
        }
        if let location = cursorLocation as? Count {
            if count < location.value { return .less }
            if count > location.value { return .greater }
            return .equal
        }
        return .equal
    }
}

struct HeightTarget<D: Dimension<ListItemSummary>>: SeekTarget, Sendable {
    typealias SummaryType = ListItemSummary
    typealias D = D

    let height: Pixels

    init(_ height: Pixels) {
        self.height = height
    }

    func cmp(cursorLocation: D, cx: Void) -> Ordering {
        if let location = cursorLocation as? ListItemSummary {
            if height < location.height { return .less }
            if height > location.height { return .greater }
            return .equal
        }
        if let location = cursorLocation as? Height {
            if height < location.value { return .less }
            if height > location.value { return .greater }
            return .equal
        }
        return .equal
    }
}
