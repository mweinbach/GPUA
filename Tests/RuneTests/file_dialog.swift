// Tests ported from: crates/rune/src/file_dialog.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func isVoidOk<E: Error>(_ result: Result<Void, E>) -> Bool {
    if case .success = result { return true }
    return false
}

@Suite
struct FileDialogTests {
    @Test
    func scriptedDialogsPreserveOrderUnicodePathsAndCancellation() async {
        let path = "/fixture/录音.wav"
        let dialogs = FileDialogs.scripted([
            ScriptedFileDialog(kind: .open, path: path),
            ScriptedFileDialog(kind: .save, path: nil),
            ScriptedFileDialog(kind: .folder, path: "/fixture/Projects"),
        ])
        let options = FileDialogOptions().filter("Audio", ["wav", "flac"])
        if case .success = await dialogs.save(options) {
            Issue.record("Expected Save before Open fixture to error")
        }
        #expect(await dialogs.open(options) == .success(path))
        let cloned = dialogs
        #expect(await cloned.save(options) == .success(nil))
        if case .success = await dialogs.open(options) {
            Issue.record("A folder fixture doesn't answer an Open")
        }
        #expect(await dialogs.openFolder(options) == .success("/fixture/Projects"))
        if case .success = await dialogs.open(options) {
            Issue.record("Expected exhausted fixture to error")
        }
    }

    struct ImportState {
        var answers: [FileDialogResult] = []
    }

    private func makeRuntime() -> Runtime<ImportState> {
        Runtime(ImportState(), { _, _ in el().key("import").size(80.0, 20.0) }, (200.0, 100.0), Env.new(true, 1.0))
    }

    private func askImport(_ rt: Runtime<ImportState>) {
        rt.hostUpdate { _, tx in
            let options = FileDialogOptions(title: "Import").filter("Export", ["json"])
            tx.openFile(options) { (s: inout ImportState, result, _) in
                s.answers.append(result)
            }
        }
    }

    @Test
    func aHandlersDialogWaitsOpenAndItsAnswerRunsOnALaterFrame() {
        let rt = makeRuntime()
        _ = rt.frame(0.0)
        askImport(rt)
        guard let (kind, options) = rt.hostFileDialog() else {
            Issue.record("Expected pending dialog")
            return
        }
        #expect(kind == .open)
        #expect(options.title == "Import")
        #expect(options.filters.count == 1 && options.filters[0].0 == "Export" && options.filters[0].1 == ["json"])
        let json = rt.hostFileDialogJson()
        #expect(json?["kind"] as? String == "open")
        #expect(json?["title"] as? String == "Import")

        _ = rt.hostFlushFileDialogAnswers()
        _ = rt.frame(2.0 / 60.0)
        #expect(rt.state.answers.isEmpty && rt.hostFileDialog() != nil)

        #expect(isVoidOk(rt.hostResolveFileDialog("/exports/录音.json")))
        #expect(rt.hostFileDialog() == nil && rt.state.answers.isEmpty)
        #expect(rt.hostHasPendingFileDialogAnswers())
        _ = rt.hostFlushFileDialogAnswers()
        _ = rt.frame(3.0 / 60.0)
        #expect(rt.state.answers == [.success("/exports/录音.json")])

        askImport(rt)
        #expect(isVoidOk(rt.hostResolveFileDialog(nil)))
        _ = rt.hostFlushFileDialogAnswers()
        _ = rt.frame(5.0 / 60.0)
        #expect(rt.state.answers[1] == .success(nil))
        if case .success = rt.hostResolveFileDialog(nil) {
            Issue.record("Expected resolving when nothing is open to fail")
        }
    }

    @Test
    func aFolderDialogWaitsOpenAsAFolderAndAnswersWithTheFolder() {
        let rt = makeRuntime()
        _ = rt.frame(0.0)
        rt.hostUpdate { _, tx in
            let options = FileDialogOptions(title: "Open Project", directory: "/work")
            tx.openFolder(options) { (s: inout ImportState, result, _) in
                s.answers.append(result)
            }
        }
        #expect(rt.hostFileDialog()?.0 == .folder)
        #expect(rt.hostFileDialog()?.1.title == "Open Project")
        let json = rt.hostFileDialogJson()
        #expect(json?["kind"] as? String == "folder")
        #expect(json?["directory"] as? String == "/work")
        #expect(isVoidOk(rt.hostResolveFileDialog("/work/notes")))
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers == [.success("/work/notes")])
    }

    @Test
    func aSecondDialogWhileOneIsOpenIsRefusedAndTheFirstStays() {
        let rt = makeRuntime()
        _ = rt.frame(0.0)
        askImport(rt)
        askImport(rt)
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers == [.failure(FileDialogError("a file dialog is already open"))])

        rt.hostUpdate { _, tx in
            tx.saveFile(FileDialogOptions()) { (s: inout ImportState, result, _) in
                s.answers.append(result)
            }
        }
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers.count == 2)
        #expect(rt.hostFileDialog()?.0 == .open)

        #expect(isVoidOk(rt.hostResolveFileDialog("a.json")))
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers[2] == .success("a.json"))

        rt.hostUpdate { _, tx in
            tx.saveFile(FileDialogOptions(fileName: "out.json")) { (s: inout ImportState, result, _) in
                s.answers.append(result)
            }
        }
        #expect(rt.hostFileDialog()?.0 == .save)
        #expect(rt.hostFileDialog()?.1.fileName == "out.json")
    }

    @Test
    func aHostShowsTheDialogOnceAndAnswersItById() {
        let rt = makeRuntime()
        _ = rt.frame(0.0)
        askImport(rt)
        guard let (id, kind, _) = rt.hostTakeFileDialog() else {
            Issue.record("Expected hostTakeFileDialog to return pending dialog")
            return
        }
        #expect(kind == .open)
        #expect(rt.hostTakeFileDialog() == nil)
        rt.hostAnswerFileDialog(id, .failure(FileDialogError("no portal")))
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers == [.failure(FileDialogError("no portal"))])

        askImport(rt)
        rt.hostRefuseFileDialog("unsupported")
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers[1] == .failure(FileDialogError("unsupported")))
    }

    @Test
    func anOverlayRefusesFileDialogs() {
        let rt = makeRuntime()
        fileDialogState(for: rt).isNativeOverlay = true
        _ = rt.frame(0.0)
        askImport(rt)
        #expect(rt.hostFileDialog() == nil)
        #expect(rt.hostHasPendingFileDialogAnswers())
        _ = rt.hostFlushFileDialogAnswers()
        #expect(rt.state.answers == [.failure(FileDialogError("overlays cannot open file dialogs"))])
    }

    @Test
    func closingOrHidingCancelsOpenAndQueuedFileDialogs() {
        let rt = makeRuntime()
        _ = rt.frame(0.0)
        rt.hostUpdate { _, tx in
            tx.openFile(FileDialogOptions()) { (s: inout ImportState, result, tx) in
                s.answers.append(result)
                tx.saveFile(FileDialogOptions()) { (s: inout ImportState, follow, _) in
                    s.answers.append(follow)
                }
            }
            tx.saveFile(FileDialogOptions()) { (s: inout ImportState, result, _) in
                s.answers.append(result)
            }
        }
        #expect(rt.hostFileDialog() != nil)
        rt.hostCancelFileDialogs()
        #expect(rt.hostFileDialog() == nil)
        #expect(
            rt.state.answers == [
                .failure(FileDialogError("a file dialog is already open")),
                .success(nil),
                .success(nil),
            ]
        )
    }
}
