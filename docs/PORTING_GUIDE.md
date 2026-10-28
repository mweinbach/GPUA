# Porting Guide

How to port GPUI's Rust into GPUA's Swift. The overarching principle is the **Fidelity Rule**: **port logic, not code**.

- **1:1 Mapping & Provenance**: Keep the existing 1:1 upstream-file → Swift-file mapping and per-file headers (`Ported from`, `Upstream commit`, `Port status`).
- **Idiomatic Swift**: Inside each file, any idiomatic Swift is fine as long as behavior matches upstream, and tests must demonstrate that. Do not force Rust borrow patterns, lifetime workarounds, or raw pointer gymnastics into Swift where Swift provides native language or standard library features.
- **Substitutions**: Where Swift or the platform offers a different way to get the same result, use it and note the substitution with a `// PORT NOTE: <rationale>`.

When this guide doesn't cover something, pick the most faithful option, leave a `// PORT NOTE:`, and open a PR that adds the rule here.

---

## 1. File mapping rules

The rules are implemented in [`Scripts/port.py`](../Scripts/port.py) and configured in [`porting.json`](../porting.json). **Use `Scripts/port.py map <path>` instead of working them out by hand.**

| Upstream | Swift |
|---|---|
| `crates/<crate>/src/<path>.rs` | `Sources/<Target>/<path>.swift` |
| `crates/<crate>/src/<dir>/mod.rs` | `Sources/<Target>/<dir>/<dir>.swift` |
| `crates/<crate>/examples/<path>.rs` | `Sources/<Target>/examples/<path>.swift` |
| `#[cfg(test)]` items inside `src/<path>.rs` | `Tests/<Target>Tests/<path>.swift` (same name as the source file) |
| `crates/<crate>/tests/<path>.rs` | `Tests/<Target>Tests/tests/<path>.swift` |
| `*.metal`, `*.wgsl`, `*.hlsl`, example images | Copied verbatim to the same relative path, declared as resources |
| `build.rs`, `Cargo.toml`, `*.h` bindgen inputs | Not mapped; their effects go into `Package.swift` or SwiftPM plugins |

**Filename collisions.** SwiftPM fails when two files in one target share a basename (`window.swift` twice → "multiple producers"). When that happens, the shallowest file keeps the plain name, and deeper files are prefixed with their parent directory names until unique:

```
crates/gpui/src/window.rs                 → Sources/GPUI/window.swift
crates/gpui/src/platform/test/window.rs   → Sources/GPUI/platform/test/test_window.swift
crates/gpui/src/app/context.rs            → Sources/GPUI/app/app_context.swift
crates/gpui/src/keymap/context.rs         → Sources/GPUI/keymap/keymap_context.swift
```

File names stay `snake_case` like upstream. That's deliberate: it makes the mapping greppable and scriptable.

### Crate → target names

Crate names are PascalCased: `gpui` → `GPUI`, `gpui_macos` → `GPUIMacOS`, `sum_tree` → `SumTree`. There are two exceptions to avoid module-name clashes: `collections` → `GPUICollections` and `util` → `ZedUtil`. `porting.json` is authoritative.

### Swift-only files

Some files have no upstream counterpart: the examples' `main.swift`, the Android backend, or shims that replace a Rust crate. Their first line must be:

```swift
// Swift-only: <one-line reason>
```

---

## 2. File headers & status lifecycle

Every mapped Swift file starts with:

```swift
// Ported from: crates/gpui/src/geometry.rs
// Upstream commit: 650aab59d54f
// Port status: ported
```

| Status | Meaning |
|---|---|
| `not-started` | Scaffolded stub. Empty. |
| `in-progress` | Partially translated. May contain `fatalError("TODO(port)")` bodies. |
| `ported` | All logic and behavior from the upstream file are ported into idiomatic Swift, compiling on all CI platforms, with behavioral tests ported and passing (or disabled with a reason). |
| `verified` | Reviewed side by side against upstream by someone other than the porter, and exercised by an example or integration test. |
| `skipped` | Intentionally not ported. **Requires** a `// Skip reason: …` line, e.g. `// Skip reason: objc runtime helpers; Swift has native ObjC interop.` |

`Upstream commit:` records the commit the file was last synced to. `Scripts/port.py stale` uses it to show what changed upstream since then.

Inside a file, mark incomplete parts like this:

```swift
func paint(...) {
    fatalError("TODO(port): crates/gpui/src/elements/div.rs paint() scroll handling")
}
```

`grep -r "TODO(port)" Sources` gives you the work list inside partially ported files.

---

## 3. Naming

| Rust | Swift | Example |
|---|---|---|
| Types, traits, enum names | **Verbatim** | `Hsla`, `SharedString`, `AnyElement`, `PlatformWindow` |
| Functions, methods, fields, locals | lowerCamelCase, mechanically | `flex_col` → `flexCol`, `request_layout` → `requestLayout` |
| Digits | Join, but keep `_` between two digit runs | `size_8` → `size8`, `gap_0p5` → `gap0p5`, `w_1_2` → `w1_2` |
| Enum variants | lowerCamelCase cases | `WindowBounds::Windowed(b)` → `.windowed(b)` |
| `const`/`static` items | lowerCamelCase `let` / `static let` | `DEFAULT_WINDOW_SIZE` → `defaultWindowSize` |
| Swift keywords | Backticks | `default` → `` `default` ``, `in` → `` `in` `` |
| Acronyms inside identifiers | Don't re-case; follow the mechanical rule | `text_xl` → `textXl`, `rgba` → `rgba`, `to_rgb` → `toRgb` |
| Free functions | Keep as free functions | `div()`, `px(5)`, `rgb(0x505050)`, `size(px(1), px(2))` |

**Parameters are unlabeled by default** (`func openWindow(_ options: WindowOptions, _ build: …)`), so Swift call sites read like Rust ones. Add a label only when Swift overloading needs one to disambiguate. Trailing closures are encouraged where the Rust closure is the last argument.

---

## 4. Visibility

| Rust | Swift |
|---|---|
| `pub` and reachable from the crate root (`pub use`) | `public` |
| `pub` but only used by sibling crates (e.g. gpui internals used by `gpui_macos`), often `#[doc(hidden)]` | `package` |
| `pub` within a private module, `pub(crate)`, `pub(super)` | `internal` (the default; omit the keyword) |
| private | `private`, or `fileprivate` when an extension in the same file needs it |

---

## 5. Language idioms

### Types & ownership

| Rust | Swift | Notes |
|---|---|---|
| `struct` that is `Copy`/`Clone` and small (geometry, colors, ids) | `struct` (+ `Hashable`, `Sendable` where derived) | Value semantics match. |
| `struct` with identity/shared mutation (held in `Rc<RefCell<…>>`) | `final class` | |
| `enum` with data | `enum` with associated values | `indirect` if recursive. |
| `trait` | `protocol` | Default methods go in a protocol extension. |
| Associated types | `associatedtype` | `Element::RequestLayoutState` → `associatedtype RequestLayoutState`. |
| `dyn Trait`, `Box<dyn Trait>`, `Rc<dyn Trait>`, `Arc<dyn Trait>` | `any Trait` | `ExistentialAny` is on, so be explicit. |
| `impl Trait` in argument position | `some Trait` | |
| `impl Trait` in return position | `some Trait` | `fn render(...) -> impl IntoElement` → `-> some IntoElement`. |
| Generic bounds `T: A + B` | `T: A & B` or `where` clause | |
| `Rc<T>` / `Arc<T>` | Class reference | |
| `Weak<T>` | `weak var` / a small `Weak<T>` box | |
| `RefCell<T>` / `Cell<T>` / `Mutex<T>` | `var` on a class / `Mutex` from `Synchronization` (Swift 6) | Don't reproduce `RefCell` borrow panics, **except** for entity leasing (see §6). |
| `&mut T` parameter (value type) | `inout T` | `update(cx) { state, cx in }` → `state` is `inout`. |
| `&mut App`, `&mut Window`, `&mut Context<T>` | `App`, `Window`, `Context<T>` (classes, passed by reference) | |
| `&T`, `&str`, `&[T]` | `T`, `String`/`Substring`, `[T]`/`ArraySlice<T>` | Use `borrowing` only where profiling says it matters. |
| `String` | `String` | |
| `SharedString` (Arc<str> or &'static) | `SharedString` struct wrapping `String` | Keep the type; it's in the public API. Conform to `ExpressibleByStringLiteral`/`ExpressibleByStringInterpolation`. |
| `Option<T>` | `T?` | `.unwrap()` → `!`; `.unwrap_or(x)` → `?? x`; `.map` → `.map`. |
| `Result<T, E>` | `throws(E) -> T`, or `Result<T, E>` when stored | `anyhow::Result<T>` → `throws -> T`. `?` → `try`. |
| `panic!` / `unreachable!` / `.expect("m")` | `fatalError("m")` / `preconditionFailure("m")` | `debug_assert!` → `assert`. `assert!` → `precondition`. |
| Lifetimes | Dropped | If a lifetime enforces scoping, use a closure-scoped API instead. |
| `usize` / `isize` | `Int` | `u32`/`i32`/`u8`/`f32`/`f64` keep exact widths: `UInt32`, `Int32`, `UInt8`, `Float`, `Double`. GPU-facing structs must match shader layout exactly. |
| Tuples | Tuples | |
| `SmallVec<[T; N]>`, `ArrayVec` | `[T]` | Optimize later with profiling. |
| `HashMap`/`HashSet`/`BTreeMap`/`IndexMap` | `Dictionary`/`Set`/sorted array or a GPUICollections type/`OrderedDictionary` | `collections` crate aliases map to `GPUICollections`. |
| `slotmap::SlotMap` | `SlotMap` in `GPUICollections` (Swift-only file) | Generation-checked keys matter for `EntityId`/`WindowId`. |
| `#[derive(Debug)]` | `CustomDebugStringConvertible` only if used | |
| `#[derive(PartialEq, Eq, Hash)]` | `Equatable, Hashable` | |
| `#[derive(Default)]` | `init()` with defaults | |
| `#[derive(Serialize, Deserialize)]` | `Codable` | Match serde renames with `CodingKeys`. `JsonSchema` is dropped with a `// PORT NOTE:`. |
| `#[derive(Clone)]` | Nothing (structs are values) | For classes, add `clone()` only if upstream calls it for a deep copy. |
| `impl Deref for X { Target = Y }` | See §6 "Deref" | |
| `impl From<A> for B` | `extension B { init(_ a: A) }` | Implicit `.into()` calls become explicit `B(a)` or literal conformances. |
| `impl Display` | `CustomStringConvertible` | |
| Operator traits (`Add`, `Mul`, …) | Static operator funcs | |
| Iterators / `impl Iterator<Item = T>` | `some Sequence<T>` / `LazySequence` | Chains translate directly: `.iter().map().filter()` → `.lazy.map().filter()`. |
| Closures `Box<dyn FnMut(&mut App)>` | `@escaping (App) -> Void` | `FnOnce` → plain closure (document single-call). `Send` closures → `@Sendable`. |
| `macro_rules!` | Hand-expand, or a Swift macro (§8) | |
| `mod foo { … }` inline | `enum foo {}` namespace, or flatten with `fileprivate` | |

### Porting Logic vs. Transliterating Syntax

Rust and Swift handle memory, ownership, and concurrency through different paradigms:
- **Ownership & Lifetimes**: Rust's explicit lifetime annotations (`'a`) and borrow checker guards exist to satisfy compile-time memory safety without a garbage collector or runtime ARC. Swift uses ARC and automatic value semantics. Do not simulate Rust borrow scopes or double-option tricks in Swift when a standard Swift property, optional unwrapping, or closure scope achieves the same behavior.
- **Collections**: Use standard Swift `Dictionary`, `Set`, and `Array` unless exact memory layout or monoidal indexing requires specialized types (e.g., `SumTree`, `SlotMap`).
- **Error Handling**: Use Swift's native `throws` / `try` for recoverable errors.
- **Documentation of Deviations**: Always place a `// PORT NOTE: <explanation>` comment when substituting a Swift-idiomatic pattern or platform API for Rust internals.

### Item placement

- An `impl Trait for Type` block becomes `extension Type: Trait { … }` **in the file where the impl lives upstream**, even if `Type` is declared in another file.
- An inherent `impl Type { … }` block in a different file from the type becomes `extension Type { … }` in that file.
- Stored properties have to live on the primary declaration. If upstream adds fields through some other mechanism, add them to the primary type and leave a `// PORT NOTE:`.

### `cfg` and features

| Rust | Swift |
|---|---|
| `#[cfg(target_os = "macos")]` | `#if os(macOS)` |
| `#[cfg(target_os = "ios")]` | `#if os(iOS) \|\| os(visionOS)` |
| `#[cfg(any(target_os = "linux", target_os = "freebsd"))]` | `#if os(Linux) \|\| os(FreeBSD)` |
| `#[cfg(target_os = "windows")]` | `#if os(Windows)` |
| `#[cfg(target_family = "wasm")]` | `#if os(WASI)` / `#if arch(wasm32)` |
| `#[cfg(test)]` (in library code) | `#if TestSupport` |
| `#[cfg(feature = "test-support")]` | `#if TestSupport` (SwiftPM trait) |
| `#[cfg(feature = "inspector")]`, `"screen-capture"`, `"wayland"`, `"x11"`, `"runtime_shaders"` | `#if Inspector`, `ScreenCapture`, `Wayland`, `X11`, `RuntimeShaders` |
| `#[cfg(debug_assertions)]` | `#if DEBUG` |

Cargo features map to **SwiftPM package traits**, declared in `Package.swift`. Adding a trait needs an ADR.

---

## 6. GPUI-specific patterns

These need extra care because they carry GPUI's semantics.

### Entities (`app/entity_map.rs`)

- Keep the design: `App` owns every entity's state in an `EntityMap`. `Entity<T>` is a strong, ref-counted **handle** (an id plus a ref count), not the state itself. `WeakEntity<T>` is the weak version.
- Store state in a type-erased box (`final class EntityCell<T> { var value: T }`). Views are usually Swift **structs**, so `inout` access works naturally.
- **Leasing:** `entity.update(cx) { state, cx in … }` takes the state out of the map for the duration of the call (`lease`/`end_lease`). Re-entrant updates of the same entity are a bug upstream (they panic), and they must `preconditionFailure` here too. This is the one `RefCell`-style check we keep.
- Ref counting and leak detection (`leak-detection` feature) port 1:1 under `#if TestSupport`.

### Contexts and `Deref`

Rust `Context<T>` derefs to `App`, so `cx.open_window(…)` works on both. Swift has no `Deref`. Use the following pattern, and update this section if Phase 2 proves it wrong:

```swift
/// Anything that can stand in for `&mut App` (Rust: `Deref<Target = App>`).
public protocol AppDeref: AnyObject { var app: App { get } }
extension App: AppDeref { public var app: App { self } }
extension Context: AppDeref { /* stored `app` */ }

// Upstream `impl App { pub fn open_window(..) }` is written as:
extension AppDeref {
    public func openWindow<V: Render>(_ options: WindowOptions, _ build: …) throws -> WindowHandle<V> { … app … }
}
```

Methods that `Context<T>` itself defines (`notify`, `spawn`, `listener`, `emit`, …) stay on `Context`. Swift picks the concrete method over the protocol-extension method, which matches Rust's method resolution through `Deref`.

### `AppContext` / `VisualContext` traits

These port directly as protocols (`gpui.rs`). Their generic methods (`new`, `update_entity`, `read_entity`, …) become protocol requirements. Because these protocols have associated types (`type Result<T>`), keep the associated type and use `some AppContext`.

### Elements

```swift
public protocol Element: IntoElement {
    associatedtype RequestLayoutState
    associatedtype PrepaintState

    func id() -> ElementId?
    func sourceLocation() -> SourceLocation?
    mutating func requestLayout(_ id: GlobalElementId?, _ inspectorId: InspectorElementId?,
                                _ window: Window, _ cx: App) -> (LayoutId, RequestLayoutState)
    mutating func prepaint(_ id: GlobalElementId?, _ inspectorId: InspectorElementId?,
                           _ bounds: Bounds<Pixels>, _ requestLayout: inout RequestLayoutState,
                           _ window: Window, _ cx: App) -> PrepaintState
    mutating func paint(_ id: GlobalElementId?, _ inspectorId: InspectorElementId?,
                        _ bounds: Bounds<Pixels>, _ requestLayout: inout RequestLayoutState,
                        _ prepaint: inout PrepaintState, _ window: Window, _ cx: App)
}
```

- `AnyElement` is a class box over `any Element` that keeps its own `RequestLayoutState`/`PrepaintState` (mirror `element.rs`'s `ElementObject`/`Drawable`).
- Upstream allocates elements in a frame arena (`arena.rs`). Port the arena API, but backing it with ordinary allocation is fine for a first pass (`// PORT NOTE:`). Measure before optimizing.
- `#[track_caller]`/`panic::Location` → `#fileID`/`#line` default arguments packed into `SourceLocation`.

### Fluent styling (`styled.rs`, `gpui_macros/src/styles.rs`)

`Styled` is a protocol with `var style: StyleRefinement { get set }` (Rust: `fn style(&mut self) -> &mut StyleRefinement`). Every helper is a consuming builder:

```swift
extension Styled {
    public func flexCol() -> Self { var s = self; s.style.flexDirection = .column; return s }
}
```

Rust generates most helpers with proc macros (`style_helpers!`, `margin_style_methods!`, …). Port those as Swift macros in `GPUIMacros` (§8) so `styled.swift` keeps the same shape as `styled.rs`.

### Actions

- `#[derive(Action)]` / `actions!(ns, [A, B])` → `@Action` / `#actions("ns", A.self, B.self)` macros (§8).
- Upstream registers actions at link time with `inventory`. Swift has no stable equivalent, so action registration is **explicit** (generated by the macro and collected at `App` startup). `// PORT NOTE:` wherever `inventory::submit!` appears.

### Executors and async (`executor.rs`, `scheduler`)

- GPUI is **main-thread, single-threaded** for app state, with a `ForegroundExecutor` (main thread, `!Send` futures) and a `BackgroundExecutor` (thread pool).
- App state (`App`, `Window`, `Context`, entities) is `@MainActor`. Background work takes `@Sendable` closures.
- **Determinism under test is required.** `TestDispatcher` must keep control of scheduling (random interleavings, `run_until_parked`, seeded iterations). That rules out a plain `Task { }` on the global executor for GPUI tasks. GPUI's `Task<T>` is ported as its own type, driven by `PlatformDispatcher`, with Swift `async` functions bridged in through custom executors. See [ADR-0003](adr/0003-concurrency-model.md).
- `futures::channel`, `postage`, and `async-channel` → `AsyncStream` or small ported channel types. `smol::Timer` → `executor.timer(…)`.

### Platform traits (`platform.rs`)

- `Platform`, `PlatformWindow`, `PlatformDisplay`, `PlatformDispatcher`, `PlatformTextSystem`, `PlatformAtlas`, `PlatformKeyboardLayout`, `InputHandler` → protocols with the same members, in the same order.
- Raw pointers (`*mut c_void` native handles) → `UnsafeMutableRawPointer?`. On Apple, prefer passing `NSView`/`UIView` where the upstream pointer is only bridged straight back.
- `raw-window-handle` → a small Swift-only `RawWindowHandle` enum in `GPUI` (AppKit/UIKit/Win32/Wayland/Xlib/AndroidNdk/Web cases) that renderers consume.

### Objective-C / Win32 / C bindings

- **Apple:** use AppKit/UIKit/Metal/CoreText directly. Most of `gpui_apple/src/objc/*` (manual class declaration, ivars, retain/release) becomes unnecessary. Mark those files `skipped` with a reason, but **port the behavior** (e.g. a custom `NSView` subclass declared via `ClassDecl` becomes `final class GPUIView: NSView`).
- **Windows:** use the `WinSDK` module that ships with Swift on Windows (COM, D3D11, DirectWrite, DirectComposition). The `windows` crate calls map almost 1:1.
- **Linux/Android:** C libraries (wayland-client, xcb, xkbcommon, FreeType, HarfBuzz, fontconfig, the NDK) come in through `systemLibrary` or vendored C targets named `C<Lib>` (e.g. `CWayland`). Adding one needs an ADR.

### Shaders

Shaders are copied verbatim. Every Swift struct uploaded to the GPU (`Quad`, `Shadow`, `PathSprite`, …) must match the shader's memory layout exactly. Use explicit widths, padding fields, and `MemoryLayout` assertions in tests. On Metal, load the `.metal` source from `Bundle.module` and compile it at runtime first. Precompiling a `.metallib` with a build plugin comes later.

---

## 7. Tests

- **Behavioral Parity Is Validated by Tests**: Porting logic rather than syntax makes tests the authoritative proof of fidelity. Every upstream test in `#[cfg(test)]` should have a matching `@Test` in Swift that verifies identical state transitions, outputs, edge cases, and deterministic execution.
- Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`).
- Placement: §1. One test file per upstream file that has `#[cfg(test)]`. Keep test function names (`fn test_foo` → `@Test func test_foo()`). Snake case is fine in tests because it keeps them greppable against upstream.
- `#[gpui::test]` / `#[gpui::test(iterations = 10, seed = 1)]` becomes a Swift Testing trait ported from `gpui_macros/src/test.rs`:
  ```swift
  @Test(.gpui(iterations: 10)) @MainActor
  func test_window_focus() async throws {
      let cx = TestAppContext.current
      …
  }
  ```
- `proptest` → seeded randomized loops using GPUI's own RNG, so failures reproduce.
- Platform-only tests (AppKit main thread, etc.) are guarded by the same `#if` as the target and `.disabled(if:)` where they need a display.

---

## 8. Macros & code generation

Upstream proc-macro crates map to SwiftPM **macro targets** built on swift-syntax:

| Upstream | Swift |
|---|---|
| `gpui_macros` (`derive(Action)`, `derive(IntoElement)`, `derive(Render)`, `style_helpers!`, `#[gpui::test]`, `register_action!`, …) | `GPUIMacros` (`.macro` target). Macro declarations live in `GPUI` next to where upstream re-exports them. |
| `derive_refineable` (`#[derive(Refineable)]`) | `DeriveRefineable` (`.macro` target), used by `Refineable` as `@Refineable` |

Until the swift-syntax dependency lands (its own ADR and PR), these targets are plain targets holding stubs. **Don't hand-expand macro output into call sites.** Leave a `fatalError("TODO(port): needs GPUIMacros")` instead, so the macro port has a single place to land.

---

## 9. Comments & docs

- Translate `///` and `//!` doc comments into Swift DocC (`///`). `[`Foo`]` intra-doc links become ``` ``Foo`` ```.
- Keep upstream code examples in doc comments, translated to Swift.
- Put deviations in `// PORT NOTE: <why>`. Don't silently change behavior.

---

## 10. Worked example

Upstream (`crates/gpui/src/geometry.rs`, abridged):

```rust
/// A point on a two-dimensional plane.
#[derive(Refineable, Default, Add, AddAssign, Sub, SubAssign, Copy, Debug, PartialEq, Eq, Hash)]
#[refineable(Debug)]
#[repr(C)]
pub struct Point<T: Clone + Debug + Default + PartialEq> {
    pub x: T,
    pub y: T,
}

pub const fn point<T: Clone + Debug + Default + PartialEq>(x: T, y: T) -> Point<T> {
    Point { x, y }
}

impl<T: Clone + Debug + Default + PartialEq> Point<T> {
    pub fn map<U: Clone + Debug + Default + PartialEq>(&self, f: impl Fn(T) -> U) -> Point<U> {
        Point { x: f(self.x.clone()), y: f(self.y.clone()) }
    }
}
```

Swift (`Sources/GPUI/geometry.swift`):

```swift
/// A point on a two-dimensional plane.
@Refineable
public struct Point<T: GeometryValue>: Hashable {   // PORT NOTE: GeometryValue = Clone + Debug + Default + PartialEq
    public var x: T
    public var y: T

    public init(x: T, y: T) { self.x = x; self.y = y }
}

public func point<T: GeometryValue>(_ x: T, _ y: T) -> Point<T> {
    Point(x: x, y: y)
}

extension Point {
    public func map<U: GeometryValue>(_ f: (T) -> U) -> Point<U> {
        Point<U>(x: f(x), y: f(y))
    }
}

// derive(Add, AddAssign, Sub, SubAssign)
extension Point where T: AdditiveArithmetic {
    public static func + (lhs: Self, rhs: Self) -> Self { Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: Self, rhs: Self) -> Self { Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
}
```
