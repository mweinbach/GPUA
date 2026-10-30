// Ported from: crates/gpui_ios/src/text_input/events.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// High-level events emitted by the UIKit-backed text input control to `IosTextInputSession`.
public enum IosTextInputEvent: Sendable, Equatable {
    /// The backing UIKit text control became first responder.
    case focused
    /// The backing UIKit text control resigned first responder.
    case blurred
    /// Text content inside the backing UIKit control changed (typing, paste, dictation, IME commit).
    case textChanged
    /// Selected or marked text range inside the backing UIKit control changed.
    case selectionChanged
    /// The user triggered return/submit on a single-line text input control.
    case submit
}
