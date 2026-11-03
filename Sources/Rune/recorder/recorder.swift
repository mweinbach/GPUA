// Ported from: crates/rune/src/recorder/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Audio recording: a cheap, cloneable `Recorder` handle that records the microphone to a
//! file, with elapsed time and a smoothed input level to draw.

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

/// The file format a recorder writes.
public enum RecordFormat: Sendable, Equatable {
    /// AAC in an MPEG-4 container (`.m4a`), high quality: about 1 MB a minute, mono.
    case aac
    /// 16-bit PCM WAV: about 5 MB a minute at 44.1 kHz mono.
    case wav
}

/// Where a recorder is.
public enum RecorderState: Sendable, Equatable {
    /// Not started, or cancelled.
    case idle
    /// Asking for permission or opening the input.
    case starting
    case recording
    case paused
    /// Stopped with the file written.
    case stopped
    /// The input went away mid-recording. What was captured is saved; `stop` returns it and `cancel` deletes it.
    case interrupted(String)
    /// Couldn't record: no permission, no input, an unwritable path, or an unsupported platform.
    case failed(String)
}

/// Microphone access, as the system reports it.
public enum MicPermission: Sendable, Equatable {
    case granted
    case denied
    case undetermined
    case restricted
}

/// Error returned by `Recorder.stop()` when not recording or when writing fails.
public struct RecorderError: Error, CustomStringConvertible, Sendable, Equatable, ExpressibleByStringLiteral {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public init(stringLiteral value: String) {
        self.message = value
    }

    public var description: String { message }
}

/// A finished recording.
public struct Recording: Sendable, Equatable {
    /// Path of the written audio file.
    public var path: String
    /// Seconds of audio, pauses excluded.
    public var duration: Double

    public init(path: String, duration: Double) {
        self.path = path
        self.duration = duration
    }
}

struct RecorderOptions: Sendable {
    var format: RecordFormat
    var sampleRate: UInt32
    var channels: UInt16
    var fake: FakeMicrophone?
}

private let RECORDER_DENIED_MSG = "microphone access is denied: allow it in System Settings > Privacy & Security > Microphone"
private let RECORDER_RESTRICTED_MSG = "microphone access is restricted on this device"
private let RECORDER_CLOCK_SLACK: Double = 1e-9

private func recorderDenial(_ answer: MicPermission) -> String {
    answer == .restricted ? RECORDER_RESTRICTED_MSG : RECORDER_DENIED_MSG
}

// MARK: - Windowed vs Headless Clock Coordination

private let recorderDeviceLock = LiveLock()
// PORT NOTE: Protected by `recorderDeviceLock`; toggled when the windowed shell starts its event loop.
nonisolated(unsafe) private var recorderWindowPlaybackEnabled: Bool = false

func enableRecorderDeviceMode() {
    recorderDeviceLock.withLock { recorderWindowPlaybackEnabled = true }
}

func recorderUsesDevices() -> Bool {
    #if os(WASI)
    return true
    #else
    return recorderDeviceLock.withLock { recorderWindowPlaybackEnabled }
    #endif
}

private let recorderOriginInstant = RuneInstant.now()
private func recorderWallNow() -> Double {
    recorderOriginInstant.elapsedSeconds()
}

#if !os(WASI)
private let recorderHeadlessKey = "gpua.rune.recorderHeadless"
final class WeakRecorderShared {
    weak var value: RecorderShared?
    init(_ value: RecorderShared) { self.value = value }
}
final class RecorderHeadlessThreadBox {
    var clock: Double? = nil
    var recorders: [WeakRecorderShared] = []
}
private func currentRecorderHeadlessBox() -> RecorderHeadlessThreadBox {
    if let existing = Thread.current.threadDictionary[recorderHeadlessKey] as? RecorderHeadlessThreadBox {
        return existing
    }
    let fresh = RecorderHeadlessThreadBox()
    Thread.current.threadDictionary[recorderHeadlessKey] = fresh
    return fresh
}
#endif

func recorderHeadlessClock() -> Double? {
    #if os(WASI)
    return nil
    #else
    guard let box = Thread.current.threadDictionary[recorderHeadlessKey] as? RecorderHeadlessThreadBox else {
        return nil
    }
    return box.clock
    #endif
}

/// A headless runtime starts a frame at `clock`: fake recorders started on this thread catch up.
func hostRecorderHeadlessFrame(_ clock: Double) {
    #if !os(WASI)
    let box = currentRecorderHeadlessBox()
    box.clock = clock
    box.recorders.removeAll { $0.value == nil }
    let active = box.recorders.compactMap(\.value)
    for r in active {
        r.follow()
    }
    #endif
}

/// A new runtime on this thread starts its clock at 0: fake recordings keep their elapsed time and go on from there.
func hostRecorderHeadlessReset() {
    #if !os(WASI)
    let box = currentRecorderHeadlessBox()
    let active = box.recorders.compactMap(\.value)
    for r in active {
        r.ctlLock.withLock {
            r.ctl.advance()
            if r.ctl.anchor != nil {
                r.ctl.anchor = (0.0, r.ctl.elapsed)
            }
        }
    }
    box.clock = 0.0
    #endif
}

func recorderHeadlessFollowedCount(for shared: RecorderShared) -> Int {
    #if os(WASI)
    _ = shared
    return 0
    #else
    guard let box = Thread.current.threadDictionary[recorderHeadlessKey] as? RecorderHeadlessThreadBox else {
        return 0
    }
    return box.recorders.filter { $0.value === shared }.count
    #endif
}

// MARK: - Recorder Control & Shared State

struct FakeRecorderSession {
    var input: FakeMicInput
    var path: String
    var meter: AudioMeter
    var metered: UInt64
    var unplug: Double?
}

struct RecorderControl {
    var state: RecorderState = .idle
    var generation: UInt64 = 0
    var attempt: UInt64 = 0
    var elapsed: Double = 0.0
    var anchor: (Double, Double)? = nil
    var virtualClock: Bool = false
    var fake: FakeRecorderSession? = nil
    var saved: Recording? = nil
    var path: String

    mutating func set(_ newState: RecorderState) {
        if state != newState {
            state = newState
            generation &+= 1
        }
    }

    func now() -> Double? {
        virtualClock ? recorderHeadlessClock() : recorderWallNow()
    }

    mutating func advance() {
        guard state == .recording, let current = now() else { return }
        if let (clock, prevElapsed) = anchor, clock <= current {
            elapsed = prevElapsed + (current - clock)
        } else {
            anchor = (current, elapsed)
        }
    }
}

func packRecorderLevel(_ level: Level) -> UInt64 {
    (UInt64(level.peakDb().bitPattern) << 32) | UInt64(level.rmsDb().bitPattern)
}

func unpackRecorderLevel(_ bits: UInt64) -> Level {
    let peak = Float(bitPattern: UInt32(truncatingIfNeeded: bits >> 32))
    let rms = Float(bitPattern: UInt32(truncatingIfNeeded: bits))
    return Level.new(peak, rms)
}

private func recorderFramesAt(_ seconds: Double, _ rate: UInt32) -> UInt64 {
    let raw = floor((seconds + RECORDER_CLOCK_SLACK) * Double(rate))
    return raw > 0.0 ? UInt64(raw) : 0
}

func withRecorderFormatExtension(_ path: String, _ format: RecordFormat) -> String {
    let lastSlash = path.lastIndex(of: "/") ?? path.lastIndex(of: "\\")
    let fileStart = lastSlash.map { path.index(after: $0) } ?? path.startIndex
    let filename = path[fileStart...]
    let dotIndex: String.Index? = {
        guard let dot = filename.lastIndex(of: "."), dot > filename.startIndex else { return nil }
        return dot
    }()
    let extLower: String? = dotIndex.map { String(filename[filename.index(after: $0)...]).lowercased() }
    let (keep, want): ([String], String) = {
        switch format {
        case .aac: return (["m4a", "mp4"], "m4a")
        case .wav: return (["wav"], "wav")
        }
    }()
    if let extLower, keep.contains(extLower) {
        return path
    }
    if let dot = dotIndex {
        return String(path[..<dot]) + "." + want
    }
    return path + "." + want
}

// PORT NOTE: Synchronized via `optsLock`, `ctlLock`, `levelLock`, `wakerLock`, and `nativeLock` (`LiveLock`), mirroring `Arc<Shared>` in `crates/rune/src/recorder/mod.rs`.
final class RecorderShared: @unchecked Sendable {
    let basePath: String
    let optsLock = LiveLock()
    var opts: RecorderOptions
    let ctlLock = LiveLock()
    var ctl: RecorderControl
    private let levelLock = LiveLock()
    private var packedLevel: UInt64
    private var fakedFlag: Bool = false
    let live: Live<Float>
    private let wakerLock = LiveLock()
    private var wakerEntry: (Waker, UInt64)? = nil
    let nativeLock = LiveLock()
    var nativeSession: (UInt64, RecorderBackendSession)? = nil

    init(path: String, opts: RecorderOptions) {
        self.basePath = path
        self.opts = opts
        self.ctl = RecorderControl(path: path)
        self.packedLevel = packRecorderLevel(.SILENT)
        self.live = Live.new(0.0)
    }

    var isFaked: Bool {
        get { levelLock.withLock { fakedFlag } }
        set { levelLock.withLock { fakedFlag = newValue } }
    }

    func loadPackedLevel() -> UInt64 {
        levelLock.withLock { packedLevel }
    }

    func publish(_ level: Level) {
        let bits = packRecorderLevel(level)
        levelLock.withLock { packedLevel = bits }
        _ = live.set(level.meter())
    }

    func fakeMic() -> FakeMicrophone? {
        let own = optsLock.withLock { opts.fake }
        if let own { return own }
        return recorderUsesDevices() ? nil : FakeMicrophone.installed()
    }

    func resolveFakePermission() -> MicPermission {
        optsLock.withLock {
            if var own = opts.fake {
                let ans = own.resolve()
                opts.fake = own
                return ans
            }
            return FakeMicrophone.requestInstalled()
        }
    }

    func withFollowingControl<R>(_ body: (inout RecorderControl) -> R) -> R {
        let hasFake = ctlLock.withLock { ctl.fake != nil }
        if hasFake {
            follow()
        }
        return ctlLock.withLock {
            ctl.advance()
            return body(&ctl)
        }
    }

    func settle() {
        let gen = ctlLock.withLock { ctl.generation }
        let toWake: Waker? = wakerLock.withLock {
            guard var entry = wakerEntry, entry.1 != gen else { return nil }
            entry.1 = gen
            wakerEntry = entry
            return entry.0
        }
        toWake?()
    }

    func setWaker(_ waker: @escaping Waker) {
        wakerLock.withLock { wakerEntry = (waker, 0) }
        settle()
    }

    func fail(_ attempt: UInt64, _ error: String) {
        ctlLock.withLock {
            if ctl.attempt == attempt && ctl.state == .starting {
                ctl.set(.failed(error))
            }
        }
    }

    func launch(_ attempt: UInt64, _ fake: FakeMicrophone?) {
        let currentAttempt = ctlLock.withLock { ctl.attempt }
        guard currentAttempt == attempt else { return }
        if let mic = fake {
            launchFake(attempt, mic)
        } else {
            let currentOpts = optsLock.withLock { opts }
            let path = ctlLock.withLock { ctl.path }
            nativeLock.withLock {
                switch recorderBackendStart(self, attempt, path, currentOpts) {
                case .success(let session):
                    nativeSession = (attempt, session)
                case .failure(let err):
                    fail(attempt, err.message)
                }
            }
        }
    }

    private func launchFake(_ attempt: UInt64, _ mic: FakeMicrophone) {
        let path = ctlLock.withLock { ctl.path }
        let opened: Result<FakeMicInput, RecorderError> = mic.open().flatMap { input in
            writeFakeWav(path, input, 0).map { input }
        }
        ctlLock.withLock {
            guard ctl.attempt == attempt && ctl.state == .starting else { return }
            switch opened {
            case .success(let input):
                ctl.fake = FakeRecorderSession(
                    input: input,
                    path: path,
                    meter: AudioMeter(),
                    metered: 0,
                    unplug: mic.unplugSeconds
                )
                isFaked = true
                ctl.anchor = ctl.now().map { ($0, 0.0) }
                ctl.set(.recording)
                #if !os(WASI)
                if ctl.virtualClock {
                    let box = currentRecorderHeadlessBox()
                    box.recorders.removeAll { $0.value == nil }
                    if !box.recorders.contains(where: { $0.value === self }) {
                        box.recorders.append(WeakRecorderShared(self))
                    }
                }
                #endif
            case .failure(let err):
                ctl.set(.failed(err.message))
            }
        }
    }

    func follow() {
        var didInterrupt = false
        var computedLevel: Level? = nil
        ctlLock.withLock {
            ctl.advance()
            guard ctl.state == .recording else { return }
            let elapsed = ctl.elapsed
            guard var f = ctl.fake else { return }
            if let unplug = f.unplug, elapsed + RECORDER_CLOCK_SLACK >= unplug {
                ctl.elapsed = unplug
                ctl.anchor = nil
                ctl.fake = nil
                let frames = recorderFramesAt(unplug, f.input.rate)
                switch writeFakeWav(f.path, f.input, frames) {
                case .success:
                    ctl.saved = Recording(path: f.path, duration: Double(frames) / Double(f.input.rate))
                    ctl.set(.interrupted("the microphone went away"))
                case .failure(let err):
                    ctl.set(.failed(err.message))
                }
                didInterrupt = true
                return
            }
            let input = f.input
            let rate = input.rate
            let target = recorderFramesAt(elapsed, rate)
            let block = UInt64(max(rate / 100, 1))
            let tenSec = 10 * UInt64(rate)
            let floorMetered = target > tenSec ? ((target - tenSec) / block) * block : 0
            f.metered = max(f.metered, floorMetered)
            while f.metered + block <= target {
                let start = f.metered
                let end = start + block
                f.meter.pushSamples((start..<end).lazy.map { input.sample($0) }, rate)
                f.metered = end
            }
            computedLevel = f.meter.level()
            ctl.fake = f
        }
        if didInterrupt {
            publish(.SILENT)
            settle()
        } else if let level = computedLevel {
            publish(level)
        }
    }

    func stop() -> Result<Recording, RecorderError> {
        let hasFake = ctlLock.withLock { ctl.fake != nil }
        if hasFake {
            follow()
        }

        enum StopAction {
            case immediate(Result<Recording, RecorderError>)
            case cancelStarting
            case finishFake(FakeRecorderSession, Double)
            case finishNative(String)
        }

        let action: StopAction = ctlLock.withLock {
            ctl.advance()
            switch ctl.state {
            case .recording, .paused:
                ctl.anchor = nil
                if let f = ctl.fake {
                    ctl.fake = nil
                    return .finishFake(f, ctl.elapsed)
                }
                return .finishNative(ctl.path)
            case .interrupted:
                if let saved = ctl.saved {
                    ctl.saved = nil
                    ctl.set(.stopped)
                    return .immediate(.success(saved))
                }
                return .immediate(.failure(RecorderError("the interrupted recording wasn't saved")))
            case .starting:
                ctl.attempt &+= 1
                ctl.set(.idle)
                return .cancelStarting
            case .failed(let e):
                return .immediate(.failure(RecorderError(e)))
            case .idle, .stopped:
                return .immediate(.failure(RecorderError("not recording")))
            }
        }

        switch action {
        case .immediate(let res):
            return res
        case .cancelStarting:
            let taken = nativeLock.withLock { () -> RecorderBackendSession? in
                let s = nativeSession?.1
                nativeSession = nil
                return s
            }
            if let s = taken {
                recorderBackendCancel(s)
            }
            return .failure(RecorderError("stopped before recording started"))
        case .finishFake(let f, let elapsed):
            let frames = recorderFramesAt(elapsed, f.input.rate)
            let result = writeFakeWav(f.path, f.input, frames).map {
                Recording(path: f.path, duration: Double(frames) / Double(f.input.rate))
            }
            ctlLock.withLock {
                switch result {
                case .success: ctl.set(.stopped)
                case .failure(let e): ctl.set(.failed(e.message))
                }
            }
            publish(.SILENT)
            return result
        case .finishNative(let path):
            let taken = nativeLock.withLock { () -> RecorderBackendSession? in
                let s = nativeSession?.1
                nativeSession = nil
                return s
            }
            let stopped: Result<Recording, RecorderError>
            if let s = taken {
                stopped = recorderBackendStop(s).map { Recording(path: path, duration: $0) }
            } else {
                stopped = .failure(RecorderError("not recording"))
            }
            let finalResult: Result<Recording, RecorderError> = ctlLock.withLock {
                if case .interrupted = ctl.state, let saved = ctl.saved {
                    ctl.saved = nil
                    ctl.set(.stopped)
                    return .success(saved)
                }
                switch stopped {
                case .success: ctl.set(.stopped)
                case .failure(let e): ctl.set(.failed(e.message))
                }
                return stopped
            }
            publish(.SILENT)
            return finalResult
        }
    }

    func began(_ attempt: UInt64) {
        ctlLock.withLock {
            guard ctl.attempt == attempt && ctl.state == .starting else { return }
            ctl.anchor = (recorderWallNow(), 0.0)
            ctl.set(.recording)
        }
        settle()
    }

    func beganFailure(_ attempt: UInt64, _ error: String) {
        fail(attempt, error)
        _ = nativeLock.withLock { () -> RecorderBackendSession? in
            if nativeSession?.0 == attempt {
                let s = nativeSession?.1
                nativeSession = nil
                return s
            }
            return nil
        }
        settle()
    }

    func interrupted(_ attempt: UInt64, _ reason: String, _ duration: Double) {
        ctlLock.withLock {
            guard ctl.attempt == attempt && (ctl.state == .recording || ctl.state == .paused) else { return }
            ctl.advance()
            ctl.anchor = nil
            ctl.saved = Recording(path: ctl.path, duration: duration)
            ctl.set(.interrupted(reason))
        }
        publish(.SILENT)
        settle()
    }

    func metered(_ attempt: UInt64, _ level: Level) {
        let shouldPublish = ctlLock.withLock {
            ctl.attempt == attempt && ctl.state == .recording
        }
        if shouldPublish {
            publish(level)
        }
    }

    deinit {
        ctl.advance()
        if let f = ctl.fake, ctl.state == .recording || ctl.state == .paused {
            ctl.fake = nil
            let elapsed = f.unplug.map { min(ctl.elapsed, $0) } ?? ctl.elapsed
            _ = writeFakeWav(f.path, f.input, recorderFramesAt(elapsed, f.input.rate))
        }
        if let (_, session) = nativeSession {
            nativeSession = nil
            recorderBackendFinish(session)
        }
    }
}

/// Records the microphone to a file. Copies share one recorder; dropping the last copy while
/// recording stops it and keeps the file.
public struct Recorder: Sendable, CustomDebugStringConvertible {
    public static let METER_INTERVAL: Duration = .milliseconds(33)

    let shared: RecorderShared

    /// A recorder writing `path`: WAV when it ends in `.wav`, otherwise AAC, at 44.1 kHz mono.
    public static func toFile(_ path: String) -> Recorder {
        let lower = path.lowercased()
        let isWav = lower.hasSuffix(".wav")
        let format: RecordFormat = isWav ? .wav : .aac
        let opts = RecorderOptions(format: format, sampleRate: 44_100, channels: 1, fake: nil)
        return Recorder(shared: RecorderShared(path: path, opts: opts))
    }

    #if !os(WASI)
    public static func toFile(_ url: URL) -> Recorder {
        toFile(url.path)
    }
    #endif

    public func format(_ format: RecordFormat) -> Recorder {
        shared.optsLock.withLock { shared.opts.format = format }
        return self
    }

    public func sampleRate(_ hz: UInt32) -> Recorder {
        shared.optsLock.withLock { shared.opts.sampleRate = min(max(hz, 8_000), 192_000) }
        return self
    }

    public func channels(_ channels: UInt16) -> Recorder {
        shared.optsLock.withLock { shared.opts.channels = min(max(channels, 1), 2) }
        return self
    }

    public func fake(_ mic: FakeMicrophone) -> Recorder {
        shared.optsLock.withLock { shared.opts.fake = mic }
        return self
    }

    public func path() -> String {
        let fmt = shared.optsLock.withLock { shared.opts.format }
        return withRecorderFormatExtension(shared.basePath, fmt)
    }

    public static func permission() -> MicPermission {
        recorderUsesDevices() ? recorderBackendPermission() : FakeMicrophone.installed().permissionValue
    }

    public static func requestPermission(_ callback: @escaping @Sendable (MicPermission) -> Void) {
        if recorderUsesDevices() {
            recorderBackendRequestPermission(callback)
        } else {
            callback(FakeMicrophone.requestInstalled())
        }
    }

    public func start() {
        let fake = shared.fakeMic()
        let attemptOpt: UInt64? = shared.ctlLock.withLock {
            switch shared.ctl.state {
            case .starting, .recording, .paused:
                return nil
            default:
                break
            }
            shared.ctl.attempt &+= 1
            shared.ctl.elapsed = 0.0
            shared.ctl.anchor = nil
            shared.ctl.fake = nil
            shared.isFaked = false
            shared.ctl.saved = nil
            let fmt = fake != nil ? .wav : shared.optsLock.withLock { shared.opts.format }
            shared.ctl.path = withRecorderFormatExtension(shared.basePath, fmt)
            shared.ctl.virtualClock = (fake != nil && !recorderUsesDevices())
            shared.ctl.set(.starting)
            return shared.ctl.attempt
        }
        guard let attempt = attemptOpt else { return }
        shared.publish(.SILENT)

        if fake == nil, case .failure(let err) = recorderBackendPreflight() {
            shared.fail(attempt, err.message)
            shared.settle()
            return
        }

        let perm = fake?.permissionValue ?? recorderBackendPermission()
        switch perm {
        case .granted:
            shared.launch(attempt, fake)
        case .denied:
            shared.fail(attempt, RECORDER_DENIED_MSG)
        case .restricted:
            shared.fail(attempt, RECORDER_RESTRICTED_MSG)
        case .undetermined:
            if fake != nil {
                let answer = shared.resolveFakePermission()
                if answer == .granted {
                    shared.launch(attempt, shared.fakeMic())
                } else {
                    shared.fail(attempt, recorderDenial(answer))
                }
            } else {
                recorderBackendRequestPermission { [weak shared] answer in
                    guard let strong = shared else { return }
                    if answer == .granted {
                        strong.launch(attempt, nil)
                    } else {
                        strong.fail(attempt, recorderDenial(answer))
                    }
                    strong.settle()
                }
            }
        }
        shared.settle()
    }

    public func pause() {
        let didPause: Bool = shared.withFollowingControl { c in
            guard c.state == .recording else { return false }
            c.anchor = nil
            c.set(.paused)
            return true
        }
        guard didPause else { return }
        shared.publish(.SILENT)
        shared.nativeLock.withLock {
            if let (_, s) = shared.nativeSession {
                recorderBackendPause(s)
            }
        }
        shared.settle()
    }

    public func resume() {
        let didResume: Bool = shared.ctlLock.withLock {
            guard shared.ctl.state == .paused else { return false }
            shared.ctl.anchor = shared.ctl.now().map { ($0, shared.ctl.elapsed) }
            shared.ctl.set(.recording)
            return true
        }
        guard didResume else { return }
        shared.nativeLock.withLock {
            if let (_, s) = shared.nativeSession {
                recorderBackendResume(s)
            }
        }
        shared.settle()
    }

    public func stop() -> Result<Recording, RecorderError> {
        let res = shared.stop()
        shared.settle()
        return res
    }

    public func cancel() {
        let pathToDelete: (Bool, String?) = shared.ctlLock.withLock {
            switch shared.ctl.state {
            case .starting, .recording, .paused, .interrupted:
                break
            default:
                return (false, nil)
            }
            shared.ctl.attempt &+= 1
            shared.ctl.anchor = nil
            shared.ctl.set(.idle)
            let p: String?
            if let f = shared.ctl.fake {
                shared.ctl.fake = nil
                p = f.path
            } else if let s = shared.ctl.saved {
                shared.ctl.saved = nil
                p = s.path
            } else {
                p = nil
            }
            return (true, p)
        }
        guard pathToDelete.0 else { return }
        shared.publish(.SILENT)
        let taken = shared.nativeLock.withLock { () -> RecorderBackendSession? in
            let s = shared.nativeSession?.1
            shared.nativeSession = nil
            return s
        }
        if let s = taken {
            recorderBackendCancel(s)
        }
        #if !os(WASI)
        if let p = pathToDelete.1 {
            try? FileManager.default.removeItem(atPath: p)
        }
        #endif
        shared.settle()
    }

    public func state() -> RecorderState {
        shared.withFollowingControl { $0.state }
    }

    public func isRecording() -> Bool {
        shared.withFollowingControl { $0.state == .recording }
    }

    public func elapsed() -> Double {
        shared.withFollowingControl { $0.elapsed }
    }

    public func level() -> Level {
        if shared.isFaked {
            shared.follow()
        }
        return unpackRecorderLevel(shared.loadPackedLevel())
    }

    public func liveLevel() -> Live<Float> {
        shared.live
    }

    public func setWaker(_ waker: @escaping Waker) {
        shared.setWaker(waker)
    }

    public var debugDescription: String {
        shared.ctlLock.withLock {
            "Recorder(path: \(shared.basePath), state: \(shared.ctl.state), elapsed: \(shared.ctl.elapsed))"
        }
    }
}
