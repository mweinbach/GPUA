// Ported from: crates/rune/src/el/handler_set.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Event, gesture, layout-watch and pointer-feedback handlers shared by `El` and `Node` behind
//! `Cold<Handlers>`, so elements without callbacks pay one pointer.

#if DEBUG
/// Where `onHover`, `onHoverChange`, `onPointerMove`, `onLayout`, `onDrawnLayout` and
/// `onVisibleRows` were set.
struct HandlerSites: Sendable, Equatable {
    var hover: String? = nil
    var hoverChange: String? = nil
    var pointerMove: String? = nil
    var layout: String? = nil
    var drawnLayout: String? = nil
    var visibleRows: String? = nil
}
#endif

struct Handlers: ColdEmpty {
    var onPaste: PasteFn? = nil
    var onWindowFocus: WindowFocusFn? = nil
    var modal: ModalSpec? = nil
    var onPress: PressFn? = nil
    var onDoublePress: PressFn? = nil
    var onSecondaryPress: PointerFn? = nil
    var onHover: PressFn? = nil
    var onHoverChange: WindowFocusFn? = nil
    /// Seconds the pointer must stay inside, then outside, before `onHoverChange` hears it.
    var hoverDelay: [Float] = [0.0, 0.0]
    var onPointerMove: PointerFn? = nil
    /// `onWheel`, `onMagnify` and the other canvas handlers (`canvas_input.swift`).
    var gestures: CanvasInput? = nil
    var onDrag: DragFn? = nil
    var dragOut: DragOutFn? = nil
    var dragThreshold: Float? = nil
    var onDragStart: PressFn? = nil
    var onDragEnd: DragEndFn? = nil
    var drop: DropSpec? = nil
    var onAtBottom: AtBottomFn? = nil
    var onFarFromBottom: (Float, AtBottomFn)? = nil
    var onVisibleRows: VisibleRowsFn? = nil
    var onLayout: LayoutTxFn? = nil
    var onScreenLayout: LayoutFn? = nil
    var onDrawnLayout: LayoutTxFn? = nil
    /// `El.drawnRectInto`: where each frame draws the element.
    var drawnRect: Live<[Float]>? = nil
    var onScrollOffset: ScrollOffsetFn? = nil
    var selectionCopy: SelectionCopy? = nil
    var onSelectionChange: SelectionChangeFn? = nil
    var cursor: Cursor? = nil
    var pressScale: Float? = nil
    var hostExtras: HostElExtras? = nil
    #if DEBUG
    var sites: HandlerSites = HandlerSites()
    #endif

    @inline(__always)
    func hasPrimary() -> Bool {
        onPress != nil
            || onDoublePress != nil
            || onHover != nil
            || onDrag != nil
            || dragOut != nil
    }

    @inline(__always)
    func takesHit() -> Bool {
        onPointerMove != nil
            || onPress != nil
            || onDoublePress != nil
            || onSecondaryPress != nil
            || onHover != nil
            || onHoverChange != nil
            || onDrag != nil
            || dragOut != nil
            || modal != nil
            || (gestures?.takesGestures ?? false)
    }

    static var emptyValue: Handlers { Handlers() }

    var isColdEmpty: Bool {
        #if DEBUG
        let sitesEmpty = (sites == HandlerSites())
        #else
        let sitesEmpty = true
        #endif
        return onPaste == nil
            && onWindowFocus == nil
            && modal == nil
            && onPress == nil
            && onDoublePress == nil
            && onSecondaryPress == nil
            && onHover == nil
            && onHoverChange == nil
            && hoverDelay == [0.0, 0.0]
            && onPointerMove == nil
            && gestures == nil
            && onDrag == nil
            && dragOut == nil
            && dragThreshold == nil
            && onDragStart == nil
            && onDragEnd == nil
            && drop == nil
            && onAtBottom == nil
            && onFarFromBottom == nil
            && onVisibleRows == nil
            && onLayout == nil
            && onScreenLayout == nil
            && onDrawnLayout == nil
            && drawnRect == nil
            && onScrollOffset == nil
            && selectionCopy == nil
            && onSelectionChange == nil
            && cursor == nil
            && pressScale == nil
            && hostExtras == nil
            && sitesEmpty
    }
}
