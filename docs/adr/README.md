# Architecture Decision Records

Decisions that shape the port. Each one is short: context, decision, consequences. Write a new ADR before you:

- add a dependency (SwiftPM package, vendored C/C++ library, system library),
- deviate from file-for-file mapping or the porting guide,
- add a SwiftPM trait, target, or host shell,
- pick a platform technology (renderer, text stack, JNI approach, …).

Copy [0000-template.md](0000-template.md), take the next number, and open it as a PR. Status is `Proposed` until it's merged. Once merged it becomes `Accepted`. If a later ADR replaces it, mark it `Superseded by NNNN`.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-file-for-file-port.md) | File-for-file port of upstream GPUI | Accepted |
| [0002](0002-module-naming-and-layout.md) | Crate → target naming and file layout | Accepted |
| [0003](0003-concurrency-model.md) | Concurrency model: `@MainActor` app state, GPUI-owned executors | Proposed |
| [0004](0004-renderers.md) | Renderers: Metal, D3D11, and WebGPU via wgpu-native | Proposed |
| [0005](0005-layout-engine.md) | Layout: port Taffy file-for-file | Proposed |
| [0006](0006-text-stack.md) | Text: CoreText / DirectWrite / FreeType + HarfBuzz | Proposed |
| [0007](0007-macros.md) | Proc macros → Swift macros (swift-syntax) | Proposed |
| [0008](0008-features-as-traits.md) | Cargo features → SwiftPM package traits | Accepted |
