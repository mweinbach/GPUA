// Ported from: crates/gpui_macros/src/derive_into_element.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Protocol matching upstream `derive(IntoElement)` which maps a component view struct into an Element.
public protocol ComponentConvertible: Sendable {
    associatedtype ComponentElement
    func intoComponentElement() -> ComponentElement
}

/// Generic wrapper holding a component instance for element conversion.
public struct ComponentWrapper<T: Sendable>: Sendable {
    public var component: T

    public init(_ component: T) {
        self.component = component
    }
}
