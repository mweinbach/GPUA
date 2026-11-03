// Ported from: crates/rune/src/input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Input support shared between window hosts and the runtime.
// PORT NOTE: In Swift all files in the `Rune` target share one module namespace; submodules (`canvas_input.swift`, `drop_pointer.swift`, `fn_key.swift`, `input_time.swift`, `key_diagnostics.swift`, `keycaps.swift`, `physical_input.swift`, `pointer_observer.swift`, `secure_input.swift`) expose their public and internal APIs directly.
