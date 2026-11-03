// Ported from: crates/rune/src/platform.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Platform-specific integration modules (`accent`, `app_icon`, `display_link`, `embed`,
//! `macos`, `main_queue`, `portal_appearance`, `preferences`, `ready_signal`, `reopen`,
//! `web`, `win32`, `x11`).

/// Namespace mirroring `rune::platform::*`.
public enum platform {
    public typealias SystemAccent = Rune.SystemAccent

    public static func systemAccent() -> SystemAccent {
        Rune.systemAccent()
    }

    public static func setAppIcon(_ bytes: [UInt8]) -> Result<Void, AppIconError> {
        Rune.setAppIcon(bytes)
    }
}
