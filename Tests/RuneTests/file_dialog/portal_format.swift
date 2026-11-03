// Tests ported from: crates/rune/src/file_dialog/portal_format.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct FileDialogPortalFormatTests {
    @Test
    func chosenUrisBecomePercentDecodedPaths() {
        #expect(
            fileDialogPortalOutcome(0, ["file:///home/a/My%20Export%20%E5%BD%95.csv"])
                == .success("/home/a/My Export 录.csv")
        )
        #expect(
            fileDialogPortalOutcome(0, ["file://localhost/tmp/a%2fb", "file:///tmp/second"])
                == .success("/tmp/a/b")
        )
        #expect(
            fileDialogPortalOutcome(0, ["file://LOCALHOST/tmp/a"])
                == .success("/tmp/a")
        )
        #expect(fileDialogPortalOutcome(0, []) == .success(nil))

        // Malformed or truncated escapes stay literal.
        #expect(fileDialogPortalUriPath("file:///tmp/100%") == .success("/tmp/100%"))
        #expect(fileDialogPortalUriPath("file:///tmp/1%2") == .success("/tmp/1%2"))
        #expect(fileDialogPortalUriPath("file:///tmp/%zz") == .success("/tmp/%zz"))

        // Non-UTF-8 names survive as raw bytes.
        #expect(
            fileDialogPortalUriPathBytes("file:///tmp/%FF")
                == .success(Array("/tmp/".utf8) + [0xFF])
        )
        if case .success = fileDialogPortalUriPath("file://server/share/a") {
            Issue.record("Expected non-local authority to fail")
        }
        if case .success = fileDialogPortalUriPath("https://example.com/a") {
            Issue.record("Expected https URI to fail")
        }
    }

    @Test
    func cancelledOrEndedDialogIsNoChoice() {
        #expect(fileDialogPortalOutcome(1, ["file:///tmp/a"]) == .success(nil))
        #expect(fileDialogPortalOutcome(2, []) == .success(nil))
        if case .success = fileDialogPortalOutcome(3, []) {
            Issue.record("Expected portal status 3 to return an error")
        }
    }

    @Test
    func filtersFoldersAndParentsUsePortalFormats() {
        let options = FileDialogOptions()
            .filter("Exports", ["csv", ".json", "*.txt"])
            .filter("Empty", [])
            .filter("", ["wav"])
            .filter("All files", ["*"])
        #expect(
            fileDialogPortalFilters(options) == [
                PortalFilter("Exports", [
                    PortalFilterPattern(0, "*.csv"),
                    PortalFilterPattern(0, "*.json"),
                    PortalFilterPattern(0, "*.txt"),
                ]),
                PortalFilter("*.wav", [PortalFilterPattern(0, "*.wav")]),
                PortalFilter("All files", [PortalFilterPattern(0, "*")]),
            ]
        )
        #expect(
            fileDialogPortalPathBytes("/home/a/Downloads")
                == Array("/home/a/Downloads".utf8) + [0]
        )
        #expect(fileDialogPortalPathBytes("") == nil)
        #expect(fileDialogPortalPathBytes("/tmp/a\0b") == nil)
        #expect(fileDialogParentWindow(0) == "")
        #expect(fileDialogParentWindow(0x3a0000f) == "x11:3a0000f")
    }
}
