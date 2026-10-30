// Swift-only: Pure-Swift zero-dependency PNG encoder for test artifacts and screenshots

import Foundation

public enum PNGEncoder: Sendable {
    /// Encodes raw RGBA (8-bit per channel) pixel bytes into a valid PNG Data buffer.
    public static func encodeRGBA(width: Int, height: Int, rgba: [UInt8]) -> Data {
        guard width > 0 && height > 0 else {
            return Data()
        }
        let expectedBytes = width * height * 4
        guard rgba.count >= expectedBytes else {
            return Data()
        }

        var output = Data()
        output.reserveCapacity(58 + height * (1 + width * 4))

        // 1. PNG Signature (RFC 2083 Section 3.1)
        output.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // 2. IHDR Chunk (Image Header)
        var ihdr = Data(capacity: 13)
        appendUInt32BigEndian(UInt32(width), to: &ihdr)
        appendUInt32BigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [
            8,  // bit depth: 8 bits per channel
            6,  // color type: RGBA (Truecolor with alpha)
            0,  // compression method: 0 (deflate)
            0,  // filter method: 0 (standard adaptive filtering)
            0   // interlace method: 0 (no interlace)
        ])
        writeChunk(type: "IHDR", payload: ihdr, into: &output)

        // 3. IDAT Chunk (Filtered Scanlines + zlib compressed Deflate stream)
        let rowBytes = width * 4
        var filtered = Data(capacity: height * (1 + rowBytes))
        for y in 0..<height {
            filtered.append(0x00) // Filter type: None (Filter 0)
            let rowStart = y * rowBytes
            rgba.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    filtered.append(base.advanced(by: rowStart), count: rowBytes)
                }
            }
        }

        var zlib = Data(capacity: filtered.count + 64)
        zlib.append(contentsOf: [0x78, 0x01]) // zlib header (CM=8, CINFO=7, FCHECK=1)

        // Uncompressed deflate blocks (RFC 1951 BTYPE=00, max 65,535 bytes per block)
        var offset = 0
        let total = filtered.count
        filtered.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            while offset < total {
                let chunkLen = min(total - offset, 65535)
                let isLast = (offset + chunkLen == total)
                zlib.append(isLast ? 0x01 : 0x00) // BFINAL + BTYPE (00)
                let len16 = UInt16(chunkLen)
                let nlen16 = ~len16
                zlib.append(UInt8(len16 & 0xFF))
                zlib.append(UInt8(len16 >> 8))
                zlib.append(UInt8(nlen16 & 0xFF))
                zlib.append(UInt8(nlen16 >> 8))
                zlib.append(ptr.advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: chunkLen)
                offset += chunkLen
            }
        }

        // Adler-32 trailer (RFC 1950)
        let adler = calculateAdler32(filtered)
        appendUInt32BigEndian(adler, to: &zlib)
        writeChunk(type: "IDAT", payload: zlib, into: &output)

        // 4. IEND Chunk (Image Trailer)
        writeChunk(type: "IEND", payload: Data(), into: &output)

        return output
    }

    /// Convenience overload accepting UInt32 dimensions.
    public static func encodeRGBA(width: UInt32, height: UInt32, rgba: [UInt8]) -> Data {
        encodeRGBA(width: Int(width), height: Int(height), rgba: rgba)
    }

    // MARK: - Chunk Writing & Checksums

    private static func writeChunk(type: StaticString, payload: Data, into output: inout Data) {
        appendUInt32BigEndian(UInt32(payload.count), to: &output)
        let typeStart = output.count
        output.append(type.utf8Start, count: type.utf8CodeUnitCount)
        output.append(payload)
        let crc = calculateCRC32(data: output, offset: typeStart, length: type.utf8CodeUnitCount + payload.count)
        appendUInt32BigEndian(crc, to: &output)
    }

    private static func appendUInt32BigEndian(_ value: UInt32, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func calculateAdler32(_ data: Data) -> UInt32 {
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var remaining = data.count
            var cur = ptr
            while remaining > 0 {
                let n = min(remaining, 5550)
                remaining -= n
                for _ in 0..<n {
                    s1 &+= UInt32(cur.pointee)
                    s2 &+= s1
                    cur = cur.advanced(by: 1)
                }
                s1 %= 65521
                s2 %= 65521
            }
        }
        return (s2 << 16) | s1
    }

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table[i] = c
        }
        return table
    }()

    private static func calculateCRC32(data: Data, offset: Int, length: Int) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let p = ptr.advanced(by: offset)
            for i in 0..<length {
                let byte = p[i]
                let idx = Int((c ^ UInt32(byte)) & 0xFF)
                c = crcTable[idx] ^ (c >> 8)
            }
        }
        return c ^ 0xFFFFFFFF
    }
}
