// Tests ported from: crates/rune-mac/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import RuneMac

@Test
func parses_appkits_frame_string() {
    let parsed = parseSize("1645 0 716 1084 0 0 1728 1084 ")
    #expect(parsed?.0 == 716.0)
    #expect(parsed?.1 == 1084.0)
    #expect(parseSize("12 30") == nil)
    #expect(parseSize("") == nil)
}

@Test
func busy_holds_a_marker_named_for_this_process() {
    let originalHome = getenv("HOME").map { String(cString: $0) }
    let tempHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("rune-mac-busy-\(getpid())-\(UUID().uuidString)", isDirectory: true)
    setenv("HOME", tempHome.path, 1)
    defer {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        } else {
            unsetenv("HOME")
        }
        try? FileManager.default.removeItem(at: tempHome)
    }

    let marker = tempHome
        .appendingPathComponent("Library/Caches/mac-app/busy", isDirectory: true)
        .appendingPathComponent(String(getpid()), isDirectory: false)

    busy(true)
    #expect(FileManager.default.fileExists(atPath: marker.path))
    busy(false)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}
#endif
