// Tests ported from: crates/rune/src/file_dialog/portal.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct FileDialogPortalTests {
    @Test
    func replyUrisAreReadFromTheResultsMap() {
        let list = ["file:///tmp/a%20b", "file:///tmp/c"]
        let results: [String: PortalVariant] = ["uris": .stringArray(list)]
        #expect(fileDialogPortalUris(results) == list)
        #expect(fileDialogPortalOutcome(0, fileDialogPortalUris(results)) == .success("/tmp/a b"))
        #expect(fileDialogPortalUris([:]).isEmpty)
        let mistyped: [String: PortalVariant] = ["uris": .uint32(7)]
        #expect(fileDialogPortalUris(mistyped).isEmpty)
    }

    @Test
    func optionsCarryTokenFiltersFolderAndSaveName() {
        let options = FileDialogOptions(
            title: "Import",
            directory: "/home/a/Downloads",
            fileName: "export.csv"
        ).filter("Exports", ["csv"])

        let open = fileDialogPortalRequestOptions(.open, options, "t1")
        #expect(open["handle_token"] == .string("t1"))
        #expect(open["filters"] == .filters([PortalFilter("Exports", [PortalFilterPattern(0, "*.csv")])]))
        #expect(open["current_folder"] == .bytes(Array("/home/a/Downloads".utf8) + [0]))
        #expect(open["current_name"] == nil)
        #expect(open["directory"] == nil)

        let folder = fileDialogPortalRequestOptions(.folder, options, "t4")
        #expect(folder["directory"] == .bool(true))
        #expect(folder["filters"] == nil)
        #expect(folder["current_folder"] == .bytes(Array("/home/a/Downloads".utf8) + [0]))

        let save = fileDialogPortalRequestOptions(.save, options, "t2")
        #expect(save["current_name"] == .string("export.csv"))

        let empty = FileDialogOptions(directory: "", fileName: "").filter("Empty", [])
        let emptySave = fileDialogPortalRequestOptions(.save, empty, "t3")
        #expect(emptySave["filters"] == nil)
        #expect(emptySave["current_folder"] == nil)
        #expect(emptySave["current_name"] == nil)
    }

    @Test
    func missingPortalIsAClearError() {
        #expect(fileDialogPortalMapDbusError(.serviceUnknown("portal")) == fileDialogPortalUnavailable())
        #expect(fileDialogPortalMapDbusError(.unknownMethod("OpenFile")) == fileDialogPortalUnavailable())
        #expect(fileDialogPortalMapDbusError(.spawnChildExited("portal")) == fileDialogPortalUnavailable())
        #expect(fileDialogPortalMapDbusError(.failed("x")) != fileDialogPortalUnavailable())
    }
}
