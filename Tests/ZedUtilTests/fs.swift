// Swift-only: Behavioral unit tests for ZedUtil filesystem utilities

import Testing
import Foundation
@testable import ZedUtil

@Suite("Filesystem Utilities Tests")
struct FSTests {
    @Test
    func test_remove_matching_and_collect_matching() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_test_\(UUID().uuidString)")
        try createDirectories(at: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("match_1.txt")
        let fileB = tempDir.appendingPathComponent("ignore_2.log")
        let subDir = tempDir.appendingPathComponent("match_dir")
        let fileInsideSub = subDir.appendingPathComponent("child.txt")

        try "Hello".write(to: fileA, atomically: true, encoding: .utf8)
        try "World".write(to: fileB, atomically: true, encoding: .utf8)
        try createDirectories(at: subDir)
        try "Child".write(to: fileInsideSub, atomically: true, encoding: .utf8)

        let collected = await collectMatching(in: tempDir.path) { path in
            path.contains("match")
        }
        #expect(collected.count == 2)
        #expect(collected.contains(fileA.path))
        #expect(collected.contains(subDir.path))

        await removeMatching(in: tempDir.path) { path in
            path.contains("match")
        }

        #expect(!FileManager.default.fileExists(atPath: fileA.path))
        #expect(!FileManager.default.fileExists(atPath: subDir.path))
        #expect(FileManager.default.fileExists(atPath: fileB.path))
    }

    @Test
    func test_find_file_name_in_dir() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_find_\(UUID().uuidString)")
        try createDirectories(at: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetFile = tempDir.appendingPathComponent("special_config.json")
        try "{}".write(to: targetFile, atomically: true, encoding: .utf8)

        let found = await findFileNameInDir(in: tempDir.path) { name in
            name.hasPrefix("special_") && name.hasSuffix(".json")
        }
        #expect(found == targetFile.path)

        let notFound = await findFileNameInDir(in: tempDir.path) { name in
            name == "nonexistent"
        }
        #expect(notFound == nil)
    }

    @Test
    func test_move_folder_files_to_folder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_move_\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        let dst = root.appendingPathComponent("dst")

        try createDirectories(at: src)
        try createDirectories(at: dst)
        defer { try? FileManager.default.removeItem(at: root) }

        let file1 = src.appendingPathComponent("item1.txt")
        let file2 = src.appendingPathComponent("item2.txt")
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)

        try await moveFolderFilesToFolder(sourcePath: src.path, targetPath: dst.path)

        // Source folder should be removed
        #expect(!FileManager.default.fileExists(atPath: src.path))

        // Files should now exist in dst
        let moved1 = dst.appendingPathComponent("item1.txt")
        let moved2 = dst.appendingPathComponent("item2.txt")
        #expect(FileManager.default.fileExists(atPath: moved1.path))
        #expect(FileManager.default.fileExists(atPath: moved2.path))
        let content1 = try String(contentsOf: moved1, encoding: .utf8)
        #expect(content1 == "Content 1")
    }

    @Test
    func test_move_folder_files_target_not_dir_fails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_move_err_\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        let dstFile = root.appendingPathComponent("file.txt")

        try createDirectories(at: src)
        try "not a dir".write(to: dstFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: FSError.notADirectory(dstFile.path)) {
            try await moveFolderFilesToFolder(sourcePath: src.path, targetPath: dstFile.path)
        }
    }

    @Test
    func test_atomic_write_and_permissions() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs_perm_\(UUID().uuidString)")
        try createDirectories(at: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scriptFile = tempDir.appendingPathComponent("script.sh")
        let data = Data("#!/bin/sh\necho test\n".utf8)
        try atomicWrite(data: data, to: scriptFile.path)

        #expect(FileManager.default.fileExists(atPath: scriptFile.path))
        let readData = try Data(contentsOf: scriptFile)
        #expect(readData == data)

        try await makeFileExecutable(at: scriptFile.path)

        #if !os(Windows)
        let attrs = try FileManager.default.attributesOfItem(atPath: scriptFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((perms & 0o777) == 0o755)
        #endif
    }
}
