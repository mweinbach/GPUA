// Ported from: crates/rune/src/video/foreign.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Ogg (Vorbis, Opus) and WebM/Matroska container sniffing and 16-bit PCM WAV header/temp-file
//! generation (`video/foreign.rs`).
//!
//! // PORT NOTE: Upstream uses external Rust crates `symphonia` and `opuscule` behind the Cargo
//! // `ogg-audio` feature to software-decode Ogg Vorbis / Opus / WebM Opus into temporary 16-bit
//! // PCM WAV files. Per GPUA Golden Rule 8 (no unapproved C/SwiftPM dependencies without an ADR),
//! // `foreignSniff` and `foreignWavHeader` / `ForeignWav` are ported bit-for-bit, while compressed
//! // Vorbis/Opus packet decoding reports a clear unsupported-codec error when invoked.

#if !os(WASI)
import Foundation
#endif

/// A WAV's sizes are 32-bit: at most this many 16-bit samples (about 6 hours of 48 kHz stereo).
let FOREIGN_MAX_SAMPLES: UInt64 = (UInt64(UInt32.max) - 36) / 2
private let FOREIGN_TOO_LONG: String = "too long to decode (a WAV holds about 6 hours of 48 kHz stereo)"

/// An Ogg or EBML (WebM, Matroska) stream, by its first bytes.
func foreignSniff(_ bytes: [UInt8]) -> Bool {
    if bytes.count >= 4 {
        if bytes[0] == 0x4f && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53 {
            return true // "OggS"
        }
        if bytes[0] == 0x1a && bytes[1] == 0x45 && bytes[2] == 0xdf && bytes[3] == 0xa3 {
            return true // EBML
        }
    }
    return false
}

/// Validates an `OpusHead` identification header (RFC 7845 §5.1), returning `(channels, preSkip, gain)`.
func parseOpusHead(_ head: [UInt8]) -> Result<(channels: Int, preSkip: Int, gain: Float), SurfaceError> {
    let magic: [UInt8] = Array("OpusHead".utf8)
    guard head.count >= 19, Array(head[0..<8]) == magic else {
        return .failure(SurfaceError("Opus track without an OpusHead header"))
    }
    let channels = Int(head[9])
    guard head[18] == 0 && (channels == 1 || channels == 2) else {
        return .failure(SurfaceError("Opus with \(channels) channels isn't supported (mono and stereo are)"))
    }
    let preSkip = Int(UInt16(head[10]) | (UInt16(head[11]) << 8))
    let gainRaw = Int16(bitPattern: UInt16(head[16]) | (UInt16(head[17]) << 8))
    let gainDb = Float(gainRaw) / 256.0
    #if !os(WASI)
    let linearGain = Float(pow(10.0, Double(gainDb) / 20.0))
    #else
    let linearGain: Float = 1.0 + gainDb * 0.11512925
    #endif
    return .success((channels, preSkip, linearGain))
}

/// The 44-byte header of a 16-bit PCM WAV holding `samples` interleaved samples.
func foreignWavHeader(rate: UInt32, channels: UInt16, samples: UInt64) -> Result<[UInt8], SurfaceError> {
    let (dataBytes64, mulOverflow) = samples.multipliedReportingOverflow(by: 2)
    if mulOverflow || dataBytes64 > UInt64(UInt32.max) {
        return .failure(SurfaceError(FOREIGN_TOO_LONG))
    }
    let data = UInt32(dataBytes64)
    let (riff, addOverflow) = data.addingReportingOverflow(36)
    if addOverflow {
        return .failure(SurfaceError(FOREIGN_TOO_LONG))
    }
    let (block, chOverflow) = channels.multipliedReportingOverflow(by: 2)
    if chOverflow || block == 0 {
        return .failure(SurfaceError("too many channels"))
    }
    let (byteRate, rateOverflow) = rate.multipliedReportingOverflow(by: UInt32(block))
    if rateOverflow {
        return .failure(SurfaceError("sample rate too high"))
    }

    var h = [UInt8]()
    h.reserveCapacity(44)
    func putU16(_ v: UInt16) {
        let le = v.littleEndian
        h.append(UInt8(truncatingIfNeeded: le))
        h.append(UInt8(truncatingIfNeeded: le >> 8))
    }
    func putU32(_ v: UInt32) {
        let le = v.littleEndian
        h.append(UInt8(truncatingIfNeeded: le))
        h.append(UInt8(truncatingIfNeeded: le >> 8))
        h.append(UInt8(truncatingIfNeeded: le >> 16))
        h.append(UInt8(truncatingIfNeeded: le >> 24))
    }

    h.append(contentsOf: "RIFF".utf8)
    putU32(riff)
    h.append(contentsOf: "WAVEfmt ".utf8)
    putU32(16)
    putU16(1)
    putU16(channels)
    putU32(rate)
    putU32(byteRate)
    putU16(block)
    putU16(16)
    h.append(contentsOf: "data".utf8)
    putU32(data)
    return .success(h)
}

#if !os(WASI)
private let wavCounterLock = LiveLock()
// PORT NOTE: Guarded by `wavCounterLock` for unique temporary WAV file names per process.
nonisolated(unsafe) private var nextWavId: UInt64 = 0

/// A decoded clip on disk for `AVPlayer`, removed when dropped.
final class ForeignWav: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var path: String {
        url.path
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes interleaved 16-bit PCM `samples` to a temporary WAV file and returns its RAII owner.
    static func writePCM(rate: UInt32, channels: UInt16, samples: [Int16]) -> Result<ForeignWav, SurfaceError> {
        if samples.isEmpty || channels == 0 {
            return .failure(SurfaceError("no audio decoded"))
        }
        if UInt64(samples.count) > FOREIGN_MAX_SAMPLES {
            return .failure(SurfaceError(FOREIGN_TOO_LONG))
        }
        switch foreignWavHeader(rate: rate, channels: channels, samples: UInt64(samples.count)) {
        case .failure(let err):
            return .failure(err)
        case .success(let hdr):
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-audio", isDirectory: true)
            let seq: UInt64 = wavCounterLock.withLock {
                let current = nextWavId
                nextWavId &+= 1
                return current
            }
            if seq == 0 {
                sweepOldWavFiles(in: dir)
            }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let fileURL = dir.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)-\(seq).wav")
                var bytes = [UInt8]()
                bytes.reserveCapacity(44 + samples.count * 2)
                bytes.append(contentsOf: hdr)
                for s in samples {
                    let le = UInt16(bitPattern: s).littleEndian
                    bytes.append(UInt8(truncatingIfNeeded: le))
                    bytes.append(UInt8(truncatingIfNeeded: le >> 8))
                }
                try Data(bytes).write(to: fileURL, options: .atomic)
                return .success(ForeignWav(url: fileURL))
            } catch {
                return .failure(SurfaceError("can't write decoded audio: \(error)"))
            }
        }
    }

    /// Attempts to decode compressed Ogg/WebM audio bytes.
    static func decode(_ bytes: [UInt8]) -> Result<ForeignWav, SurfaceError> {
        if !foreignSniff(bytes) {
            return .failure(SurfaceError("can't decode this audio: not an Ogg or WebM/EBML stream"))
        }
        // PORT NOTE: Software Ogg Vorbis / Opus decoding requires external `symphonia` + `opuscule` codecs,
        // which are omitted per Golden Rule 8 (no unapproved third-party dependencies).
        return .failure(SurfaceError("can't decode this audio: Ogg/WebM software decoder unavailable without ogg-audio codec dependency"))
    }
}

private func sweepOldWavFiles(in dir: URL) {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return }
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    for entry in entries {
        if let vals = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
           let mod = vals.contentModificationDate,
           mod < cutoff {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
#endif
