// Ported from: crates/rune/src/runtime/input/file_dialog.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native open/save file dialog request queue for host shells.

public struct FileDialogRequest: Sendable, Equatable {
    public var save: Bool
    public var directory: Bool
    public var multiple: Bool
    public var title: String?
    public var extensions: [String]

    public init(
        save: Bool = false,
        directory: Bool = false,
        multiple: Bool = false,
        title: String? = nil,
        extensions: [String] = []
    ) {
        self.save = save
        self.directory = directory
        self.multiple = multiple
        self.title = title
        self.extensions = extensions
    }
}

extension Runtime {
    public func takeFileDialogRequest() -> FileDialogRequest? {
        let out = pendingFileDialog
        pendingFileDialog = nil
        return out
    }
}
