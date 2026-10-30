// Ported from: crates/gpui_examples/examples/text_layout.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
import GPUIPlatform

// PORT NOTE: TextLayoutView conforms to Sendable for view leasing across contexts.
public struct TextLayoutView: Render, Sendable {
    public init() {}

    public mutating func render(_ window: inout Window, _ cx: inout Context<TextLayoutView>) -> AnyElement {
        let alignChildren: [AnyElement] = [
            div().child("Text left").intoAnyElement(),
            div().textCenter().child("Text center").intoAnyElement(),
            div().textRight().child("Text right").intoAnyElement(),
            div().textDecoration1().child("Text left (underline)").intoAnyElement(),
            div().textCenter().textDecoration1().child("Text center (underline)").intoAnyElement(),
            div().textRight().textDecoration1().child("Text right (underline)").intoAnyElement(),
            div().lineThrough().child("Text left (line_through)").intoAnyElement(),
            div().textCenter().lineThrough().child("Text center (line_through)").intoAnyElement(),
            div().textRight().lineThrough().child("Text right (line_through)").intoAnyElement(),
        ]

        let boxRow = div()
            .flex()
            .gap2()
            .justifyBetween()
            .child(
                div()
                    .w(px(400.0))
                    .border1()
                    .borderColor(GPUI.blue())
                    .p1()
                    .whitespaceNowrap()
                    .overflowHidden()
                    .textCenter()
                    .child("A long non-wrapping text align center")
            )
            .child(
                div()
                    .w32()
                    .border1()
                    .borderColor(GPUI.blue())
                    .p1()
                    .whitespaceNowrap()
                    .overflowHidden()
                    .textRight()
                    .child("100%")
            )

        let styledRow = div()
            .flex()
            .gap2()
            .justifyBetween()
            .child(
                StyledText.new("ABCD").withHighlights([
                    (0..<1, HighlightStyle(FontWeight.extraBold)),
                    (2..<3, HighlightStyle(FontStyle.italic)),
                ])
            )

        return div()
            .bg(GPUI.white())
            .flex()
            .flexCol()
            .gap2()
            .p4()
            .sizeFull()
            .children(alignChildren)
            .child(boxRow)
            .child(styledRow)
            .intoAnyElement()
    }
}

public enum TextLayoutExample {
    @MainActor
    public static func run() {
        application().run { cx in
            let bounds = Bounds.centered(nil, size: size(px(800.0), px(600.0)), cx)
            _ = try? cx.openWindow(
                WindowOptions(windowBounds: .windowed(bounds))
            ) { _, cx in
                cx.new { _ in
                    TextLayoutView()
                }
            }
            cx.activate(ignoringOtherApps: true)
        }
    }
}
