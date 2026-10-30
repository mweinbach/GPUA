// Ported from: crates/gpui_examples/examples/scrollable.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
import GPUIPlatform

// PORT NOTE: ScrollableView conforms to Sendable for view leasing across contexts.
public struct ScrollableView: Render, Sendable {
    public init() {}

    public mutating func render(_ window: inout Window, _ cx: inout Context<ScrollableView>) -> AnyElement {
        let horizontalDiv = div()
            .w(px(2000.0))
            .h(px(150.0))
            .bg(GPUI.green().opacity(0.1))
            .hover { (this: StyleRefinement) -> StyleRefinement in
                var copy = this
                copy.background = Fill(GPUI.green().opacity(0.2))
                return copy
            }
            .border1()
            .borderColor(GPUI.green())
            .p4()
            .child("Scroll Horizontal")

        let horizontalContainer = div()
            .mb5()
            .wFull()
            .id("horizontal")
            .overflowScroll()
            .child(horizontalDiv)

        let verticalContent = div()
            .h(px(5000.0))
            .border1()
            .borderColor(GPUI.blue())
            .bg(GPUI.blue().opacity(0.05))
            .p4()
            .child(horizontalContainer)
            .child("Scroll Vertical")

        let root = div()
            .sizeFull()
            .id("vertical")
            .p4()
            .overflowScroll()
            .bg(GPUI.white())
            .child("Example for test 2 way scroll in nested layout")
            .child(verticalContent)

        return root.intoAnyElement()
    }
}

public enum ScrollableExample {
    @MainActor
    public static func run() {
        application().run { cx in
            let bounds = Bounds.centered(nil, size: size(px(500.0), px(500.0)), cx)
            _ = try? cx.openWindow(
                WindowOptions(windowBounds: .windowed(bounds))
            ) { _, cx in
                cx.new { _ in
                    ScrollableView()
                }
            }
            cx.activate(ignoringOtherApps: true)
        }
    }
}
