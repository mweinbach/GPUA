// Ported from: crates/gpui/src/view.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - View Cache Types

public struct AnyViewState: Sendable {
    public var prepaintRange: Range<PrepaintStateIndex>
    public var paintRange: Range<PaintIndex>
    public var cacheKey: ViewCacheKey
    public var accessedEntities: Set<EntityId>

    public init(
        prepaintRange: Range<PrepaintStateIndex>,
        paintRange: Range<PaintIndex>,
        cacheKey: ViewCacheKey,
        accessedEntities: Set<EntityId>
    ) {
        self.prepaintRange = prepaintRange
        self.paintRange = paintRange
        self.cacheKey = cacheKey
        self.accessedEntities = accessedEntities
    }
}

public struct ViewCacheKey: Sendable, Equatable {
    public var bounds: Bounds<Pixels>
    public var contentMask: ContentMask<Pixels>
    public var textStyle: TextStyle

    public init(
        bounds: Bounds<Pixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<Pixels> = ContentMask(bounds: .zero),
        textStyle: TextStyle = TextStyle()
    ) {
        self.bounds = bounds
        self.contentMask = contentMask
        self.textStyle = textStyle
    }
}

// MARK: - AnyView

/// A dynamically-typed handle to a view, which can be downcast to an `Entity` for a specific type.
public struct AnyView: Element, Equatable, Error {
    public typealias RequestLayoutState = AnyElement?
    public typealias PrepaintState = AnyElement?

    public var entity: AnyEntity
    private var renderClosure: @Sendable (AnyView, inout Window, inout App) -> AnyElement
    public var cachedStyle: StyleRefinement?

    public init<V: Render>(_ entity: Entity<V>) {
        self.entity = entity.intoAny()
        self.cachedStyle = nil
        let typedEntity = entity
        self.renderClosure = { anyView, window, cx in
            MainActor.assumeIsolated {
                typedEntity.update(&cx) { v, cx in
                    v.render(&window, &cx).intoAnyElement()
                }
            }
        }
    }

    public init(
        entity: AnyEntity,
        renderClosure: @escaping @Sendable (AnyView, inout Window, inout App) -> AnyElement,
        cachedStyle: StyleRefinement? = nil
    ) {
        self.entity = entity
        self.renderClosure = renderClosure
        self.cachedStyle = cachedStyle
    }

    /// Indicate that this view should be cached when using it as an element.
    public func cached(_ style: StyleRefinement) -> AnyView {
        var copy = self
        copy.cachedStyle = style
        return copy
    }

    /// Convert this to a weak handle.
    public func downgrade() -> AnyWeakView {
        AnyWeakView(entity: entity.downgrade(), renderClosure: renderClosure)
    }

    /// Convert this to an `Entity` of a specific type.
    public func downcast<T>() -> Result<Entity<T>, AnyView> {
        let res: Result<Entity<T>, AnyEntity> = entity.downcast()
        switch res {
        case .success(let typedEntity):
            return .success(typedEntity)
        case .failure:
            return .failure(self)
        }
    }

    /// Gets the `ObjectIdentifier` of the underlying view type.
    public func entityType() -> ObjectIdentifier {
        entity.entityType
    }

    /// Gets the entity id of this handle.
    public func entityId() -> EntityId {
        entity.entityId
    }

    public static func == (lhs: AnyView, rhs: AnyView) -> Bool {
        lhs.entity == rhs.entity
    }

    public func id() -> ElementId? {
        .view(entityId())
    }

    public func sourceLocation() -> String? {
        nil
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, AnyElement?) {
        let viewId = entityId()
        return window.withRenderedView(viewId) { window in
            let cachingDisabled = window.isInspectorPicking(cx)
            if let style = self.cachedStyle, !cachingDisabled {
                var rootStyle = Style()
                rootStyle.refine(style)
                let layoutId = window.requestLayout(style: rootStyle)
                return (layoutId, nil)
            } else {
                var element = (self.renderClosure)(self, &window, &cx)
                let layoutId = element.requestLayout(&window, &cx)
                return (layoutId, element)
            }
        }
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ element: inout AnyElement?,
        _ window: inout Window,
        _ cx: inout App
    ) -> AnyElement? {
        let viewId = entityId()
        window.setViewId(viewId)
        return window.withRenderedView(viewId) { (window: inout Window) -> AnyElement? in
            if var el = element {
                _ = el.prepaint(&window, &cx)
                return el
            }

            guard let globalId = id else { return nil }
            return window.withElementState(globalId) { (state: AnyViewState?, window: inout Window) -> (AnyElement?, AnyViewState?) in
                let contentMask = window.contentMask()
                let textStyle = window.textStyle()

                if var s = state,
                   s.cacheKey.bounds == bounds,
                   s.cacheKey.contentMask == contentMask,
                   s.cacheKey.textStyle == textStyle,
                   !window.dirtyViews.contains(viewId),
                   !window.refreshing {
                    let prepaintStart = window.prepaintIndex()
                    window.reusePrepaint(s.prepaintRange)
                    cx.entities.extendAccessed(s.accessedEntities)
                    let prepaintEnd = window.prepaintIndex()
                    s.prepaintRange = prepaintStart..<prepaintEnd
                    return (nil, s)
                }

                let refreshing = window.refreshing
                window.refreshing = true
                let prepaintStart = window.prepaintIndex()

                let (renderedElement, accessedEntities) = cx.detectAccessedEntities { cx in
                    var cx = cx
                    var el = (self.renderClosure)(self, &window, &cx)
                    _ = el.layoutAsRoot(Size(width: .definite(bounds.size.width), height: .definite(bounds.size.height)), &window, &cx)
                    _ = el.prepaintAt(bounds.origin, &window, &cx)
                    return el
                }

                let prepaintEnd = window.prepaintIndex()
                window.refreshing = refreshing

                let newState = AnyViewState(
                    prepaintRange: prepaintStart..<prepaintEnd,
                    paintRange: PaintIndex()..<PaintIndex(),
                    cacheKey: ViewCacheKey(bounds: bounds, contentMask: contentMask, textStyle: textStyle),
                    accessedEntities: accessedEntities
                )
                return (renderedElement, newState)
            }
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout AnyElement?,
        _ prepaint: inout AnyElement?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        let viewId = entityId()
        window.withRenderedView(viewId) { window in
            let cachingDisabled = window.isInspectorPicking(cx)
            if self.cachedStyle != nil && !cachingDisabled, let globalId = id {
                window.withElementState(globalId) { (state: AnyViewState?, window: inout Window) -> (Void, AnyViewState?) in
                    guard var s = state else { return ((), nil) }
                    let paintStart = window.paintIndex()
                    if var el = prepaint {
                        let refreshing = window.refreshing
                        window.refreshing = true
                        el.paint(&window, &cx)
                        window.refreshing = refreshing
                    } else {
                        window.reusePaint(s.paintRange)
                    }
                    let paintEnd = window.paintIndex()
                    s.paintRange = paintStart..<paintEnd
                    return ((), s)
                }
            } else if var el = prepaint {
                el.paint(&window, &cx)
            }
        }
    }
}

extension AnyView: IntoElement {
    public func intoElement() -> AnyView {
        self
    }

    public func intoAnyElement() -> AnyElement {
        AnyElement(self)
    }
}

extension Entity: IntoElement where T: Render {
    public func intoElement() -> AnyView {
        AnyView(self)
    }

    public func intoAnyElement() -> AnyElement {
        AnyElement(AnyView(self))
    }
}

// MARK: - AnyWeakView

/// A weak, dynamically-typed view handle that does not prevent the view from being released.
public struct AnyWeakView: Equatable {
    public var entity: AnyWeakEntity
    private var renderClosure: @Sendable (AnyView, inout Window, inout App) -> AnyElement

    public init(
        entity: AnyWeakEntity,
        renderClosure: @escaping @Sendable (AnyView, inout Window, inout App) -> AnyElement
    ) {
        self.entity = entity
        self.renderClosure = renderClosure
    }

    public init<V: Render>(_ view: WeakEntity<V>) {
        self.entity = view.anyEntity
        let weakEntity = view
        self.renderClosure = { anyView, window, cx in
            MainActor.assumeIsolated {
                guard let strong = weakEntity.upgrade() else {
                    return Empty().intoAnyElement()
                }
                return strong.update(&cx) { v, cx in
                    v.render(&window, &cx).intoAnyElement()
                }
            }
        }
    }

    /// Convert to a strongly-typed handle if the referenced view has not yet been released.
    public func upgrade() -> AnyView? {
        guard let strongEntity = entity.upgrade() else { return nil }
        return AnyView(
            entity: strongEntity,
            renderClosure: renderClosure,
            cachedStyle: nil
        )
    }

    public static func == (lhs: AnyWeakView, rhs: AnyWeakView) -> Bool {
        lhs.entity == rhs.entity
    }
}

// MARK: - Render Helper

/// Renders a typed view into an element tree.
public func render<V: Render>(
    _ view: AnyView,
    _ type: V.Type = V.self,
    _ window: inout Window,
    _ cx: inout App
) -> AnyElement {
    let downcastResult: Result<Entity<V>, AnyView> = view.downcast()
    guard case .success(let typedView) = downcastResult else {
        fatalError("Failed to downcast AnyView to \(V.self)")
    }
    return MainActor.assumeIsolated {
        typedView.update(&cx) { v, cx in
            v.render(&window, &cx).intoAnyElement()
        }
    }
}

// MARK: - EmptyView

/// A view that renders nothing.
// PORT NOTE: EmptyView is a minimal Render view matching upstream gpui::EmptyView.
public final class EmptyView: Render, @unchecked Sendable {
    public init() {}

    public func render(_ window: inout Window, _ cx: inout Context<EmptyView>) -> Empty {
        Empty()
    }
}

// MARK: - View & Context Typealiases

public typealias ViewContext<V> = Context<V>
