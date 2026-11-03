// Ported from: crates/rune/src/gpu/metal/builtin.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Built-in shader hash lookup and BLAKE3 pipeline key derivation for Rune's Metal backend.

// MARK: - Pure-Swift BLAKE3-256

private let blake3IV: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
]

private let blake3Perm: [Int] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

@inline(__always)
private func blake3Rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

@inline(__always)
private func blake3G(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ mx: UInt32, _ my: UInt32) {
    s[a] = s[a] &+ s[b] &+ mx
    s[d] = blake3Rotr(s[d] ^ s[a], 16)
    s[c] = s[c] &+ s[d]
    s[b] = blake3Rotr(s[b] ^ s[c], 12)
    s[a] = s[a] &+ s[b] &+ my
    s[d] = blake3Rotr(s[d] ^ s[a], 8)
    s[c] = s[c] &+ s[d]
    s[b] = blake3Rotr(s[b] ^ s[c], 7)
}

private func blake3Compress(_ cv: [UInt32], _ blockWords: [UInt32], _ counter: UInt64, _ blockLen: UInt32, _ flags: UInt32) -> [UInt32] {
    var s: [UInt32] = [
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        blake3IV[0], blake3IV[1], blake3IV[2], blake3IV[3],
        UInt32(truncatingIfNeeded: counter),
        UInt32(truncatingIfNeeded: counter >> 32),
        blockLen,
        flags,
    ]
    var m = blockWords
    for round in 0..<7 {
        blake3G(&s, 0, 4, 8, 12, m[0], m[1])
        blake3G(&s, 1, 5, 9, 13, m[2], m[3])
        blake3G(&s, 2, 6, 10, 14, m[4], m[5])
        blake3G(&s, 3, 7, 11, 15, m[6], m[7])
        blake3G(&s, 0, 5, 10, 15, m[8], m[9])
        blake3G(&s, 1, 6, 11, 12, m[10], m[11])
        blake3G(&s, 2, 7, 8, 13, m[12], m[13])
        blake3G(&s, 3, 4, 9, 14, m[14], m[15])
        if round < 6 {
            var next = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 { next[i] = m[blake3Perm[i]] }
            m = next
        }
    }
    for i in 0..<8 { s[i] ^= s[i + 8] }
    return Array(s[0..<8])
}

/// Computes the 32-byte BLAKE3 digest for arbitrary input bytes.
public func runeBlake3Bytes(_ input: [UInt8]) -> [UInt8] {
    let chunkStart: UInt32 = 1 << 0
    let chunkEnd: UInt32 = 1 << 1
    let parentFlag: UInt32 = 1 << 2
    let rootFlag: UInt32 = 1 << 3

    func blockWords(_ slice: ArraySlice<UInt8>) -> [UInt32] {
        var padded = [UInt8](repeating: 0, count: 64)
        for (idx, b) in slice.enumerated() { padded[idx] = b }
        var w = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let o = i * 4
            w[i] = UInt32(padded[o])
                | (UInt32(padded[o + 1]) << 8)
                | (UInt32(padded[o + 2]) << 16)
                | (UInt32(padded[o + 3]) << 24)
        }
        return w
    }

    func wordsToBytes(_ words: [UInt32]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32)
        for i in 0..<8 {
            let v = words[i]
            out[i * 4] = UInt8(truncatingIfNeeded: v)
            out[i * 4 + 1] = UInt8(truncatingIfNeeded: v >> 8)
            out[i * 4 + 2] = UInt8(truncatingIfNeeded: v >> 16)
            out[i * 4 + 3] = UInt8(truncatingIfNeeded: v >> 24)
        }
        return out
    }

    if input.isEmpty {
        let out = blake3Compress(blake3IV, [UInt32](repeating: 0, count: 16), 0, 0, chunkStart | chunkEnd | rootFlag)
        return wordsToBytes(out)
    }

    let totalChunks = (input.count + 1023) / 1024
    var cvStack: [[UInt32]] = []

    for chunkIdx in 0..<totalChunks {
        let cStart = chunkIdx * 1024
        let cEnd = min(cStart + 1024, input.count)
        let chunkLen = cEnd - cStart
        let blocks = max(1, (chunkLen + 63) / 64)
        var cv = blake3IV

        for b in 0..<blocks {
            let bStart = cStart + b * 64
            let bEnd = min(bStart + 64, cEnd)
            var flags: UInt32 = 0
            if b == 0 { flags |= chunkStart }
            if b == blocks - 1 { flags |= chunkEnd }
            let isSingleChunkRoot = (totalChunks == 1 && b == blocks - 1)
            if isSingleChunkRoot {
                flags |= rootFlag
                let rootWords = blake3Compress(cv, blockWords(input[bStart..<bEnd]), UInt64(chunkIdx), UInt32(bEnd - bStart), flags)
                return wordsToBytes(rootWords)
            }
            cv = blake3Compress(cv, blockWords(input[bStart..<bEnd]), UInt64(chunkIdx), UInt32(bEnd - bStart), flags)
        }

        var totalAfter = chunkIdx + 1
        var newCv = cv
        if totalAfter < totalChunks {
            while (totalAfter & 1) == 0 {
                let left = cvStack.removeLast()
                newCv = blake3Compress(blake3IV, left + newCv, 0, 64, parentFlag)
                totalAfter >>= 1
            }
        }
        cvStack.append(newCv)
    }

    while cvStack.count > 1 {
        let right = cvStack.removeLast()
        let left = cvStack.removeLast()
        let flags = cvStack.isEmpty ? (parentFlag | rootFlag) : parentFlag
        let merged = blake3Compress(blake3IV, left + right, 0, 64, flags)
        if cvStack.isEmpty {
            return wordsToBytes(merged)
        }
        cvStack.append(merged)
    }
    return wordsToBytes(cvStack[0])
}

/// Hex-encoded 64-character BLAKE3-256 digest.
public func runeBlake3Hex(_ bytes: [UInt8]) -> String {
    let hexDigits = Array("0123456789abcdef".utf8)
    let digest = runeBlake3Bytes(bytes)
    var out = [UInt8]()
    out.reserveCapacity(64)
    for b in digest {
        out.append(hexDigits[Int(b >> 4)])
        out.append(hexDigits[Int(b & 0x0f)])
    }
    return String(decoding: out, as: UTF8.self)
}

public func runeBlake3Hex(_ text: String) -> String {
    runeBlake3Hex(Array(text.utf8))
}

private let builtinMissesLock = LiveLock()
// PORT NOTE: Guarded by `builtinMissesLock`, mirroring `static MISSES: AtomicUsize` in `builtin.rs`.
nonisolated(unsafe) private var builtinMissesValue: Int = 0

public func metalBuiltinShortHash(_ hex: String) -> String {
    String(hex.prefix(32))
}

public func metalBuiltinEnabled() -> Bool {
    if let raw = readProcessEnv("RUNE_DISABLE_METALLIB") {
        let lower = raw.lowercased()
        if lower == "1" || lower == "true" || lower == "yes" {
            return false
        }
    }
    if readProcessEnv("RUNE_METAL_CAPTURE") != nil {
        return false
    }
    return true
}

/// Whether `sourceWgslHashHex` (full 64-char or 32-char prefix) is a known built-in WGSL module.
public func metalBuiltinKnown(_ sourceWgslHashHex: String) -> Bool {
    guard metalBuiltinEnabled() else { return false }
    let target = metalBuiltinShortHash(sourceWgslHashHex)
    return METAL_BUILTIN_SOURCES.contains(target)
}

/// Computes the deterministic pipeline key `"k<32-hex>"` for a stage + entry + overrides + layout.
public func metalBuiltinKey(
    sourceHashBytes: [UInt8],
    stage: MetalShaderStages,
    entry: String,
    constants: [(String, Double)],
    points: Bool,
    slotsDescription: String
) -> String {
    var payload = sourceHashBytes
    payload.append(contentsOf: "\(stage.rawValue)|\(entry)|\(constants)|\(points)|\(slotsDescription)".utf8)
    return "k" + metalBuiltinShortHash(runeBlake3Hex(payload))
}

/// Looks up a precompiled function row in `METAL_BUILTIN_FUNCTIONS`, incrementing `metalBuiltinMisses()` on a miss.
public func metalBuiltinLookupRow(_ key: String) -> MetalBuiltinFunctionRow? {
    guard metalBuiltinEnabled() else { return nil }
    var lo = 0
    var hi = METAL_BUILTIN_FUNCTIONS.count - 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        let row = METAL_BUILTIN_FUNCTIONS[mid]
        if row.key == key {
            return row
        } else if row.key < key {
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    builtinMissesLock.withLock { builtinMissesValue += 1 }
    return nil
}

/// How many pipelines compiled at runtime because `METAL_BUILTIN_FUNCTIONS` lacked their key.
public func metalBuiltinMisses() -> Int {
    builtinMissesLock.withLock { builtinMissesValue }
}
