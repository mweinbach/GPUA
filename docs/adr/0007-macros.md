# 0007: Proc macros → Swift macros (swift-syntax)

- **Status:** Proposed
- **Date:** 2026-10-27

## Context

Upstream uses proc macros heavily. `gpui_macros` provides `derive(Action)`, `derive(IntoElement)`, `derive(AppContext)`, `derive(VisualContext)`, `derive(InspectorReflection)`, `register_action!`, `style_helpers!`, `{visibility,margin,padding,position,overflow,cursor,border,box_shadow}_style_methods!`, `#[gpui::test]`, and `#[gpui::property_test]`. `derive_refineable` provides `derive(Refineable)`. The `styled.rs` helpers alone expand to hundreds of methods.

## Decision

- `GPUIMacros` and `DeriveRefineable` become SwiftPM `.macro` targets depending on **swift-syntax**. Their files mirror upstream (`styles.rs` → `styles.swift`, …).
- Macro *declarations* (`@freestanding(declaration) public macro styleHelpers() = #externalMacro(…)`) live in `GPUI` and `Refineable`, next to where upstream re-exports the proc macros.
- Freestanding declaration macros are allowed inside type and extension bodies with `names: arbitrary`, which lets `styled.swift` say `extension Styled { #styleHelpers() }`, mirroring `style_helpers!()`.
- `#[gpui::test]` and `#[gpui::property_test]` become Swift Testing traits (`.gpui(iterations:seed:)`) using `TestScoping`, not macros. Their files (`test.swift`, `property_test.swift`) live in `GPUIMacros` for mapping purposes but hold only a `// PORT NOTE:` pointing to the trait in `GPUI/test.swift`.
- Use swift-syntax prebuilts (SwiftPM 6.1+) to keep build times reasonable.

## Consequences

Adds one dependency (swift-syntax) for the whole package. Macros run on the host, so cross-compiling to Android/Windows/Wasm is unaffected. Until this lands, macro-dependent code stays `fatalError("TODO(port): needs GPUIMacros")`.
