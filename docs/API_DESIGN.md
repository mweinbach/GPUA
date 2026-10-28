# API Design

GPUA's public API is **GPUI's public API faithfully ported to idiomatic Swift** using the rules in [PORTING_GUIDE.md](PORTING_GUIDE.md). This page shows what that looks like for users. Treat it as the target the port is aiming for.

> [!NOTE]
> Nothing here compiles yet. These examples are the acceptance tests for the API. If porting reveals that a snippet can't work as written, update this page in the same PR.

## Principles

1. **Conceptually and behaviorally faithful.** Rust GPUI code and concepts map cleanly to GPUA. GPUI docs, blog posts, and Zed's codebase stay useful references.
2. **Same nouns.** `App`, `Window`, `Context<T>`, `Entity<T>`, `Render`, `IntoElement`, `div()`, `px()`, `rgb()`, `SharedString`, `Bounds`, `WindowOptions`.
3. **Swift where it's free.** String interpolation into `SharedString`, trailing closures, `some`/`any`, `throws`, enums with leading-dot syntax, Swift Testing traits, macros instead of derives.
4. **No hidden magic.** No property wrappers or SwiftUI-style implicit dependency tracking. State changes go through `cx.notify()`, as in GPUI.

## Hello, World

**Rust (upstream)**

```rust
struct HelloWorld { text: SharedString }

impl Render for HelloWorld {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .bg(rgb(0x2e7d32))
            .size(px(500.0))
            .justify_center()
            .items_center()
            .text_xl()
            .text_color(rgb(0xffffff))
            .child(format!("Hello, {}!", &self.text))
    }
}

fn main() {
    application().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(500.), px(500.0)), cx);
        cx.open_window(
            WindowOptions { window_bounds: Some(WindowBounds::Windowed(bounds)), ..Default::default() },
            |_, cx| cx.new(|_| HelloWorld { text: "World".into() }),
        )
        .unwrap();
        cx.activate(true);
    });
}
```

**Swift (GPUA)**

```swift
struct HelloWorld: Render {
    var text: SharedString

    mutating func render(_ window: Window, _ cx: Context<Self>) -> some IntoElement {
        div()
            .flex()
            .bg(rgb(0x2e7d32))
            .size(px(500))
            .justifyCenter()
            .itemsCenter()
            .textXl()
            .textColor(rgb(0xffffff))
            .child("Hello, \(text)!")
    }
}

@main enum App_ {
    static func main() {
        application().run { cx in
            let bounds = Bounds.centered(nil, size(px(500), px(500)), cx)
            _ = try! cx.openWindow(WindowOptions(windowBounds: .windowed(bounds))) { _, cx in
                cx.new { _ in HelloWorld(text: "World") }
            }
            cx.activate(true)
        }
    }
}
```

`WindowOptions(windowBounds:)`: Rust's `..Default::default()` struct-update syntax becomes a memberwise `init` where every parameter has a default value, in declaration order.

## State, events, and notify

```swift
struct Counter: Render, EventEmitter {
    typealias Event = CounterEvent
    var count = 0

    mutating func render(_ window: Window, _ cx: Context<Self>) -> some IntoElement {
        div()
            .id("counter")
            .p4()
            .child("Count: \(count)")
            .onClick(cx.listener { this, _event, _window, cx in
                this.count += 1
                cx.emit(.changed(this.count))
                cx.notify()
            })
    }
}

enum CounterEvent { case changed(Int) }

// Elsewhere:
let counter = cx.new { _ in Counter() }
let _subscription = cx.subscribe(counter) { _counter, event, cx in
    if case .changed(let n) = event { print("now \(n)") }
}
counter.update(cx) { state, cx in state.count = 10; cx.notify() }
```

`cx.listener` hands the closure an `inout` reference to the view's state (`this`). Upstream gets the same effect with `&mut Self`.

## Actions and keybindings

**Rust (upstream)**

```rust
actions!(editor, [MoveUp, MoveDown]);

cx.bind_keys([
    KeyBinding::new("up", MoveUp, Some("Editor")),
    KeyBinding::new("down", MoveDown, Some("Editor")),
]);

div()
    .key_context("Editor")
    .on_action(cx.listener(|this, _: &MoveUp, _, cx| { this.selected -= 1; cx.notify(); }))
```

**Swift (GPUA)**

```swift
#actions("editor", MoveUp, MoveDown)

cx.bindKeys([
    KeyBinding("up", MoveUp(), "Editor"),
    KeyBinding("down", MoveDown(), "Editor"),
])

div()
    .keyContext("Editor")
    .onAction(cx.listener { (this, _: MoveUp, _, cx) in this.selected -= 1; cx.notify() })
```

## Async

```swift
cx.spawn { this, cx in                                  // foreground task (main thread)
    let data = await cx.backgroundExecutor().spawn {    // background thread pool, @Sendable
        try loadFile(path)
    }.value
    try this.update(cx) { state, cx in state.data = data; cx.notify() }
}.detach()
```

`Task<T>` is GPUI's type, not Swift's `Task`. Dropping it cancels, as upstream. `.detach()` lets it run to completion. See [ADR-0003](adr/0003-concurrency-model.md).

## Custom elements

```swift
struct Sparkline: Element, IntoElement {
    typealias RequestLayoutState = Void
    typealias PrepaintState = Path<Pixels>?
    var points: [Float]

    func id() -> ElementId? { nil }
    func sourceLocation() -> SourceLocation? { nil }

    mutating func requestLayout(_ id: GlobalElementId?, _ iid: InspectorElementId?,
                                _ window: Window, _ cx: App) -> (LayoutId, Void) {
        var style = Style(); style.size = .full
        return (window.requestLayout(style, [], cx), ())
    }

    mutating func prepaint(_ id: GlobalElementId?, _ iid: InspectorElementId?, _ bounds: Bounds<Pixels>,
                           _ rl: inout Void, _ window: Window, _ cx: App) -> Path<Pixels>? {
        var builder = PathBuilder.stroke(px(1.5))
        // … add points within bounds …
        return try? builder.build()
    }

    mutating func paint(_ id: GlobalElementId?, _ iid: InspectorElementId?, _ bounds: Bounds<Pixels>,
                        _ rl: inout Void, _ path: inout Path<Pixels>?, _ window: Window, _ cx: App) {
        if let path { window.paintPath(path, rgb(0x4caf50)) }
    }
}
```

## Tests

```swift
@Test(.gpui) @MainActor
func test_counter_increments() async throws {
    let cx = TestAppContext.current
    let counter = cx.new { _ in Counter() }
    counter.update(cx) { state, cx in state.count += 1; cx.notify() }
    cx.runUntilParked()
    #expect(counter.read(cx).count == 1)
}
```

## Shipping an app per platform

| Platform | How a GPUA app is packaged |
|---|---|
| macOS | Executable product (`swift run`) or an Xcode app target that depends on the package |
| iOS / visionOS | Thin Xcode host app (a port of upstream `hosts/ios`, generated from `project.yml`) that calls into your Swift entry point |
| Linux | Executable product. Needs Wayland or X11 + Vulkan drivers at runtime |
| Windows | Executable product (`swift build -c release`). D3D11 is available on every supported Windows |
| Android | Your Swift code builds to a `.so` with the Swift SDK for Android. A thin Gradle host app (`hosts/android`, to be created) loads it through `GameActivity`/`NativeActivity` |
| Web | Wasm build through the Swift SDK for Wasm + a small HTML/JS bootstrap (port of `hosts/web`) |

Host shells mirror upstream's `hosts/` model: native wrappers stay thin, and all behavior lives in Swift targets.
