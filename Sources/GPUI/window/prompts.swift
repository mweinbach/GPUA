// Ported from: crates/gpui/src/window/prompts.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// What kind of prompt styling to show.
public enum PromptLevel: Sendable, Equatable, Hashable {
    /// A prompt that is shown when the user should be notified of something.
    case info
    /// A prompt that is shown when the user needs to be warned of a potential problem.
    case warning
    /// A prompt that is shown when a critical problem has occurred.
    case critical
}

/// A button displayed inside a modal prompt.
public enum PromptButton: Sendable, Equatable, Hashable {
    /// Standard confirmation / Ok button.
    case ok(SharedString)
    /// Cancel button.
    case cancel(SharedString)
    /// Other / custom action button.
    case other(SharedString)

    public init(_ label: String) {
        self = .other(SharedString(label))
    }

    public static func ok(_ label: String) -> PromptButton {
        .ok(SharedString(label))
    }

    public static func cancel(_ label: String) -> PromptButton {
        .cancel(SharedString(label))
    }

    public var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }

    public var label: SharedString {
        switch self {
        case .ok(let s), .cancel(let s), .other(let s):
            return s
        }
    }
}

/// The event emitted when a prompt's option is selected.
/// The `index` is the 0-based position of the chosen action.
public struct PromptResponse: Sendable, Equatable {
    public var index: Int

    public init(_ index: Int) {
        self.index = index
    }
}

/// A protocol for components that can be focused.
public protocol Focusable {
    func focusHandle(_ cx: App) -> FocusHandle
}

/// A prompt that can be rendered in the window.
public protocol Prompt: EventEmitter<PromptResponse>, Focusable {}

/// A handle to an active prompt used to resolve user choice.
public final class PromptHandle: @unchecked Sendable {
    private var handler: (@Sendable (Int) -> Void)?

    public init(handler: (@Sendable (Int) -> Void)? = nil) {
        self.handler = handler
    }

    /// Construct a new prompt handle with a completion handler.
    public static func withHandler(_ handler: @escaping @Sendable (Int) -> Void) -> PromptHandle {
        PromptHandle(handler: handler)
    }

    /// Send the chosen option index.
    public func send(_ index: Int) {
        if let handler = self.handler {
            self.handler = nil
            handler(index)
        }
    }

    /// Construct a new renderable prompt handle from a view.
    public func withView(
        _ view: AnyView,
        window: inout Window,
        cx: inout App
    ) -> RenderablePromptHandle {
        RenderablePromptHandle(view: view)
    }
}

/// A prompt handle capable of being rendered in a window.
public struct RenderablePromptHandle: @unchecked Sendable {
    public var view: AnyView

    public init(view: AnyView) {
        self.view = view
    }
}

/// Protocol for type-erasing view handles in prompts.
public protocol PromptViewHandle: Sendable {
    func anyView() -> AnyView
}

/// The default GPUI fallback renderer for prompts when the platform doesn't provide native dialogs.
public struct FallbackPromptRenderer: Prompt, Sendable {
    public var level: PromptLevel
    public var message: String
    public var detail: String?
    public var actions: [PromptButton]
    public var focus: FocusHandle

    public init(
        level: PromptLevel,
        message: String,
        detail: String? = nil,
        actions: [PromptButton],
        focus: FocusHandle
    ) {
        self.level = level
        self.message = message
        self.detail = detail
        self.actions = actions
        self.focus = focus
    }

    public func focusHandle(_ cx: App) -> FocusHandle {
        focus
    }
}

/// A prompt renderer callback function signature.
public typealias PromptRendererFunction = @MainActor @Sendable (
    PromptLevel,
    String,
    String?,
    [PromptButton],
    PromptHandle,
    inout Window,
    inout App
) -> RenderablePromptHandle

/// Configures how prompts are built and displayed.
public enum PromptBuilder: @unchecked Sendable {
    case `default`
    case custom(PromptRendererFunction)

    @MainActor
    public func build(
        level: PromptLevel,
        message: String,
        detail: String?,
        actions: [PromptButton],
        handle: PromptHandle,
        window: inout Window,
        cx: inout App
    ) -> RenderablePromptHandle {
        switch self {
        case .default:
            return fallbackPromptRenderer(
                level: level,
                message: message,
                detail: detail,
                actions: actions,
                handle: handle,
                window: &window,
                cx: &cx
            )
        case .custom(let fn):
            return fn(level, message, detail, actions, handle, &window, &cx)
        }
    }
}

/// Use this function to render prompts using the fallback GPUI renderer.
@MainActor
public func fallbackPromptRenderer(
    level: PromptLevel,
    message: String,
    detail: String?,
    actions: [PromptButton],
    handle: PromptHandle,
    window: inout Window,
    cx: inout App
) -> RenderablePromptHandle {
    let focus = window.focusHandle()
    let renderer = FallbackPromptRenderer(
        level: level,
        message: message,
        detail: detail,
        actions: actions,
        focus: focus
    )
    let entity = cx.new { _ in renderer }
    return RenderablePromptHandle(view: AnyView(entityId: entity.entityId))
}
