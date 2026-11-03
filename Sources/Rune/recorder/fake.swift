// Ported from: crates/rune/src/recorder/fake.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The fake microphone headless runs record from, and the WAV files it reads and writes.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(CRT)
import CRT
#endif

#if !os(WASI)
import Foundation
#endif

private let FAKE_MIC_RATE: UInt32 = 48_000

private enum FakeSignal: Sendable {
    case swell
    case silence
    case sine(hz: Float, amplitude: Float)
    case samples(rate: UInt32, samples: [Float])
    case wav(String)
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; stores the thread-installed `FakeMicrophone`.
nonisolated(unsafe) private var installedFakeMicrophoneWasi: FakeMicrophone? = nil
#else
private let fakeMicThreadKey = "gpua.rune.fakeMicrophone"
private final class FakeMicThreadBox {
    var mic: FakeMicrophone?
    init(_ mic: FakeMicrophone?) { self.mic = mic }
}
#endif

/// A microphone for headless runs and tests: recorders started where no window has run (and
/// any recorder given one with `Recorder.fake`) record from it instead of a device.
public struct FakeMicrophone: Sendable {
    private var signal: FakeSignal
    var permissionValue: MicPermission
    var answerValue: MicPermission
    var unplugSeconds: Double?

    private init(signal: FakeSignal) {
        self.signal = signal
        self.permissionValue = .granted
        self.answerValue = .granted
        self.unplugSeconds = nil
    }

    /// A 220 Hz tone whose amplitude swells from silence to 0.3 and back every 1.6 s.
    public init() {
        self.init(signal: .swell)
    }

    public static func `default`() -> FakeMicrophone {
        FakeMicrophone()
    }

    /// Digital silence.
    public static func silence() -> FakeMicrophone {
        FakeMicrophone(signal: .silence)
    }

    /// A steady sine at `hz` with peak `amplitude` (1 is full scale), sampled at 48 kHz.
    public static func sine(_ hz: Float, _ amplitude: Float) -> FakeMicrophone {
        FakeMicrophone(signal: .sine(hz: hz, amplitude: amplitude))
    }

    /// Mono samples at `rate` Hz (-1 to 1).
    public static func samples(_ rate: UInt32, _ samples: [Float]) -> FakeMicrophone {
        FakeMicrophone(signal: .samples(rate: max(rate, 1), samples: samples))
    }

    /// A WAV file (8, 16, 24 or 32-bit PCM, or 32-bit float), mixed to mono, read when a
    /// recording starts.
    public static func wav(_ path: String) -> FakeMicrophone {
        FakeMicrophone(signal: .wav(path))
    }

    #if !os(WASI)
    public static func wav(_ url: URL) -> FakeMicrophone {
        FakeMicrophone(signal: .wav(url.path))
    }
    #endif

    /// What `Recorder.permission` reports (default `.granted`).
    public func permission(_ permission: MicPermission) -> FakeMicrophone {
        var copy = self
        copy.permissionValue = permission
        return copy
    }

    /// How a permission request resolves while the permission is `.undetermined` (default `.granted`).
    public func answers(_ answer: MicPermission) -> FakeMicrophone {
        var copy = self
        copy.answerValue = answer
        return copy
    }

    /// The microphone goes away after `seconds` of recording, as when a headset is unplugged.
    public func unplugAfter(_ seconds: Double) -> FakeMicrophone {
        var copy = self
        copy.unplugSeconds = max(seconds, 0.0)
        return copy
    }

    /// Recorders started on this thread while no window has run hear this microphone.
    public func install() {
        #if os(WASI)
        installedFakeMicrophoneWasi = self
        #else
        Thread.current.threadDictionary[fakeMicThreadKey] = FakeMicThreadBox(self)
        #endif
    }

    /// Back to `FakeMicrophone()` on this thread.
    public static func uninstall() {
        #if os(WASI)
        installedFakeMicrophoneWasi = nil
        #else
        Thread.current.threadDictionary.removeObject(forKey: fakeMicThreadKey)
        #endif
    }

    static func installed() -> FakeMicrophone {
        #if os(WASI)
        return installedFakeMicrophoneWasi ?? FakeMicrophone()
        #else
        if let box = Thread.current.threadDictionary[fakeMicThreadKey] as? FakeMicThreadBox,
           let mic = box.mic
        {
            return mic
        }
        return FakeMicrophone()
        #endif
    }

    static func requestInstalled() -> MicPermission {
        #if os(WASI)
        var mic = installedFakeMicrophoneWasi ?? FakeMicrophone()
        let resolved = mic.resolve()
        installedFakeMicrophoneWasi = mic
        return resolved
        #else
        if let box = Thread.current.threadDictionary[fakeMicThreadKey] as? FakeMicThreadBox,
           var mic = box.mic
        {
            let resolved = mic.resolve()
            box.mic = mic
            return resolved
        }
        var fresh = FakeMicrophone()
        let resolved = fresh.resolve()
        Thread.current.threadDictionary[fakeMicThreadKey] = FakeMicThreadBox(fresh)
        return resolved
        #endif
    }

    mutating func resolve() -> MicPermission {
        if permissionValue == .undetermined {
            permissionValue = answerValue
        }
        return permissionValue
    }

    func open() -> Result<FakeMicInput, RecorderError> {
        switch signal {
        case .swell:
            return .success(FakeMicInput(rate: FAKE_MIC_RATE, kind: .swell))
        case .silence:
            return .success(FakeMicInput(rate: FAKE_MIC_RATE, kind: .silence))
        case .sine(let hz, let amplitude):
            return .success(FakeMicInput(rate: FAKE_MIC_RATE, kind: .sine(hz: Double(hz), amplitude: Double(amplitude))))
        case .samples(let rate, let samples):
            return .success(FakeMicInput(rate: rate, kind: .samples(samples)))
        case .wav(let path):
            return readWavFile(path).map { rate, samples in
                FakeMicInput(rate: rate, kind: .samples(samples))
            }
        }
    }
}

enum FakeInputKind: Sendable {
    case swell
    case silence
    case sine(hz: Double, amplitude: Double)
    case samples([Float])
}

struct FakeMicInput: Sendable {
    var rate: UInt32
    var kind: FakeInputKind

    func sample(_ i: UInt64) -> Float {
        let t = Double(i) / Double(rate)
        let tau = 2.0 * Double.pi
        switch kind {
        case .silence:
            return 0.0
        case .sine(let hz, let amplitude):
            return Float(amplitude * sin(tau * hz * t))
        case .swell:
            return Float(0.3 * (0.5 - 0.5 * cos(tau * t / 1.6)) * sin(tau * 220.0 * t))
        case .samples(let s):
            if s.isEmpty { return 0.0 }
            return s[Int(i % UInt64(s.count))]
        }
    }
}

/// Writes the first `frames` samples of `input` to a 16-bit mono WAV.
func writeFakeWav(_ path: String, _ input: FakeMicInput, _ frames: UInt64) -> Result<Void, RecorderError> {
    #if os(WASI)
    _ = (path, input, frames)
    return .failure(RecorderError("recording files are unavailable on WASI"))
    #else
    let maxBytes = UInt64(UInt32.max) - 36
    let (byteCount, overflow) = frames.multipliedReportingOverflow(by: 2)
    guard !overflow && byteCount <= maxBytes else {
        return .failure(RecorderError("the recording is too long for a WAV file"))
    }
    var out: [UInt8] = []
    out.reserveCapacity(44 + Int(byteCount))
    out.append(contentsOf: makeWavHeader(input.rate, UInt32(byteCount)))
    for i in 0..<frames {
        let clamped = min(max(input.sample(i), -1.0), 1.0)
        let pcm = Int16((clamped * 32767.0).rounded())
        let le = UInt16(bitPattern: pcm).littleEndian
        out.append(UInt8(truncatingIfNeeded: le))
        out.append(UInt8(truncatingIfNeeded: le >> 8))
    }
    do {
        try Data(out).write(to: URL(fileURLWithPath: path))
        return .success(())
    } catch {
        return .failure(RecorderError("couldn't write \(path): \(error.localizedDescription)"))
    }
    #endif
}

private func makeWavHeader(_ rate: UInt32, _ dataBytes: UInt32) -> [UInt8] {
    var h = [UInt8](repeating: 0, count: 44)
    func put(_ at: Int, _ bytes: [UInt8]) {
        for (idx, b) in bytes.enumerated() {
            h[at + idx] = b
        }
    }
    func le16(_ v: UInt16) -> [UInt8] {
        let le = v.littleEndian
        return [UInt8(truncatingIfNeeded: le), UInt8(truncatingIfNeeded: le >> 8)]
    }
    func le32(_ v: UInt32) -> [UInt8] {
        let le = v.littleEndian
        return [
            UInt8(truncatingIfNeeded: le),
            UInt8(truncatingIfNeeded: le >> 8),
            UInt8(truncatingIfNeeded: le >> 16),
            UInt8(truncatingIfNeeded: le >> 24),
        ]
    }
    put(0, Array("RIFF".utf8))
    put(4, le32(36 &+ dataBytes))
    put(8, Array("WAVEfmt ".utf8))
    put(16, le32(16))
    put(20, le16(1)) // PCM
    put(22, le16(1)) // mono
    put(24, le32(rate))
    put(28, le32(rate &* 2))
    put(32, le16(2))
    put(34, le16(16))
    put(36, Array("data".utf8))
    put(40, le32(dataBytes))
    return h
}

/// Reads a PCM or float WAV, mixed to mono: `(sampleRate, samples)`.
func readWavFile(_ path: String) -> Result<(UInt32, [Float]), RecorderError> {
    #if os(WASI)
    return .failure(RecorderError("couldn't read \(path): unsupported on WASI"))
    #else
    let bytes: [UInt8]
    do {
        bytes = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        return .failure(RecorderError("couldn't read \(path): \(error.localizedDescription)"))
    }
    switch parseWavBytes(bytes) {
    case .success(let pair):
        return .success(pair)
    case .failure(let err):
        return .failure(RecorderError("\(path): \(err.message)"))
    }
    #endif
}

func parseWavBytes(_ b: [UInt8]) -> Result<(UInt32, [Float]), RecorderError> {
    guard b.count >= 12,
          Array(b[0..<4]) == Array("RIFF".utf8),
          Array(b[8..<12]) == Array("WAVE".utf8)
    else {
        return .failure(RecorderError("not a WAV file"))
    }
    func u16At(_ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }
    func u32At(_ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    var fmtStart: Int? = nil
    var dataRange: Range<Int>? = nil
    var at = 12
    while at + 8 <= b.count {
        let chunkId = Array(b[at..<(at + 4)])
        let len = Int(u32At(at + 4))
        let start = at + 8
        let end = min(start + max(0, len), b.count)
        if chunkId == Array("fmt ".utf8), end - start >= 16 {
            fmtStart = start
        } else if chunkId == Array("data".utf8) {
            dataRange = start..<end
        }
        let pad = len & 1
        let next = end + pad
        if next <= at { break }
        at = next
    }

    guard let f = fmtStart, let data = dataRange else {
        return .failure(RecorderError("no fmt or data chunk"))
    }
    var format = u16At(f)
    if format == 0xFFFE && f + 26 <= b.count {
        format = u16At(f + 24)
    }
    let channels = Int(u16At(f + 2))
    let rate = u32At(f + 4)
    let bits = u16At(f + 14)
    let width = Int(bits) / 8
    if channels == 0 || rate == 0 || width == 0 {
        return .failure(RecorderError("invalid fmt chunk"))
    }

    let decodeSample: (ArraySlice<UInt8>) -> Float
    switch (format, bits) {
    case (1, 8):
        decodeSample = { s in (Float(s[s.startIndex]) - 128.0) / 128.0 }
    case (1, 16):
        decodeSample = { s in
            let i0 = s.startIndex
            let u = UInt16(s[i0]) | (UInt16(s[i0 + 1]) << 8)
            return Float(Int16(bitPattern: u)) / 32768.0
        }
    case (1, 24):
        decodeSample = { s in
            let i0 = s.startIndex
            let u = (UInt32(s[i0]) << 8) | (UInt32(s[i0 + 1]) << 16) | (UInt32(s[i0 + 2]) << 24)
            return Float(Int32(bitPattern: u) >> 8) / 8_388_608.0
        }
    case (1, 32):
        decodeSample = { s in
            let i0 = s.startIndex
            let u = UInt32(s[i0]) | (UInt32(s[i0 + 1]) << 8) | (UInt32(s[i0 + 2]) << 16) | (UInt32(s[i0 + 3]) << 24)
            return Float(Int32(bitPattern: u)) / 2_147_483_648.0
        }
    case (3, 32):
        decodeSample = { s in
            let i0 = s.startIndex
            let u = UInt32(s[i0]) | (UInt32(s[i0 + 1]) << 8) | (UInt32(s[i0 + 2]) << 16) | (UInt32(s[i0 + 3]) << 24)
            return Float(bitPattern: u)
        }
    default:
        return .failure(RecorderError("unsupported WAV sample format (use PCM or 32-bit float)"))
    }

    let frameWidth = width * channels
    let frameCount = data.count / frameWidth
    var samples: [Float] = []
    samples.reserveCapacity(frameCount)
    var pos = data.lowerBound
    for _ in 0..<frameCount {
        var sum: Float = 0.0
        for ch in 0..<channels {
            let chStart = pos + ch * width
            sum += decodeSample(b[chStart..<(chStart + width)])
        }
        samples.append(sum / Float(channels))
        pos += frameWidth
    }
    return .success((rate, samples))
}
