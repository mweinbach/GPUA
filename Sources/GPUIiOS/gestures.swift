// Ported from: crates/gpui_ios/src/gestures.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import UIKit

// MARK: - Simultaneous Gesture Recognizer Delegate

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIGestureDelegate")` with a native
// Swift `NSObject` subclass conforming to `UIGestureRecognizerDelegate` (ADR-0011).

/// Delegate allowing pinch, rotation, long-press, hover, and scroll-pan gestures on `GPUIView`
/// to recognize simultaneously, while preventing the single-finger and two-finger pan
/// recognizers from firing at the same time.
@MainActor
final class GPUIGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    override init() {
        super.init()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Prevent single-finger pan and two-finger trackpad/scroll pan from recognizing
        // simultaneously and emitting duplicate scroll deltas.
        if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return true
    }
}
#endif
