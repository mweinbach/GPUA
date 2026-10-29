# 0007: Proc macros → Pure-Swift Idiomatic Architecture & Swift Testing Traits

- **Status:** Accepted (Amended)
- **Date:** 2026-10-28 (Amended 2026-10-29 under R1/R5)

## Context

Upstream GPUI in Rust relies heavily on procedural macros:
- `gpui_macros`: `derive(Action)`, `register_action!`, `derive(IntoElement)`, `derive(Render)`, `derive(AppContext)`, `derive(VisualContext)`, `derive(InspectorReflection)`, `style_helpers!`, and the test harness macros `#[gpui::test]` and `#[gpui::property_test]`.
- `derive_refineable`: `derive(Refineable)` generates structural partial refinements (`*Refinement`) and implements `Refineable`, `IsEmpty`, and `DefaultInitializable`.

While Swift compiler macros (`swift-syntax`) were initially considered, implementing compiler macros in SwiftPM introduces severe drawbacks:
1. Significant build overhead and compile-time latency on every developer workflow and CI run.
2. Cross-compilation bottlenecks on Windows and Android CI runners, where host macro plugins often fail to cross-compile or time out.
3. Lack of runtime reflection in pure macro expansion.

Per **R1** ("Fidelity rule: port logic, not code") and **R5** ("Dependencies and decisions"), GPUA uses a pure-Swift idiomatic architecture that provides genuine behavioral parity with zero compiler plugin overhead.

## Decision

1. **Pure-Swift Target Architecture**:
   - `GPUIMacros` and `DeriveRefineable` are standard library targets (not `.macro` targets), with zero dependency on `swift-syntax`.
   - All files mirror upstream 1:1 (`derive_action.swift`, `styles.swift`, `test.swift`, `derive_refineable.swift`, etc.).

2. **Refineable via KeyPath Descriptors (`DeriveRefineable`)**:
   - `RefineableDescriptor<Target, Refinement>` provides automated field refinement, emptiness testing, superset checks, and subtraction via Swift `KeyPath`s.
   - Types can conform to `AutomaticRefineable` to receive automatic implementations of `refine(with:)`, while manual overrides remain fully supported for performance-critical styling types.

3. **Actions & Reflection (`GPUIMacros`)**:
   - `ActionRegistry` and `ActionDescriptor` provide runtime action registration, namespace qualification, and dynamic dispatch.
   - `registerAction` registers action builders dynamically, matching upstream `register_action!` and `#[derive(Action)]`.
   - `derive_inspector_reflection.swift` implements runtime inspector property descriptors and reflection metadata for styled elements.

4. **Context Forwarding & Element Bridging**:
   - `AppContextForwarding` and `VisualContextForwarding` protocols provide default method forwarding to underlying app and window contexts.
   - `derive_into_element.swift` and `derive_render.swift` supply protocol extensions for element component wrapping and default rendering.

5. **Style Helpers**:
   - `styles.swift` provides style helper protocols and descriptors mapping the upstream `style_helpers!` macro groups into composable Swift extensions on `Styled`.

6. **Swift Testing Harness (`test.swift`, `property_test.swift`)**:
   - `#[gpui::test]` and `#[gpui::property_test]` are mapped to native Swift Testing traits (`.gpui(iterations:seed:)`) using `TestScoping`.
   - Property tests are executed deterministically through `PropertyTestRunner` and `PropertyTestConfig`.

## Consequences

- **Portability**: 100% compiles cleanly and instantly across macOS, Linux, Windows, and Android without requiring host-macro plugins or cross-compilation shims.
- **Speed**: Drastically reduced compilation times compared to compiling `swift-syntax` from source.
- **Behavioral Parity**: All upstream behaviors (refinement, action dispatch, test scheduling, property testing) are fully realized and covered by unit tests.
