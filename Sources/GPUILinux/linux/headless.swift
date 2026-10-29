// Ported from: crates/gpui_linux/src/linux/headless.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
// In upstream, mod client; pub(crate) use client::*;
// HeadlessClient and HeadlessClientState are declared in headless_client.swift within module GPUILinux.
#endif
