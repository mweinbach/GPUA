// Ported from: crates/rune/src/file_dialog.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Inject native dialogs in the shell, scripted responses in headless fixtures.
//!
//! A handler can also ask with `Tx.openFile`, `Tx.saveFile` or `Tx.openFolder`: the window shows the
//! dialog once the handler's frame is done, and the answer runs the callback as an action on
//! a later frame. Headless runs keep the dialog open in `--tree` (`fileDialog`) until a
//! script's `{"type": "file-dialog", "path": ...}` or `{"type": "file-dialog-cancel"}` answers it.

#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers
#elseif !os(WASI)
import Foundation
#endif

public struct FileDialogOptions: Sendable, Equatable {
    public var title: String
    public var directory: String?
    public var fileName: String?
    public var filters: [(String, [String])]

    public init(
        title: String = "",
        directory: String? = nil,
        fileName: String? = nil,
        filters: [(String, [String])] = []
    ) {
        self.title = title
        self.directory = directory
        self.fileName = fileName
        self.filters = filters
    }

    public func filter(_ name: String, _ extensions: [String]) -> FileDialogOptions {
        var copy = self
        copy.filters.append((name, extensions))
        return copy
    }

    public static func == (lhs: FileDialogOptions, rhs: FileDialogOptions) -> Bool {
        guard lhs.title == rhs.title,
              lhs.directory == rhs.directory,
              lhs.fileName == rhs.fileName,
              lhs.filters.count == rhs.filters.count
        else {
            return false
        }
        for (a, b) in zip(lhs.filters, rhs.filters) {
            if a.0 != b.0 || a.1 != b.1 {
                return false
            }
        }
        return true
    }
}

/// Which dialog: Open picks an existing file, Save names a file to write, Folder picks an
/// existing folder (its options' filters and file name don't apply).
public enum FileDialogKind: Sendable, Equatable {
    case open
    case save
    case folder

    var name: String {
        switch self {
        case .open: return "open"
        case .save: return "save"
        case .folder: return "folder"
        }
    }
}

/// Expected request and its response. `nil` is cancellation, not a missing fixture.
public struct ScriptedFileDialog: Sendable, Equatable {
    public var kind: FileDialogKind
    public var path: String?

    public init(kind: FileDialogKind, path: String?) {
        self.kind = kind
        self.path = path
    }
}

public struct FileDialogError: Error, CustomStringConvertible, Sendable, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// What a `Tx.openFile`, `Tx.saveFile` or `Tx.openFolder` callback gets: the chosen path,
/// `.success(nil)` when the user cancels, or why no dialog could show.
public typealias FileDialogResult = Result<String?, FileDialogError>

// PORT NOTE: Access to `responses` is serialized via `LiveLock`, matching upstream `Arc<Mutex<VecDeque<ScriptedFileDialog>>>`.
private final class ScriptedDialogQueue: @unchecked Sendable {
    private let lock = LiveLock()
    private var responses: [ScriptedFileDialog]

    init(_ responses: [ScriptedFileDialog]) {
        self.responses = responses
    }

    func pop(_ kind: FileDialogKind) -> FileDialogResult {
        lock.withLock {
            guard let next = responses.first else {
                return .failure(FileDialogError("file dialog fixture exhausted"))
            }
            guard next.kind == kind else {
                return .failure(FileDialogError("expected \(next.kind) dialog, received \(kind)"))
            }
            responses.removeFirst()
            return .success(next.path)
        }
    }
}

public struct FileDialogs: Sendable {
    private enum Backend: Sendable {
        case native
        case scripted(ScriptedDialogQueue)
    }

    private let backend: Backend

    public static func native() -> FileDialogs {
        FileDialogs(backend: .native)
    }

    public static func scripted(_ responses: [ScriptedFileDialog]) -> FileDialogs {
        FileDialogs(backend: .scripted(ScriptedDialogQueue(responses)))
    }

    public func open(_ options: FileDialogOptions) async -> FileDialogResult {
        await show(.open, options)
    }

    public func save(_ options: FileDialogOptions) async -> FileDialogResult {
        await show(.save, options)
    }

    public func openFolder(_ options: FileDialogOptions) async -> FileDialogResult {
        await show(.folder, options)
    }

    private func show(_ kind: FileDialogKind, _ options: FileDialogOptions) async -> FileDialogResult {
        switch backend {
        case .scripted(let queue):
            _ = options
            return queue.pop(kind)
        case .native:
            return await showNativeFileDialog(kind, options)
        }
    }
}

#if os(macOS)
@MainActor
private func configureMacSavePanel(_ panel: NSSavePanel, _ kind: FileDialogKind, _ options: FileDialogOptions) {
    if !options.title.isEmpty {
        panel.title = options.title
        panel.message = options.title
    }
    if let dir = options.directory, !dir.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: dir)
    }
    if kind == .save, let name = options.fileName, !name.isEmpty {
        panel.nameFieldStringValue = name
    }
    if kind != .folder {
        let exts = options.filters.flatMap(\.1).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "*."))
        }.filter { !$0.isEmpty && $0 != "*" }
        if !exts.isEmpty {
            let types = exts.compactMap { UTType(filenameExtension: $0) }
            if !types.isEmpty {
                panel.allowedContentTypes = types
            }
        }
    }
}

@MainActor
func presentMacFileDialog(
    _ kind: FileDialogKind,
    _ options: FileDialogOptions,
    parentWindow: NSWindow?
) async -> FileDialogResult {
    switch kind {
    case .open, .folder:
        let panel = NSOpenPanel()
        panel.canChooseFiles = (kind == .open)
        panel.canChooseDirectories = (kind == .folder)
        panel.allowsMultipleSelection = false
        configureMacSavePanel(panel, kind, options)
        let response: NSApplication.ModalResponse
        if let parentWindow {
            response = await panel.beginSheetModal(for: parentWindow)
        } else {
            response = await withCheckedContinuation { cont in
                panel.begin { resp in cont.resume(returning: resp) }
            }
        }
        return .success(response == .OK ? panel.url?.path : nil)
    case .save:
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        configureMacSavePanel(panel, kind, options)
        let response: NSApplication.ModalResponse
        if let parentWindow {
            response = await panel.beginSheetModal(for: parentWindow)
        } else {
            response = await withCheckedContinuation { cont in
                panel.begin { resp in cont.resume(returning: resp) }
            }
        }
        return .success(response == .OK ? panel.url?.path : nil)
    }
}

private func showNativeFileDialog(_ kind: FileDialogKind, _ options: FileDialogOptions) async -> FileDialogResult {
    await presentMacFileDialog(kind, options, parentWindow: nil)
}
#elseif os(Linux)
private func showNativeFileDialog(_ kind: FileDialogKind, _ options: FileDialogOptions) async -> FileDialogResult {
    await showLinuxPortalFileDialog(kind, options)
}
#else
private func showNativeFileDialog(_ kind: FileDialogKind, _ options: FileDialogOptions) async -> FileDialogResult {
    _ = (kind, options)
    return .failure(FileDialogError("native file dialogs aren't supported on this platform"))
}
#endif

// MARK: - Tx & Runtime File Dialog Support

struct FileDialogCall {
    let kind: FileDialogKind
    let options: FileDialogOptions
    let onAnswer: (States, FileDialogResult, inout Tx) -> Void
}

/// Shared one-shot box for a `Tx`'s file dialog request; clones share the request and the runtime takes it once.
// PORT NOTE: Guarded by `LiveLock` so `Tx` clones remain value-safe and `take()` runs at most once.
final class FileDialogCallBox: @unchecked Sendable, CustomDebugStringConvertible {
    private let lock = LiveLock()
    private var request: FileDialogCall?

    init(_ request: FileDialogCall) {
        self.request = request
    }

    func take() -> FileDialogCall? {
        lock.withLock {
            let r = request
            request = nil
            return r
        }
    }

    var debugDescription: String {
        lock.withLock {
            if let r = request {
                return "FileDialogCall(\(r.kind), \(r.options))"
            }
            return "FileDialogCall(nil)"
        }
    }
}

/// The runtime's dialog, from the request until its answer is queued.
struct PendingFileDialog: Sendable, Equatable {
    var id: UInt64
    var kind: FileDialogKind
    var options: FileDialogOptions
    /// A host has it on screen.
    var shown: Bool

    func toJsonDictionary() -> [String: Any] {
        let filterList: [[String: Any]] = options.filters.map { name, ext in
            ["name": name, "extensions": ext]
        }
        var dict: [String: Any] = [
            "kind": kind.name,
            "title": options.title,
            "filters": filterList,
        ]
        if let dir = options.directory {
            dict["directory"] = dir
        }
        if let name = options.fileName {
            dict["fileName"] = name
        }
        return dict
    }
}

final class RuntimeFileDialogState {
    var nextId: UInt64 = 0
    var pending: (PendingFileDialog, (States, FileDialogResult, inout Tx) -> Void)? = nil
    var queuedAnswers: [(FileDialogResult, (States, FileDialogResult, inout Tx) -> Void)] = []
    var isNativeOverlay: Bool = false
}

func fileDialogState(for rt: AnyObject) -> RuntimeFileDialogState {
    let att = hostAttachment(for: rt)
    if let existing = att.customData["fileDialog"] as? RuntimeFileDialogState {
        return existing
    }
    let created = RuntimeFileDialogState()
    att.customData["fileDialog"] = created
    return created
}

extension Tx {
    /// Show an Open dialog once this handler's frame is done. `onAnswer` runs, as an action on
    /// a later frame, with the chosen file, `.success(nil)` when the user cancels (or the window
    /// hides or closes), or an error when no dialog could show.
    public mutating func openFile<S>(
        _ options: FileDialogOptions,
        _ onAnswer: @escaping (inout S, FileDialogResult, inout Tx) -> Void
    ) {
        enqueueFileDialog(.open, options, onAnswer)
    }

    /// `Tx.openFile` for a Save dialog: the path to write, which may not exist yet.
    public mutating func saveFile<S>(
        _ options: FileDialogOptions,
        _ onAnswer: @escaping (inout S, FileDialogResult, inout Tx) -> Void
    ) {
        enqueueFileDialog(.save, options, onAnswer)
    }

    /// `Tx.openFile` for a folder: an Open dialog that picks an existing folder.
    public mutating func openFolder<S>(
        _ options: FileDialogOptions,
        _ onAnswer: @escaping (inout S, FileDialogResult, inout Tx) -> Void
    ) {
        enqueueFileDialog(.folder, options, onAnswer)
    }

    private mutating func enqueueFileDialog<S>(
        _ kind: FileDialogKind,
        _ options: FileDialogOptions,
        _ onAnswer: @escaping (inout S, FileDialogResult, inout Tx) -> Void
    ) {
        let erased: (States, FileDialogResult, inout Tx) -> Void = { states, result, tx in
            _ = states.withMutable { (target: inout S) in
                onAnswer(&target, result, &tx)
            }
        }
        appendSidecar(FileDialogCallBox(FileDialogCall(kind: kind, options: options, onAnswer: erased)))
    }
}

extension Runtime {
    func hostLatchFileDialogs(_ tx: inout Tx) {
        let calls = tx.drainSidecar(as: FileDialogCallBox.self)
        guard !calls.isEmpty else { return }
        let fd = fileDialogState(for: self)
        let att = hostAttachment(for: self)
        for box in calls {
            guard let req = box.take() else { continue }
            if fd.isNativeOverlay {
                fd.queuedAnswers.append((.failure(FileDialogError("overlays cannot open file dialogs")), req.onAnswer))
                att.dirtyFromHost = true
            } else if fd.pending != nil {
                fd.queuedAnswers.append((.failure(FileDialogError("a file dialog is already open")), req.onAnswer))
                att.dirtyFromHost = true
            } else {
                fd.nextId += 1
                let pending = PendingFileDialog(id: fd.nextId, kind: req.kind, options: req.options, shown: false)
                fd.pending = (pending, req.onAnswer)
            }
        }
    }

    /// Runs any queued file-dialog answers against `state` and latches follow-up `Tx` requests.
    @discardableResult
    func hostFlushFileDialogAnswers() -> Bool {
        let fd = fileDialogState(for: self)
        guard !fd.queuedAnswers.isEmpty else { return false }
        let batch = fd.queuedAnswers
        fd.queuedAnswers.removeAll()
        for (result, cb) in batch {
            var tx = hostNewTx()
            hostWithStates { states in
                cb(states, result, &tx)
            }
            hostLatchTx(&tx)
        }
        hostAttachment(for: self).dirtyFromHost = true
        return true
    }

    func hostFileDialog() -> (FileDialogKind, FileDialogOptions)? {
        guard let (pending, _) = fileDialogState(for: self).pending else { return nil }
        return (pending.kind, pending.options)
    }

    func hostFileDialogJson() -> [String: Any]? {
        fileDialogState(for: self).pending?.0.toJsonDictionary()
    }

    func hostHasPendingFileDialogAnswers() -> Bool {
        !fileDialogState(for: self).queuedAnswers.isEmpty
    }

    func hostTakeFileDialog() -> (UInt64, FileDialogKind, FileDialogOptions)? {
        let fd = fileDialogState(for: self)
        guard let (existingPending, cb) = fd.pending, !existingPending.shown else { return nil }
        var pending = existingPending
        pending.shown = true
        fd.pending = (pending, cb)
        return (pending.id, pending.kind, pending.options)
    }

    func hostAnswerFileDialog(_ id: UInt64, _ result: FileDialogResult) {
        let fd = fileDialogState(for: self)
        guard let (pending, cb) = fd.pending, pending.id == id else { return }
        fd.pending = nil
        fd.queuedAnswers.append((result, cb))
        hostAttachment(for: self).dirtyFromHost = true
    }

    func hostRefuseFileDialog(_ reason: String) {
        let fd = fileDialogState(for: self)
        guard let (_, cb) = fd.pending else { return }
        fd.pending = nil
        fd.queuedAnswers.append((.failure(FileDialogError(reason)), cb))
        hostAttachment(for: self).dirtyFromHost = true
    }

    @discardableResult
    func hostResolveFileDialog(_ path: String?) -> Result<Void, FileDialogError> {
        let fd = fileDialogState(for: self)
        guard let (pending, _) = fd.pending else {
            return .failure(FileDialogError("no file dialog is open"))
        }
        hostAnswerFileDialog(pending.id, .success(path))
        return .success(())
    }

    /// Cancels open and queued file dialogs immediately while the state is still alive.
    func hostCancelFileDialogs() {
        let fd = fileDialogState(for: self)
        while !fd.queuedAnswers.isEmpty || fd.pending != nil {
            if !fd.queuedAnswers.isEmpty {
                _ = hostFlushFileDialogAnswers()
            }
            if let (pending, cb) = fd.pending {
                _ = pending
                fd.pending = nil
                fd.queuedAnswers.append((.success(nil), cb))
                _ = hostFlushFileDialogAnswers()
            }
        }
    }
}
