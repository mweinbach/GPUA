// Tests ported from: crates/rune/src/video/foreign.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

@Suite("Foreign Audio Container Sniffing and WAV Header Tests")
struct VideoForeignTests {
    @Test("sniffs Ogg and EBML only")
    func sniffsOggAndEbmlOnly() {
        #expect(foreignSniff(Array("OggS\u{00}".utf8)))
        #expect(foreignSniff([0x1a, 0x45, 0xdf, 0xa3, 0x9f]))
        #expect(!foreignSniff(Array("RIFF".utf8)))
        #expect(!foreignSniff(Array("\u{00}\u{00}\u{00}\u{1c}ftypM4A ".utf8)))
        #expect(!foreignSniff(Array("Ogg".utf8)))
        #expect(!foreignSniff([]))
    }

    @Test("WAV header caps at 32-bit RIFF")
    func wavHeaderCapsAtThirtyTwoBitRiff() {
        guard case .success(let h) = foreignWavHeader(rate: 48_000, channels: 2, samples: 96_000) else {
            Issue.record("expected valid WAV header")
            return
        }
        #expect(h.count == 44)
        #expect(Array(h[0..<4]) == Array("RIFF".utf8))
        #expect(Array(h[8..<16]) == Array("WAVEfmt ".utf8))
        #expect(Array(h[36..<40]) == Array("data".utf8))
        let dataBytes = h.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self).littleEndian }
        let riffBytes = h.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian }
        #expect(dataBytes == 192_000)
        #expect(riffBytes == 192_036)

        if case .failure = foreignWavHeader(rate: 48_000, channels: 2, samples: FOREIGN_MAX_SAMPLES) {
            Issue.record("expected FOREIGN_MAX_SAMPLES to succeed")
        }
        if case .success = foreignWavHeader(rate: 48_000, channels: 2, samples: FOREIGN_MAX_SAMPLES + 1) {
            Issue.record("expected FOREIGN_MAX_SAMPLES + 1 to fail")
        }
        if case .success = foreignWavHeader(rate: 48_000, channels: 2, samples: UInt64.max) {
            Issue.record("expected UInt64.max to fail")
        }
    }

    @Test("parseOpusHead validates channels, pre-skip and gain")
    func parseOpusHeadValidatesChannelsPreSkipAndGain() {
        var head = [UInt8](repeating: 0, count: 19)
        let magic = Array("OpusHead".utf8)
        head.replaceSubrange(0..<8, with: magic)
        head[8] = 1
        head[9] = 2      // stereo
        head[10] = 0x38  // pre-skip = 312 (0x0138 LE)
        head[11] = 0x01
        head[16] = 0x00  // 0 dB gain
        head[17] = 0x00
        head[18] = 0     // mapping family 0

        guard case .success(let parsed) = parseOpusHead(head) else {
            Issue.record("expected valid OpusHead")
            return
        }
        #expect(parsed.channels == 2)
        #expect(parsed.preSkip == 312)
        #expect(abs(parsed.gain - 1.0) < 1e-5)

        head[9] = 6 // 5.1 surround unsupported
        if case .success = parseOpusHead(head) {
            Issue.record("expected 6-channel OpusHead to fail")
        }
    }

    @Test("ForeignWav.writePCM writes valid WAV and removes temp file on deinit")
    func writePCMCreatesAndRemovesTempWav() {
        var tempPath = ""
        do {
            let samples = [Int16](repeating: 0, count: 480)
            guard case .success(let wav) = ForeignWav.writePCM(rate: 48_000, channels: 1, samples: samples) else {
                Issue.record("expected ForeignWav.writePCM to succeed")
                return
            }
            tempPath = wav.path
            #expect(FileManager.default.fileExists(atPath: tempPath))
            let bytes = (try? Data(contentsOf: wav.url)) ?? Data()
            #expect(bytes.count == 44 + 480 * 2)
        }
        #expect(!FileManager.default.fileExists(atPath: tempPath))
    }
}
