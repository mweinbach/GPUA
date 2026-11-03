// Ported from: crates/rune/src/input/secure_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS) && canImport(Carbon)
import Carbon
#endif

/// One balanced native secure-input claim per focused, visible password window.
internal final class SecureInput {
    internal private(set) var isActive: Bool = false

    internal init() {}

    internal func set(_ active: Bool) {
        if active == isActive { return }
        #if os(macOS) && canImport(Carbon)
        if active {
            isActive = (EnableSecureEventInput() == noErr)
        } else {
            _ = DisableSecureEventInput()
            isActive = false
        }
        #else
        isActive = active
        #endif
    }

    deinit {
        set(false)
    }
}
