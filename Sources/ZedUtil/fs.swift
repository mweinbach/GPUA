// Ported from: crates/util/src/fs.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public enum FSError: LocalizedError, Sendable, Equatable {
    case notADirectory(String)
    case directoryNotFound(String)
    case fileNotFound(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "Path is not a directory: \(path)"
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .ioError(let msg):
            return msg
        }
    }
}

/// Removes all files and directories directly under the given directory matching the predicate.
public func removeMatching(
    in dir: String,
    predicate: @Sendable (String) -> Bool
) async {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else {
        return
    }

    for entry in entries {
        let entryPath = (dir as NSString).appendingPathComponent(entry)
        if predicate(entryPath) {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: entryPath, isDirectory: &isDir) {
                try? fileManager.removeItem(atPath: entryPath)
            }
        }
    }
}

/// URL overload for removeMatching.
public func removeMatching(
    in dir: URL,
    predicate: @Sendable (URL) -> Bool
) async {
    await removeMatching(in: dir.path) { path in
        predicate(URL(fileURLWithPath: path))
    }
}

/// Collects all paths directly under the given directory matching the predicate.
public func collectMatching(
    in dir: String,
    predicate: @Sendable (String) -> Bool
) async -> [String] {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else {
        return []
    }

    var matching: [String] = []
    for entry in entries {
        let entryPath = (dir as NSString).appendingPathComponent(entry)
        if predicate(entryPath) {
            matching.pushOrAppend(entryPath)
        }
    }
    return matching
}

/// URL overload for collectMatching.
public func collectMatching(
    in dir: URL,
    predicate: @Sendable (URL) -> Bool
) async -> [URL] {
    let paths = await collectMatching(in: dir.path) { path in
        predicate(URL(fileURLWithPath: path))
    }
    return paths.map { URL(fileURLWithPath: $0) }
}

/// Finds the first filename directly under the given directory matching the predicate.
public func findFileNameInDir(
    in dir: String,
    predicate: @Sendable (String) -> Bool
) async -> String? {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else {
        return nil
    }

    for entry in entries {
        let entryPath = (dir as NSString).appendingPathComponent(entry)
        let fileName = (entryPath as NSString).lastPathComponent
        if predicate(fileName) {
            return entryPath
        }
    }
    return nil
}

/// URL overload for findFileNameInDir.
public func findFileNameInDir(
    in dir: URL,
    predicate: @Sendable (String) -> Bool
) async -> URL? {
    if let found = await findFileNameInDir(in: dir.path, predicate: predicate) {
        return URL(fileURLWithPath: found)
    }
    return nil
}

/// Moves all files and subdirectories from source folder into target folder, then removes source folder.
public func moveFolderFilesToFolder(
    sourcePath: String,
    targetPath: String
) async throws {
    let fileManager = FileManager.default
    var isDir: ObjCBool = false
    guard fileManager.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue else {
        throw FSError.notADirectory(targetPath)
    }

    let entries = try fileManager.contentsOfDirectory(atPath: sourcePath)
    for entry in entries {
        let oldPath = (sourcePath as NSString).appendingPathComponent(entry)
        let newPath = (targetPath as NSString).appendingPathComponent(entry)
        try fileManager.moveItem(atPath: oldPath, toPath: newPath)
    }

    try fileManager.removeItem(atPath: sourcePath)
}

/// URL overload for moveFolderFilesToFolder.
public func moveFolderFilesToFolder(
    sourceURL: URL,
    targetURL: URL
) async throws {
    try await moveFolderFilesToFolder(sourcePath: sourceURL.path, targetPath: targetURL.path)
}

/// Sets the permissions for the given path so that the file becomes executable (0o755).
/// This is a no-op on Windows.
public func makeFileExecutable(at path: String) async throws {
    #if !os(Windows)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    #endif
}

/// URL overload for makeFileExecutable.
public func makeFileExecutable(at url: URL) async throws {
    try await makeFileExecutable(at: url.path)
}

/// Synchronous makeFileExecutable for non-async callers.
public func makeFileExecutableSync(at path: String) throws {
    #if !os(Windows)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    #endif
}

/// Helper: creates intermediate directories if needed.
public func createDirectories(at path: String) throws {
    try FileManager.default.createDirectory(
        atPath: path,
        withIntermediateDirectories: true,
        attributes: nil
    )
}

/// Helper: creates intermediate directories if needed.
public func createDirectories(at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: nil
    )
}

/// Helper: atomic file write via temporary file and atomic rename.
public func atomicWrite(data: Data, to destinationPath: String) throws {
    let destinationURL = URL(fileURLWithPath: destinationPath)
    try data.write(to: destinationURL, options: .atomic)
}

/// Helper: atomic file write via URL.
public func atomicWrite(data: Data, to destinationURL: URL) throws {
    try data.write(to: destinationURL, options: .atomic)
}

/// Helper: set POSIX permissions if on Unix.
public func setFilePermissions(at path: String, mode: Int) throws {
    #if !os(Windows)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    #endif
}

private extension Array {
    mutating func pushOrAppend(_ element: Element) {
        append(element)
    }
}
