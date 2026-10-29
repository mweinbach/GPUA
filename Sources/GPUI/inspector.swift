// Ported from: crates/gpui/src/inspector.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// `GlobalElementId` qualified by source location of element construction.
public struct InspectorElementPath: Sendable, Equatable, Hashable {
    public var globalId: GlobalElementId
    public var file: SharedString
    public var line: UInt32
    public var column: UInt32

    public init(
        globalId: GlobalElementId = GlobalElementId(),
        file: SharedString = "",
        line: UInt32 = 0,
        column: UInt32 = 0
    ) {
        self.globalId = globalId
        self.file = file
        self.line = line
        self.column = column
    }
}

/// A unique identifier for an element that can be inspected.
public struct InspectorElementId: Sendable, Equatable, Hashable {
    public var path: InspectorElementPath
    public var instanceId: Int

    public init(path: InspectorElementPath = InspectorElementPath(), instanceId: Int = 0) {
        self.path = path
        self.instanceId = instanceId
    }
}

/// Function set on App to render the inspector UI.
public typealias InspectorRenderer = @MainActor (inout Inspector, inout Window, App) -> AnyElement

// PORT NOTE: InspectedElement holds element states accessible only on the main thread during inspection.
private struct InspectedElement: @unchecked Sendable {
    var id: InspectorElementId
    var states: [ObjectIdentifier: Any] = [:]

    init(id: InspectorElementId) {
        self.id = id
    }
}

/// Manages inspector state - which element is currently selected and whether the inspector is in picking mode.
public struct Inspector: Sendable {
    private var activeElement: InspectedElement?
    public var pickDepth: Float?

    public init() {
        self.activeElement = nil
        self.pickDepth = 0.0
    }

    public static func new() -> Inspector {
        Inspector()
    }

    public mutating func select(id: InspectorElementId, window: inout Window) {
        _ = setActiveElementId(id, window: &window)
        pickDepth = nil
    }

    public mutating func hover(id: InspectorElementId, window: inout Window) {
        if isPicking() {
            let changed = setActiveElementId(id, window: &window)
            if changed {
                pickDepth = 0.0
            }
        }
    }

    public mutating func setActiveElementId(_ id: InspectorElementId, window: inout Window) -> Bool {
        let changed = activeElement?.id != id
        if changed {
            activeElement = InspectedElement(id: id)
            window.refresh()
        }
        return changed
    }

    public func activeElementId() -> InspectorElementId? {
        activeElement?.id
    }

    public mutating func withActiveElementState<T, R>(
        window: inout Window,
        _ f: (inout T?, inout Window) -> R
    ) -> R {
        guard var elem = activeElement else {
            var none: T? = nil
            return f(&none, &window)
        }
        let key = ObjectIdentifier(T.self)
        var state = elem.states[key] as? T
        let result = f(&state, &window)
        if let state {
            elem.states[key] = state
        } else {
            elem.states.removeValue(forKey: key)
        }
        activeElement = elem
        return result
    }

    public mutating func startPicking() {
        pickDepth = 0.0
    }

    public func isPicking() -> Bool {
        pickDepth != nil
    }

    @MainActor
    public mutating func renderInspectorStates(
        window: inout Window,
        cx: inout Context<Inspector>
    ) -> [AnyElement] {
        guard let activeElement = self.activeElement else {
            return []
        }
        var elements: [AnyElement] = []
        for (typeId, state) in activeElement.states {
            if let renderer = cx.app.inspectorElementRenderer(for: typeId) {
                let element = renderer(activeElement.id, state, &window, &cx.app)
                elements.append(element)
            }
        }
        return elements
    }
}

/// Registry for element-specific inspector renderers.
public struct InspectorElementRegistry: Sendable {
    private var renderers: [ObjectIdentifier: @Sendable (InspectorElementId, Any, inout Window, inout App) -> AnyElement] = [:]

    public init() {}

    public mutating func register<T, R: IntoElement>(
        _ f: @escaping @Sendable (InspectorElementId, T, inout Window, inout App) -> R
    ) {
        let key = ObjectIdentifier(T.self)
        renderers[key] = { id, value, win, app in
            if let typed = value as? T {
                return f(id, typed, &win, &app).intoAnyElement()
            }
            return Empty().intoAnyElement()
        }
    }
}

/// Provides definitions for reflected inspectable properties and functions.
public struct FunctionReflection<T> {
    public var name: String
    public var function: (Any) -> Any
    public var documentation: String?

    public init(name: String, function: @escaping (Any) -> Any, documentation: String? = nil) {
        self.name = name
        self.function = function
        self.documentation = documentation
    }

    public func invoke(_ value: T) -> T {
        if let result = function(value) as? T {
            return result
        }
        return value
    }
}
