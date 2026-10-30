// Tests ported from: crates/util/src/archive.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import ZedUtil

@Suite("Archive & ZIP Utilities Tests")
struct ArchiveTests {
    private func makeTestData() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_test_data_\(UUID().uuidString)")
        try createDirectories(at: tempDir)

        let testFile = tempDir.appendingPathComponent("test")
        try "Hello world.".write(to: testFile, atomically: true, encoding: .utf8)

        let fooBarDir = tempDir.appendingPathComponent("foo/bar")
        try createDirectories(at: fooBarDir)

        let fooBarTxt = tempDir.appendingPathComponent("foo/bar.txt")
        try "Foo bar.".write(to: fooBarTxt, atomically: true, encoding: .utf8)

        let fooDarMd = tempDir.appendingPathComponent("foo/dar.md")
        try "Bar dar.".write(to: fooDarMd, atomically: true, encoding: .utf8)

        let utf8File = tempDir.appendingPathComponent("foo/bar/dar你好.txt")
        try "你好世界".write(to: utf8File, atomically: true, encoding: .utf8)

        return tempDir
    }

    private func assertFileContent(_ url: URL, _ expected: String) throws {
        #expect(FileManager.default.fileExists(atPath: url.path))
        let actual = try String(contentsOf: url, encoding: .utf8)
        #expect(actual == expected)
    }

    @Test
    func test_extract_zip() async throws {
        let testDir = try makeTestData()
        let zipFile = testDir.appendingPathComponent("test.zip")
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_extract_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: testDir)
            try? FileManager.default.removeItem(at: extractDir)
        }

        try await compressZip(sourceDir: testDir, destinationZip: zipFile, keepFilePermissions: true)
        try await extractZip(destination: extractDir, archiveURL: zipFile)

        try assertFileContent(extractDir.appendingPathComponent("test"), "Hello world.")
        try assertFileContent(extractDir.appendingPathComponent("foo/bar.txt"), "Foo bar.")
        try assertFileContent(extractDir.appendingPathComponent("foo/dar.md"), "Bar dar.")
        try assertFileContent(extractDir.appendingPathComponent("foo/bar/dar你好.txt"), "你好世界")
    }

    @Test
    func test_extract_zip_preserves_executable_permissions() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_perm_\(UUID().uuidString)")
        try createDirectories(at: testDir)
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_perm_out_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: testDir)
            try? FileManager.default.removeItem(at: extractDir)
        }

        let scriptFile = testDir.appendingPathComponent("my_script")
        try "#!/bin/bash\necho 'Hello'".write(to: scriptFile, atomically: true, encoding: .utf8)

        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        #endif

        let zipFile = testDir.appendingPathComponent("test.zip")
        try await compressZip(sourceDir: testDir, destinationZip: zipFile, keepFilePermissions: true)
        try await extractZip(destination: extractDir, archiveURL: zipFile)

        let extractedScript = extractDir.appendingPathComponent("my_script")
        #expect(FileManager.default.fileExists(atPath: extractedScript.path))

        #if !os(Windows)
        let attrs = try FileManager.default.attributesOfItem(atPath: extractedScript.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((perms & 0o777) == 0o755)
        #endif
    }

    @Test
    func test_extract_zip_sets_default_permissions() async throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_default_perm_\(UUID().uuidString)")
        try createDirectories(at: testDir)
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive_default_out_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: testDir)
            try? FileManager.default.removeItem(at: extractDir)
        }

        let scriptFile = testDir.appendingPathComponent("my_script")
        try "#!/bin/bash\necho 'Hello'".write(to: scriptFile, atomically: true, encoding: .utf8)

        #if !os(Windows)
        let originalAttrs = try FileManager.default.attributesOfItem(atPath: scriptFile.path)
        let originalPerms = (originalAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #endif

        let zipFile = testDir.appendingPathComponent("test.zip")
        try await compressZip(sourceDir: testDir, destinationZip: zipFile, keepFilePermissions: false)
        try await extractZip(destination: extractDir, archiveURL: zipFile)

        let extractedScript = extractDir.appendingPathComponent("my_script")
        #expect(FileManager.default.fileExists(atPath: extractedScript.path))

        #if !os(Windows)
        let extractedAttrs = try FileManager.default.attributesOfItem(atPath: extractedScript.path)
        let extractedPerms = (extractedAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((extractedPerms & 0o777) == (originalPerms & 0o777))
        #endif
    }

    @Test
    func test_deflate_stored_block() throws {
        let inputString = "DEFLATE stored block test string 1234567890."
        let inputBytes = [UInt8](inputString.utf8)

        var compressed = [UInt8]()
        compressed.append(0x01) // BFINAL=1, BTYPE=00
        let len = UInt16(inputBytes.count)
        let nlen = ~len
        compressed.append(UInt8(len & 0xFF))
        compressed.append(UInt8((len >> 8) & 0xFF))
        compressed.append(UInt8(nlen & 0xFF))
        compressed.append(UInt8((nlen >> 8) & 0xFF))
        compressed.append(contentsOf: inputBytes)

        let decompressed = try Deflate.decompress(compressed)
        #expect(decompressed == inputBytes)
    }

    @Test
    func test_deflate_fixed_huffman_block() throws {
        // BFINAL=1 (1 bit), BTYPE=01 (2 bits) -> 1, 1, 0
        // Symbol 65 ("A"): length 8, code 0b01110001 -> 0, 1, 1, 1, 0, 0, 0, 1
        // Symbol 66 ("B"): length 8, code 0b01110010 -> 0, 1, 1, 1, 0, 0, 1, 0
        // Symbol 256 (EOB): length 7, code 0b0000000 -> 0, 0, 0, 0, 0, 0, 0
        var bits: [Int] = [1, 1, 0]
        bits += [0, 1, 1, 1, 0, 0, 0, 1] // 'A'
        bits += [0, 1, 1, 1, 0, 0, 1, 0] // 'B'
        bits += [0, 0, 0, 0, 0, 0, 0] // EOB

        var bytes = [UInt8]()
        var curByte: UInt8 = 0
        var bitPos = 0
        for bit in bits {
            curByte |= UInt8(bit << bitPos)
            bitPos += 1
            if bitPos == 8 {
                bytes.append(curByte)
                curByte = 0
                bitPos = 0
            }
        }
        if bitPos > 0 { bytes.append(curByte) }

        let decompressed = try Deflate.decompress(bytes)
        #expect(decompressed == Array("AB".utf8))
    }

    @Test
    func test_deflate_dynamic_huffman_block() throws {
        let expectedString = "The quick brown fox jumps over the lazy dog. 1234567890! Repeating text with variations: The quick brown fox jumps over the lazy dog again and again!"
        let dynamicDeflateBytes: [UInt8] = [
            141, 140, 91, 14, 130, 80, 12, 5, 183, 114, 216, 0, 65, 17, 80, 151, 97, 216, 64, 149,
            114, 169, 143, 22, 47, 229, 161, 171, 151, 196, 13, 240, 55, 153, 73, 166, 238, 24, 239, 81,
            110, 15, 92, 163, 205, 138, 214, 22, 220, 199, 87, 63, 192, 38, 142, 240, 53, 63, 233, 251,
            65, 99, 33, 197, 110, 159, 31, 138, 178, 58, 158, 178, 4, 23, 238, 153, 92, 52, 192, 121,
            113, 204, 226, 29, 38, 138, 178, 58, 211, 225, 140, 122, 251, 24, 20, 72, 20, 164, 205, 159,
            146, 31
        ]

        let decompressed = try Deflate.decompress(dynamicDeflateBytes)
        #expect(decompressed == Array(expectedString.utf8))
    }

    @Test
    func test_crc32_standard_vector() {
        let testVector = [UInt8]("123456789".utf8)
        let crc = CRC32.checksum(testVector)
        #expect(crc == 0xCBF43926)
    }
}
