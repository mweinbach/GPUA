// Ported from: crates/gpui_macros/src/derive_render.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Descriptor and marker protocol matching upstream `derive(Render)` which provides default empty rendering.
public protocol DefaultRenderable: Sendable {
    associatedtype RenderOutput
    func renderDefault() -> RenderOutput
}

public struct EmptyRenderOutput: Sendable, Equatable {
    public init() {}
}

extension DefaultRenderable where RenderOutput == EmptyRenderOutput {
    public func renderDefault() -> EmptyRenderOutput {
        EmptyRenderOutput()
    }
}
