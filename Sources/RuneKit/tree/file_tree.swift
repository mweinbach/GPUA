// Ported from: crates/rune-kit/src/tree/file_tree.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune

/// A node of a file tree: a folder (`dir`) or a file carrying the app's data.
public struct FileNode<D> {
    /// What the row shows: the file or folder name, or `a/b/c` for folders compacted into one.
    public var name: String
    /// The path from the root, which is also the node's id.
    public var path: String
    public var dir: Bool
    /// The file's data; `nil` for folders.
    public var data: D?

    public init(name: String, path: String, dir: Bool, data: D?) {
        self.name = name
        self.path = path
        self.dir = dir
        self.data = data
    }

    public func label() -> String {
        name
    }

    /// Function-value helper matching Rust's `FileNode::label` in `Tree.new(..., FileNode.label)`.
    public static func label(_ node: FileNode<D>) -> String {
        node.name
    }

    /// The folder or file icon for this node (``fileIcon(_:)``).
    public func icon(_ open: Bool) -> Icon {
        if dir {
            return open ? glyphs.FOLDER_OPEN : glyphs.FOLDER
        }
        return fileIcon(name)
    }
}

extension FileNode: Equatable where D: Equatable {}
extension FileNode: Sendable where D: Sendable {}

/// An icon for a file by its extension: code, text and docs, images, or a plain page.
public func fileIcon(_ name: String) -> Icon {
    let ext: String
    if let dot = name.lastIndex(of: ".") {
        ext = asciiLowercased(name[name.index(after: dot)...])
    } else {
        ext = ""
    }
    switch ext {
    case "rs", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "swift", "c", "h", "cc",
         "cpp", "hpp", "m", "mm", "java", "kt", "rb", "php", "cs", "zig", "lua", "sh", "bash",
         "zsh", "fish", "wgsl", "glsl", "metal", "html", "css", "scss", "vue", "svelte", "sql",
         "ex", "exs", "hs", "ml", "scala", "dart":
        return glyphs.FILE_CODE
    case "md", "mdx", "txt", "rst", "adoc", "json", "jsonc", "toml", "yaml", "yml", "lock",
         "xml", "csv", "ini", "cfg", "conf", "env":
        return glyphs.FILE_TEXT
    case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "bmp", "tiff", "avif", "heic":
        return glyphs.FILE_IMAGE
    default:
        return glyphs.FILE
    }
}

private func asciiLowercased(_ s: Substring) -> String {
    var out = ""
    out.reserveCapacity(s.utf8.count)
    for scalar in s.unicodeScalars {
        if scalar.value >= 0x41 && scalar.value <= 0x5A,
           let lower = UnicodeScalar(scalar.value + 32)
        {
            out.unicodeScalars.append(lower)
        } else {
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}

// A trie of folders; files hang off their folder.
private final class DirNode<Payload> {
    var dirs: [(String, DirNode<Payload>)] = []
    var files: [(String, Payload)] = []

    func dir(_ name: String) -> DirNode<Payload> {
        if let idx = dirs.firstIndex(where: { $0.0 == name }) {
            return dirs[idx].1
        }
        let child = DirNode<Payload>()
        dirs.append((name, child))
        return child
    }
}

/// Builds a ``TreeModel`` of ``FileNode``s from file paths (`/`-separated, relative to a root).
///
/// By default folders sort before files, names sort naturally (`file2` before `file10`, case
/// aside), and a chain of folders that each hold only one folder shows as one row named
/// `a/b/c`, as an editor's compact folders do. Folders start closed; open them on the model.
public struct FileTree: Sendable, Equatable {
    private var compact: Bool
    private var dirsFirstFlag: Bool
    private var keyName: String

    public init() {
        self.compact = true
        self.dirsFirstFlag = true
        self.keyName = "files"
    }

    public static func new() -> FileTree {
        FileTree()
    }

    public static let `default` = FileTree()

    /// Show a chain of single-folder folders as one `a/b/c` row (on by default).
    public func compactFolders(_ on: Bool) -> FileTree {
        var copy = self
        copy.compact = on
        return copy
    }

    /// Sort folders before files (on by default); off, they mix by name.
    public func dirsFirst(_ on: Bool) -> FileTree {
        var copy = self
        copy.dirsFirstFlag = on
        return copy
    }

    /// The model's row-key prefix (``TreeModel/key(_:)``, `"files"` here).
    public func key(_ key: String) -> FileTree {
        var copy = self
        copy.keyName = key
        return copy
    }

    public func build<P: StringProtocol, D, Seq: Swift.Sequence>(
        _ files: Seq
    ) -> TreeModel<FileNode<D>> where Seq.Element == (P, D) {
        let root = DirNode<D>()
        for (rawPath, data) in files {
            var parts = rawPath.split(separator: "/", omittingEmptySubsequences: true)
            if parts.isEmpty {
                continue
            }
            let file = String(parts.removeLast())
            var dir = root
            for part in parts {
                dir = dir.dir(String(part))
            }
            dir.files.append((file, data))
        }

        var model = TreeModel<FileNode<D>>.new().key(keyName)

        func joinPath(_ a: String, _ b: String) -> String {
            a.isEmpty ? b : "\(a)/\(b)"
        }

        func emit(
            _ model: inout TreeModel<FileNode<D>>,
            compact: Bool,
            parent: String?,
            prefix: String,
            dir: DirNode<D>
        ) {
            for (rawName, startDir) in dir.dirs {
                var name = rawName
                var path = joinPath(prefix, name)
                var d = startDir
                while compact && d.files.isEmpty && d.dirs.count == 1 {
                    let (n, inner) = d.dirs.removeLast()
                    name = "\(name)/\(n)"
                    path = joinPath(path, n)
                    d = inner
                }
                model.insert(parent, path, FileNode(name: name, path: path, dir: true, data: nil))
                emit(&model, compact: compact, parent: path, prefix: path, dir: d)
            }
            for (name, data) in dir.files {
                let path = joinPath(prefix, name)
                // A file sharing a folder's path (`a` and `a/b`) is left out.
                model.insert(parent, path, FileNode(name: name, path: path, dir: false, data: data))
            }
        }

        emit(&model, compact: compact, parent: nil, prefix: "", dir: root)
        let dirsFirst = dirsFirstFlag
        model.sortBy { a, b in
            let byKind: Ordering = dirsFirst ? Ordering.compare(b.dir ? 1 : 0, a.dir ? 1 : 0) : .equal
            return byKind.thenWith { naturalCmp(a.name, b.name) }
        }
        return model
    }
}

/// Compares names as people sort them: case aside, and runs of digits by value (`file2` before
/// `file10`). Ties fall back to the exact text so the order is total.
public func naturalCmp(_ a: String, _ b: String) -> Ordering {
    let xScalars = Array(a.unicodeScalars)
    let yScalars = Array(b.unicodeScalars)
    var xi = 0
    var yi = 0

    while true {
        let p = xi < xScalars.count ? xScalars[xi] : nil
        let q = yi < yScalars.count ? yScalars[yi] : nil

        switch (p, q) {
        case (nil, nil):
            return utf8Cmp(a.utf8, b.utf8)
        case (nil, .some):
            return .less
        case (.some, nil):
            return .greater
        case (.some(let ps), .some(let qs)) where isAsciiDigit(ps) && isAsciiDigit(qs):
            let mStart = xi
            while xi < xScalars.count && isAsciiDigit(xScalars[xi]) {
                xi += 1
            }
            let nStart = yi
            while yi < yScalars.count && isAsciiDigit(yScalars[yi]) {
                yi += 1
            }
            var mTrim = mStart
            while mTrim < xi && xScalars[mTrim].value == 0x30 {
                mTrim += 1
            }
            var nTrim = nStart
            while nTrim < yi && yScalars[nTrim].value == 0x30 {
                nTrim += 1
            }
            let mLen = xi - mTrim
            let nLen = yi - nTrim
            let byDigits = Ordering.compare(mLen, nLen).thenWith {
                for offset in 0..<mLen {
                    let lv = xScalars[mTrim + offset].value
                    let rv = yScalars[nTrim + offset].value
                    if lv != rv {
                        return lv < rv ? .less : .greater
                    }
                }
                return .equal
            }
            if byDigits != .equal {
                return byDigits
            }
        case (.some(let ps), .some(let qs)):
            let pl = String(ps).lowercased().utf8
            let ql = String(qs).lowercased().utf8
            let o = utf8Cmp(pl, ql)
            if o != .equal {
                return o
            }
            xi += 1
            yi += 1
        }
    }
}

private func isAsciiDigit(_ s: UnicodeScalar) -> Bool {
    s.value >= 0x30 && s.value <= 0x39
}

private func utf8Cmp(_ a: String.UTF8View, _ b: String.UTF8View) -> Ordering {
    var ai = a.startIndex
    var bi = b.startIndex
    while ai < a.endIndex && bi < b.endIndex {
        let av = a[ai]
        let bv = b[bi]
        if av != bv {
            return av < bv ? .less : .greater
        }
        a.formIndex(after: &ai)
        b.formIndex(after: &bi)
    }
    if ai == a.endIndex && bi == b.endIndex {
        return .equal
    }
    return ai == a.endIndex ? .less : .greater
}
