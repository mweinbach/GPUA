// Tests ported from: crates/rune-mac/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import CoreGraphics
import Darwin
import Foundation
import Testing
@testable import RuneMac

@Test
func saved_size_and_frame_clamp_geometry() {
    let uniqueName = "RuneMacTestWindow_\(UUID().uuidString)"
    let defaultsKey = "NSWindow Frame \(uniqueName)"
    UserDefaults.standard.set("2200 -50 900 640 0 0 1728 1117", forKey: defaultsKey)
    defer {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    let sz = savedSize(uniqueName)
    #expect(sz?.0 == 900.0)
    #expect(sz?.1 == 640.0)

    let frame = savedFrame(uniqueName)
    #expect(frame != nil)
    if let frame {
        let clamped = frame.clamped(to: CGRect(x: 0, y: 0, width: 1728, height: 1084))
        #expect(clamped == CGRect(x: 828, y: 0, width: 900, height: 640))
    }

    // Invalid sub-pixel dimensions are rejected.
    #expect(parseSize("0 0 0.5 100") == nil)
}

@Test
func quiet_launch_is_noop_without_env_var() {
    unsetenv("MAC_APP_QUIET")
    launch()
    #expect(getenv("MAC_APP_QUIET") == nil)
}
#endif
