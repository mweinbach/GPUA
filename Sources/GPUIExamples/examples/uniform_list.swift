// Ported from: crates/gpui_examples/examples/uniform_list.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
import GPUIPlatform

// PORT NOTE: UniformListView conforms to Sendable for view leasing across contexts.
public struct UniformListView: Render, Sendable {
    public init() {}

    public mutating func render(_ window: inout Window, _ cx: inout Context<UniformListView>) -> AnyElement {
        div()
            .sizeFull()
            .bg(GPUI.white())
            .child(
                uniformList(
                    "entries",
                    50
                ) { range, window, cx in
                    range.map { ix in
                        let item = ix + 1
                        return div()
                            .id(ElementId(UInt64(ix)))
                            .px2()
                            .cursorPointer()
                            .onClick { event, window, cx in
                                print("clicked Item \(item)")
                            }
                            .child("Item \(item)")
                            .intoAnyElement()
                    }
                }
                .hFull()
            )
            .intoAnyElement()
    }
}

public enum UniformListExample {
    @MainActor
    public static func run() {
        application().run { cx in
            let bounds = Bounds.centered(nil, size: size(px(300.0), px(300.0)), cx)
            _ = try? cx.openWindow(
                WindowOptions(windowBounds: .windowed(bounds))
            ) { _, cx in
                cx.new { _ in
                    UniformListView()
                }
            }
        }
    }
}
