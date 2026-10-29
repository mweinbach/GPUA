// Ported from: crates/gpui/src/prelude.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - GPUI Prelude
// The GPUI prelude is a collection of protocols and types that are widely used
// throughout the library, matching upstream crates/gpui/src/prelude.rs.

public typealias PreludeContext<T> = Context<T>
public typealias PreludeElement = Element
public typealias PreludeInteractiveElement = InteractiveElement
public typealias PreludeIntoElement = IntoElement
public typealias PreludeParentElement = ParentElement
public typealias PreludeRender = Render
public typealias PreludeRenderOnce = RenderOnce
public typealias PreludeStyled = Styled
public typealias PreludeVisualContext = VisualContext
public typealias PreludeFluentBuilder = FluentBuilder
