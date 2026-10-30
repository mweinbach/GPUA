// Ported from: crates/gpui_examples/examples/hello_world.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
import GPUIPlatform

// PORT NOTE: HelloWorld view model conforms to Sendable for view leasing across contexts.
public struct HelloWorld: Render, Sendable {
    public var text: SharedString

    public init(text: SharedString = "World") {
        self.text = text
    }

    public mutating func render(_ window: inout Window, _ cx: inout Context<HelloWorld>) -> AnyElement {
        div()
            .flex()
            .flexCol()
            .gap3()
            .bg(Hsla(rgba: rgb(0x505050)))
            .size(px(500.0))
            .justifyCenter()
            .itemsCenter()
            .shadowLg()
            .border1()
            .borderColor(Hsla(rgba: rgb(0x0000ff)))
            .textXl()
            .textColor(Hsla(rgba: rgb(0xffffff)))
            .child("Hello, \(text)!")
            .child(
                div()
                    .flex()
                    .gap2()
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.red())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.green())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.blue())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.yellow())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.black())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.white())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.black())
                    )
            )
            .intoAnyElement()
    }
}

public enum HelloWorldExample {
    @MainActor
    public static func run() {
        application().run { cx in
            let bounds = Bounds.centered(nil, size: size(px(500.0), px(500.0)), cx)
            _ = try? cx.openWindow(
                WindowOptions(windowBounds: .windowed(bounds))
            ) { _, cx in
                cx.new { _ in
                    HelloWorld(text: "World")
                }
            }
            cx.activate(ignoringOtherApps: true)
        }
    }
}
