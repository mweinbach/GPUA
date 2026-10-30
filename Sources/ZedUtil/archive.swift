// Ported from: crates/util/src/archive.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public enum ArchiveError: LocalizedError, Sendable, Equatable {
    case invalidZipSignature
    case centralDirectoryNotFound
    case corruptZipHeader
    case unexpectedEndOfData
    case invalidHuffmanCode
    case corruptDeflateBlock
    case unsupportedCompressionMethod(Int)
    case crcMismatch(expected: UInt32, actual: UInt32)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidZipSignature:
            return "Invalid ZIP signature"
        case .centralDirectoryNotFound:
            return "ZIP Central Directory record not found"
        case .corruptZipHeader:
            return "Corrupt ZIP header or entry"
        case .unexpectedEndOfData:
            return "Unexpected end of archive data"
        case .invalidHuffmanCode:
            return "Invalid Huffman code in compressed stream"
        case .corruptDeflateBlock:
            return "Corrupt DEFLATE block"
        case .unsupportedCompressionMethod(let m):
            return "Unsupported compression method: \(m)"
        case .crcMismatch(let exp, let act):
            return "CRC-32 mismatch: expected \(exp), got \(act)"
        case .ioError(let msg):
            return msg
        }
    }
}

// MARK: - Public Extraction APIs

/// Extracts a ZIP archive from in-memory Data to the given destination URL.
public func extractZip(destination: URL, data: Data) throws {
    try ZipExtractor.extract(data: data, destination: destination)
}

/// Extracts a ZIP archive from an archive file URL to the destination URL.
public func extractZip(destination: URL, archiveURL: URL) throws {
    let data = try Data(contentsOf: archiveURL)
    try extractZip(destination: destination, data: data)
}

/// Extracts a ZIP archive from an archive path to the destination path.
public func extractZip(destination: String, archivePath: String) throws {
    try extractZip(
        destination: URL(fileURLWithPath: destination),
        archiveURL: URL(fileURLWithPath: archivePath)
    )
}

/// Async overload for extractZip from in-memory Data.
public func extractZip(destination: URL, data: Data) async throws {
    let fn: (URL, Data) throws -> Void = extractZip
    try fn(destination, data)
}

/// Async overload for extractZip from archive file URL.
public func extractZip(destination: URL, archiveURL: URL) async throws {
    let fn: (URL, URL) throws -> Void = extractZip
    try fn(destination, archiveURL)
}

/// Async overload for extractZip from paths.
public func extractZip(destination: String, archivePath: String) async throws {
    let fn: (String, String) throws -> Void = extractZip
    try fn(destination, archivePath)
}

/// Extracts a seekable ZIP archive matching upstream `extract_seekable_zip`.
public func extractSeekableZip(destination: URL, archiveURL: URL) throws {
    try extractZip(destination: destination, archiveURL: archiveURL)
}

/// Async overload for extractSeekableZip.
public func extractSeekableZip(destination: URL, archiveURL: URL) async throws {
    let fn: (URL, URL) throws -> Void = extractZip
    try fn(destination, archiveURL)
}

/// Compresses the contents of sourceDir into destinationZip.
/// If keepFilePermissions is true, stores Unix file permissions in Central Directory attributes.
public func compressZip(
    sourceDir: URL,
    destinationZip: URL,
    keepFilePermissions: Bool
) throws {
    try ZipWriter.compress(
        sourceDir: sourceDir,
        destinationZip: destinationZip,
        keepFilePermissions: keepFilePermissions
    )
}

/// Async overload for compressZip.
public func compressZip(
    sourceDir: URL,
    destinationZip: URL,
    keepFilePermissions: Bool
) async throws {
    let fn: (URL, URL, Bool) throws -> Void = compressZip
    try fn(sourceDir, destinationZip, keepFilePermissions)
}


// MARK: - CRC-32 (IEEE 802.3)

public enum CRC32 {
    private static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            let index = Int((crc ^ UInt32(b)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    public static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            var crc: UInt32 = 0xFFFFFFFF
            for i in 0..<buffer.count {
                let b = ptr[i]
                let index = Int((crc ^ UInt32(b)) & 0xFF)
                crc = table[index] ^ (crc >> 8)
            }
            return crc ^ 0xFFFFFFFF
        }
    }
}

// MARK: - RFC 1951 Pure-Swift DEFLATE Decompressor

public enum Deflate {
    // RFC 1951 Section 3.2.5 - Length codes 257..285
    private struct LengthSlot {
        let base: Int
        let extraBits: Int
    }

    private static let lengthSlots: [LengthSlot] = [
        LengthSlot(base: 3, extraBits: 0),   // 257
        LengthSlot(base: 4, extraBits: 0),   // 258
        LengthSlot(base: 5, extraBits: 0),   // 259
        LengthSlot(base: 6, extraBits: 0),   // 260
        LengthSlot(base: 7, extraBits: 0),   // 261
        LengthSlot(base: 8, extraBits: 0),   // 262
        LengthSlot(base: 9, extraBits: 0),   // 263
        LengthSlot(base: 10, extraBits: 0),  // 264
        LengthSlot(base: 11, extraBits: 1),  // 265
        LengthSlot(base: 13, extraBits: 1),  // 266
        LengthSlot(base: 15, extraBits: 1),  // 267
        LengthSlot(base: 17, extraBits: 1),  // 268
        LengthSlot(base: 19, extraBits: 2),  // 269
        LengthSlot(base: 23, extraBits: 2),  // 270
        LengthSlot(base: 27, extraBits: 2),  // 271
        LengthSlot(base: 31, extraBits: 2),  // 272
        LengthSlot(base: 35, extraBits: 3),  // 273
        LengthSlot(base: 43, extraBits: 3),  // 274
        LengthSlot(base: 51, extraBits: 3),  // 275
        LengthSlot(base: 59, extraBits: 3),  // 276
        LengthSlot(base: 67, extraBits: 4),  // 277
        LengthSlot(base: 83, extraBits: 4),  // 278
        LengthSlot(base: 99, extraBits: 4),  // 279
        LengthSlot(base: 115, extraBits: 4), // 280
        LengthSlot(base: 131, extraBits: 5), // 281
        LengthSlot(base: 163, extraBits: 5), // 282
        LengthSlot(base: 195, extraBits: 5), // 283
        LengthSlot(base: 227, extraBits: 5), // 284
        LengthSlot(base: 258, extraBits: 0), // 285
    ]

    // RFC 1951 Section 3.2.5 - Distance codes 0..29
    private struct DistanceSlot {
        let base: Int
        let extraBits: Int
    }

    private static let distanceSlots: [DistanceSlot] = [
        DistanceSlot(base: 1, extraBits: 0),      // 0
        DistanceSlot(base: 2, extraBits: 0),      // 1
        DistanceSlot(base: 3, extraBits: 0),      // 2
        DistanceSlot(base: 4, extraBits: 0),      // 3
        DistanceSlot(base: 5, extraBits: 1),      // 4
        DistanceSlot(base: 7, extraBits: 1),      // 5
        DistanceSlot(base: 9, extraBits: 2),      // 6
        DistanceSlot(base: 13, extraBits: 2),     // 7
        DistanceSlot(base: 17, extraBits: 3),     // 8
        DistanceSlot(base: 25, extraBits: 3),     // 9
        DistanceSlot(base: 33, extraBits: 4),     // 10
        DistanceSlot(base: 49, extraBits: 4),     // 11
        DistanceSlot(base: 65, extraBits: 5),     // 12
        DistanceSlot(base: 97, extraBits: 5),     // 13
        DistanceSlot(base: 129, extraBits: 6),    // 14
        DistanceSlot(base: 193, extraBits: 6),    // 15
        DistanceSlot(base: 257, extraBits: 7),    // 16
        DistanceSlot(base: 385, extraBits: 7),    // 17
        DistanceSlot(base: 513, extraBits: 8),    // 18
        DistanceSlot(base: 769, extraBits: 8),    // 19
        DistanceSlot(base: 1025, extraBits: 9),   // 20
        DistanceSlot(base: 1537, extraBits: 9),   // 21
        DistanceSlot(base: 2049, extraBits: 10),  // 22
        DistanceSlot(base: 3073, extraBits: 10),  // 23
        DistanceSlot(base: 4097, extraBits: 11),  // 24
        DistanceSlot(base: 6145, extraBits: 11),  // 25
        DistanceSlot(base: 8193, extraBits: 12),  // 26
        DistanceSlot(base: 12289, extraBits: 12), // 27
        DistanceSlot(base: 16385, extraBits: 13), // 28
        DistanceSlot(base: 24577, extraBits: 13), // 29
    ]

    private static let fixedLiteralLengths: [Int] = {
        var lengths = [Int](repeating: 0, count: 288)
        for i in 0...143 { lengths[i] = 8 }
        for i in 144...255 { lengths[i] = 9 }
        for i in 256...279 { lengths[i] = 7 }
        for i in 280...287 { lengths[i] = 8 }
        return lengths
    }()

    private static let fixedDistanceLengths: [Int] = [Int](repeating: 5, count: 32)

    private struct BitReader {
        let bytes: [UInt8]
        var byteOffset: Int = 0
        var bitBuffer: UInt32 = 0
        var bitsInBuffer: Int = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func readBit() throws -> Int {
            if bitsInBuffer == 0 {
                guard byteOffset < bytes.count else {
                    throw ArchiveError.unexpectedEndOfData
                }
                bitBuffer = UInt32(bytes[byteOffset])
                byteOffset += 1
                bitsInBuffer = 8
            }
            let bit = Int(bitBuffer & 1)
            bitBuffer >>= 1
            bitsInBuffer -= 1
            return bit
        }

        mutating func readBits(_ count: Int) throws -> Int {
            guard count > 0 else { return 0 }
            while bitsInBuffer < count {
                guard byteOffset < bytes.count else {
                    throw ArchiveError.unexpectedEndOfData
                }
                bitBuffer |= (UInt32(bytes[byteOffset]) << bitsInBuffer)
                byteOffset += 1
                bitsInBuffer += 8
            }
            let mask = (1 << count) - 1
            let value = Int(bitBuffer & UInt32(mask))
            bitBuffer >>= count
            bitsInBuffer -= count
            return value
        }

        mutating func alignToByte() {
            bitBuffer = 0
            bitsInBuffer = 0
        }

        mutating func readBytes(_ count: Int) throws -> [UInt8] {
            alignToByte()
            guard byteOffset + count <= bytes.count else {
                throw ArchiveError.unexpectedEndOfData
            }
            let slice = bytes[byteOffset ..< byteOffset + count]
            byteOffset += count
            return Array(slice)
        }
    }

    private struct HuffmanNode {
        var symbol: Int = -1
        var left: Int = -1
        var right: Int = -1
    }

    private struct HuffmanTree {
        var nodes: [HuffmanNode]

        init(lengths: [Int]) throws {
            var nodes = [HuffmanNode()]
            let maxBits = lengths.max() ?? 0
            if maxBits == 0 {
                self.nodes = nodes
                return
            }

            var blCount = [Int](repeating: 0, count: maxBits + 1)
            for len in lengths where len > 0 {
                blCount[len] += 1
            }

            var nextCode = [Int](repeating: 0, count: maxBits + 1)
            var code = 0
            for bits in 1...maxBits {
                code = (code + blCount[bits - 1]) << 1
                nextCode[bits] = code
            }

            for (symbol, len) in lengths.enumerated() {
                guard len > 0 else { continue }
                let codeVal = nextCode[len]
                nextCode[len] += 1

                var nodeIdx = 0
                for bitPos in stride(from: len - 1, through: 0, by: -1) {
                    let bit = (codeVal >> bitPos) & 1
                    if bit == 0 {
                        if nodes[nodeIdx].left == -1 {
                            nodes[nodeIdx].left = nodes.count
                            nodes.append(HuffmanNode())
                        }
                        nodeIdx = nodes[nodeIdx].left
                    } else {
                        if nodes[nodeIdx].right == -1 {
                            nodes[nodeIdx].right = nodes.count
                            nodes.append(HuffmanNode())
                        }
                        nodeIdx = nodes[nodeIdx].right
                    }
                }
                nodes[nodeIdx].symbol = symbol
            }

            self.nodes = nodes
        }

        func decode(reader: inout BitReader) throws -> Int {
            var nodeIdx = 0
            while nodes[nodeIdx].symbol == -1 {
                let bit = try reader.readBit()
                let nextIdx = (bit == 0) ? nodes[nodeIdx].left : nodes[nodeIdx].right
                guard nextIdx != -1 else {
                    throw ArchiveError.invalidHuffmanCode
                }
                nodeIdx = nextIdx
            }
            return nodes[nodeIdx].symbol
        }
    }

    public static func decompress(_ bytes: [UInt8]) throws -> [UInt8] {
        var reader = BitReader(bytes: bytes)
        var output = [UInt8]()
        var isFinal = false

        while !isFinal {
            isFinal = (try reader.readBit() == 1)
            let blockType = try reader.readBits(2)

            switch blockType {
            case 0b00:
                // Stored block
                reader.alignToByte()
                let lenLow = try reader.readBits(8)
                let lenHigh = try reader.readBits(8)
                let len = lenLow | (lenHigh << 8)
                let nlenLow = try reader.readBits(8)
                let nlenHigh = try reader.readBits(8)
                let nlen = nlenLow | (nlenHigh << 8)
                guard len == (~nlen & 0xFFFF) else {
                    throw ArchiveError.corruptDeflateBlock
                }
                let storedBytes = try reader.readBytes(len)
                output.append(contentsOf: storedBytes)

            case 0b01:
                // Fixed Huffman block
                let litTree = try HuffmanTree(lengths: fixedLiteralLengths)
                let distTree = try HuffmanTree(lengths: fixedDistanceLengths)
                try decodeHuffmanBlock(reader: &reader, litTree: litTree, distTree: distTree, output: &output)

            case 0b10:
                // Dynamic Huffman block
                let hlit = try reader.readBits(5) + 257
                let hdist = try reader.readBits(5) + 1
                let hclen = try reader.readBits(4) + 4

                let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var codeLengths = [Int](repeating: 0, count: 19)
                for i in 0..<hclen {
                    codeLengths[codeLengthOrder[i]] = try reader.readBits(3)
                }
                let codeLengthTree = try HuffmanTree(lengths: codeLengths)

                var litAndDistLengths = [Int]()
                let totalLengths = hlit + hdist
                while litAndDistLengths.count < totalLengths {
                    let symbol = try codeLengthTree.decode(reader: &reader)
                    switch symbol {
                    case 0...15:
                        litAndDistLengths.append(symbol)
                    case 16:
                        guard let prev = litAndDistLengths.last else {
                            throw ArchiveError.corruptDeflateBlock
                        }
                        let repeatCount = try reader.readBits(2) + 3
                        for _ in 0..<repeatCount {
                            litAndDistLengths.append(prev)
                        }
                    case 17:
                        let repeatCount = try reader.readBits(3) + 3
                        for _ in 0..<repeatCount {
                            litAndDistLengths.append(0)
                        }
                    case 18:
                        let repeatCount = try reader.readBits(7) + 11
                        for _ in 0..<repeatCount {
                            litAndDistLengths.append(0)
                        }
                    default:
                        throw ArchiveError.corruptDeflateBlock
                    }
                }
                guard litAndDistLengths.count >= totalLengths else {
                    throw ArchiveError.corruptDeflateBlock
                }

                let litLengths = Array(litAndDistLengths[0..<hlit])
                let distLengths = Array(litAndDistLengths[hlit..<(hlit + hdist)])

                let litTree = try HuffmanTree(lengths: litLengths)
                let distTree = try HuffmanTree(lengths: distLengths)
                try decodeHuffmanBlock(reader: &reader, litTree: litTree, distTree: distTree, output: &output)

            default:
                throw ArchiveError.corruptDeflateBlock
            }
        }

        return output
    }

    public static func decompress(_ data: Data) throws -> Data {
        let bytes = Array(data)
        let uncompressed = try decompress(bytes)
        return Data(uncompressed)
    }

    private static func decodeHuffmanBlock(
        reader: inout BitReader,
        litTree: HuffmanTree,
        distTree: HuffmanTree,
        output: inout [UInt8]
    ) throws {
        while true {
            let symbol = try litTree.decode(reader: &reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                break
            } else if symbol <= 285 {
                let slot = lengthSlots[symbol - 257]
                let extra = try reader.readBits(slot.extraBits)
                let length = slot.base + extra

                let distSymbol = try distTree.decode(reader: &reader)
                guard distSymbol < distanceSlots.count else {
                    throw ArchiveError.corruptDeflateBlock
                }
                let distSlot = distanceSlots[distSymbol]
                let distExtra = try reader.readBits(distSlot.extraBits)
                let distance = distSlot.base + distExtra

                guard distance <= output.count else {
                    throw ArchiveError.corruptDeflateBlock
                }

                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            } else {
                throw ArchiveError.corruptDeflateBlock
            }
        }
    }
}

// MARK: - ZIP Extraction & Central Directory Engine

private struct ZipEntryInfo {
    let filename: String
    let isDirectory: Bool
    let compressionMethod: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
    let unixPermissions: Int?
}

private enum ZipExtractor {
    static func extract(data: Data, destination: URL) throws {
        let fileManager = FileManager.default
        let destPath = destination.path
        let entries = try parseEntries(data: data)

        for entry in entries {
            let relative = entry.filename.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let itemPath = (destPath as NSString).appendingPathComponent(relative)

            if entry.isDirectory {
                try fileManager.createDirectory(
                    atPath: itemPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } else {
                let parentDir = (itemPath as NSString).deletingLastPathComponent
                try fileManager.createDirectory(
                    atPath: parentDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                let uncompressed = try extractData(for: entry, in: data)
                try uncompressed.write(to: URL(fileURLWithPath: itemPath))

                #if !os(Windows)
                if let perms = entry.unixPermissions, perms != 0 {
                    try? fileManager.setAttributes([.posixPermissions: perms], ofItemAtPath: itemPath)
                }
                #endif
            }
        }
    }

    private static func parseEntries(data: Data) throws -> [ZipEntryInfo] {
        if let cdEntries = try? parseCentralDirectory(data: data), !cdEntries.isEmpty {
            return cdEntries
        }
        return try parseLocalHeaders(data: data)
    }

    private static func parseCentralDirectory(data: Data) throws -> [ZipEntryInfo] {
        let bytes = Array(data)
        guard bytes.count >= 22 else {
            throw ArchiveError.corruptZipHeader
        }

        // Search backward for End of Central Directory record (0x06054b50)
        var eocdOffset: Int? = nil
        let maxSearch = min(bytes.count - 22, 65557)
        let searchStart = bytes.count - 22
        for i in 0...maxSearch {
            let offset = searchStart - i
            if bytes[offset] == 0x50 &&
               bytes[offset + 1] == 0x4b &&
               bytes[offset + 2] == 0x05 &&
               bytes[offset + 3] == 0x06 {
                eocdOffset = offset
                break
            }
        }

        guard let eocd = eocdOffset else {
            throw ArchiveError.centralDirectoryNotFound
        }

        let totalEntries = Int(readUInt16(bytes: bytes, offset: eocd + 10))
        let cdOffset = Int(readUInt32(bytes: bytes, offset: eocd + 16))

        var entries = [ZipEntryInfo]()
        var offset = cdOffset

        for _ in 0..<totalEntries {
            guard offset + 46 <= bytes.count else {
                throw ArchiveError.corruptZipHeader
            }
            let sig = readUInt32(bytes: bytes, offset: offset)
            guard sig == 0x02014b50 else {
                break
            }

            let versionMadeBy = readUInt16(bytes: bytes, offset: offset + 4)
            let method = readUInt16(bytes: bytes, offset: offset + 10)
            let crc = readUInt32(bytes: bytes, offset: offset + 16)
            let compSize = readUInt32(bytes: bytes, offset: offset + 20)
            let uncompSize = readUInt32(bytes: bytes, offset: offset + 24)
            let nameLen = Int(readUInt16(bytes: bytes, offset: offset + 28))
            let extraLen = Int(readUInt16(bytes: bytes, offset: offset + 30))
            let commentLen = Int(readUInt16(bytes: bytes, offset: offset + 32))
            let extAttrs = readUInt32(bytes: bytes, offset: offset + 38)
            let localOffset = readUInt32(bytes: bytes, offset: offset + 42)

            let nameStart = offset + 46
            guard nameStart + nameLen <= bytes.count else {
                throw ArchiveError.corruptZipHeader
            }
            let nameBytes = bytes[nameStart ..< nameStart + nameLen]
            let filename = String(decoding: nameBytes, as: UTF8.self)

            let isDir = filename.hasSuffix("/") || ((extAttrs >> 16) & 0o170000 == 0o040000)

            let hostOS = (versionMadeBy >> 8) & 0xFF
            var unixPerms: Int? = nil
            if hostOS == 3 {
                let mode = Int((extAttrs >> 16) & 0xFFFF)
                if mode != 0 {
                    unixPerms = mode & 0o7777
                }
            }

            entries.append(ZipEntryInfo(
                filename: filename,
                isDirectory: isDir,
                compressionMethod: method,
                crc32: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset,
                unixPermissions: unixPerms
            ))

            offset += 46 + nameLen + extraLen + commentLen
        }

        return entries
    }

    private static func parseLocalHeaders(data: Data) throws -> [ZipEntryInfo] {
        let bytes = Array(data)
        var offset = 0
        var entries = [ZipEntryInfo]()

        while offset + 30 <= bytes.count {
            let sig = readUInt32(bytes: bytes, offset: offset)
            if sig != 0x04034b50 { break }

            let method = readUInt16(bytes: bytes, offset: offset + 8)
            let crc = readUInt32(bytes: bytes, offset: offset + 14)
            let compSize = readUInt32(bytes: bytes, offset: offset + 18)
            let uncompSize = readUInt32(bytes: bytes, offset: offset + 22)
            let nameLen = Int(readUInt16(bytes: bytes, offset: offset + 26))
            let extraLen = Int(readUInt16(bytes: bytes, offset: offset + 28))

            let nameStart = offset + 30
            guard nameStart + nameLen <= bytes.count else { break }
            let nameBytes = bytes[nameStart ..< nameStart + nameLen]
            let filename = String(decoding: nameBytes, as: UTF8.self)
            let isDir = filename.hasSuffix("/")

            entries.append(ZipEntryInfo(
                filename: filename,
                isDirectory: isDir,
                compressionMethod: method,
                crc32: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: UInt32(offset),
                unixPermissions: nil
            ))

            offset += 30 + nameLen + extraLen + Int(compSize)
        }

        return entries
    }

    private static func extractData(for entry: ZipEntryInfo, in data: Data) throws -> Data {
        let bytes = Array(data)
        let localOffset = Int(entry.localHeaderOffset)
        guard localOffset + 30 <= bytes.count else {
            throw ArchiveError.corruptZipHeader
        }
        let sig = readUInt32(bytes: bytes, offset: localOffset)
        guard sig == 0x04034b50 else {
            throw ArchiveError.invalidZipSignature
        }

        let nameLen = Int(readUInt16(bytes: bytes, offset: localOffset + 26))
        let extraLen = Int(readUInt16(bytes: bytes, offset: localOffset + 28))
        let dataStart = localOffset + 30 + nameLen + extraLen
        let dataEnd = dataStart + Int(entry.compressedSize)

        guard dataEnd <= bytes.count else {
            throw ArchiveError.unexpectedEndOfData
        }

        let compressedBytes = Array(bytes[dataStart..<dataEnd])
        let uncompressedBytes: [UInt8]

        switch entry.compressionMethod {
        case 0:
            uncompressedBytes = compressedBytes
        case 8:
            uncompressedBytes = try Deflate.decompress(compressedBytes)
        default:
            throw ArchiveError.unsupportedCompressionMethod(Int(entry.compressionMethod))
        }

        if entry.crc32 != 0 {
            let actualCrc = CRC32.checksum(uncompressedBytes)
            if actualCrc != entry.crc32 {
                throw ArchiveError.crcMismatch(expected: entry.crc32, actual: actualCrc)
            }
        }

        return Data(uncompressedBytes)
    }

    private static func readUInt16(bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - Pure-Swift ZIP Writer (for tests and packaging)

private enum ZipWriter {
    static func compress(
        sourceDir: URL,
        destinationZip: URL,
        keepFilePermissions: Bool
    ) throws {
        let fileManager = FileManager.default
        let srcPath = sourceDir.path
        guard let enumerator = fileManager.enumerator(atPath: srcPath) else {
            throw ArchiveError.ioError("Cannot read source directory: \(srcPath)")
        }

        var localHeadersData = Data()
        var centralDirData = Data()
        var entryCount: UInt16 = 0

        while let item = enumerator.nextObject() as? String {
            let fullPath = (srcPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
                continue
            }
            if isDir.boolValue {
                continue
            }

            let uncompressedData = try Data(contentsOf: URL(fileURLWithPath: fullPath))
            let uncompressedBytes = Array(uncompressedData)
            let crc = CRC32.checksum(uncompressedBytes)
            let uncompSize = UInt32(uncompressedBytes.count)

            // Compress using stored RFC 1951 DEFLATE blocks (BTYPE 00)
            let compressedBytes = createDeflateStoredBlocks(uncompressedBytes)
            let compSize = UInt32(compressedBytes.count)

            let filenameBytes = Array(item.utf8)
            let filenameLen = UInt16(filenameBytes.count)

            let localHeaderOffset = UInt32(localHeadersData.count)

            // Local File Header
            localHeadersData.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // PK\x03\x04
            localHeadersData.appendUInt16(20) // version needed: 2.0
            localHeadersData.appendUInt16(0x0800) // general purpose flag: bit 11 UTF-8
            localHeadersData.appendUInt16(8) // compression method: 8 (Deflate)
            localHeadersData.appendUInt16(0) // mod time
            localHeadersData.appendUInt16(0) // mod date
            localHeadersData.appendUInt32(crc)
            localHeadersData.appendUInt32(compSize)
            localHeadersData.appendUInt32(uncompSize)
            localHeadersData.appendUInt16(filenameLen)
            localHeadersData.appendUInt16(0) // extra length
            localHeadersData.append(contentsOf: filenameBytes)
            localHeadersData.append(contentsOf: compressedBytes)

            // Permissions
            var externalAttrs: UInt32 = 0
            #if !os(Windows)
            if keepFilePermissions {
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let perms = attrs[.posixPermissions] as? NSNumber {
                    externalAttrs = UInt32((0o100000 | perms.intValue) << 16)
                }
            }
            #endif

            // Central Directory Record
            centralDirData.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // PK\x01\x02
            centralDirData.appendUInt16((3 << 8) | 20) // version made by: Unix 2.0
            centralDirData.appendUInt16(20) // version needed
            centralDirData.appendUInt16(0x0800) // flags: UTF-8
            centralDirData.appendUInt16(8) // compression: Deflate
            centralDirData.appendUInt16(0) // time
            centralDirData.appendUInt16(0) // date
            centralDirData.appendUInt32(crc)
            centralDirData.appendUInt32(compSize)
            centralDirData.appendUInt32(uncompSize)
            centralDirData.appendUInt16(filenameLen)
            centralDirData.appendUInt16(0) // extra length
            centralDirData.appendUInt16(0) // comment length
            centralDirData.appendUInt16(0) // disk number start
            centralDirData.appendUInt16(0) // internal attrs
            centralDirData.appendUInt32(externalAttrs)
            centralDirData.appendUInt32(localHeaderOffset)
            centralDirData.append(contentsOf: filenameBytes)

            entryCount += 1
        }

        let cdOffset = UInt32(localHeadersData.count)
        let cdSize = UInt32(centralDirData.count)

        var zipData = localHeadersData
        zipData.append(centralDirData)

        // End of Central Directory Record
        zipData.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // PK\x05\x06
        zipData.appendUInt16(0) // disk number
        zipData.appendUInt16(0) // disk where CD starts
        zipData.appendUInt16(entryCount)
        zipData.appendUInt16(entryCount)
        zipData.appendUInt32(cdSize)
        zipData.appendUInt32(cdOffset)
        zipData.appendUInt16(0) // comment length

        #if os(WASI)
        try zipData.write(to: destinationZip)
        #else
        try zipData.write(to: destinationZip, options: .atomic)
        #endif
    }

    private static func createDeflateStoredBlocks(_ bytes: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        if bytes.isEmpty {
            // Empty stored block with BFINAL=1
            result.append(0x01)
            result.append(contentsOf: [0x00, 0x00, 0xFF, 0xFF])
            return result
        }

        var offset = 0
        while offset < bytes.count {
            let chunkSize = min(bytes.count - offset, 65535)
            let isLast = (offset + chunkSize == bytes.count)
            let headerByte: UInt8 = isLast ? 0x01 : 0x00 // BFINAL | BTYPE 00
            result.append(headerByte)

            let len = UInt16(chunkSize)
            let nlen = ~len
            result.append(UInt8(len & 0xFF))
            result.append(UInt8((len >> 8) & 0xFF))
            result.append(UInt8(nlen & 0xFF))
            result.append(UInt8((nlen >> 8) & 0xFF))
            result.append(contentsOf: bytes[offset ..< offset + chunkSize])
            offset += chunkSize
        }
        return result
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}
