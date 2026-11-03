// Ported from: crates/rune/src/recorder/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AVFAudio
import AVFoundation
import CoreAudio
import Foundation

private let DEVICE_CHECK_TICKS: UInt32 = 15
private let REPLY_PATIENCE_SECONDS: TimeInterval = 5.0
private let recorderThreadKey = "gpua.rune.onRecorderThread"

private func defaultAudioInputDevice() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var device: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &device
    )
    return (status == noErr && device != 0) ? device : nil
}

func recorderBackendPermission() -> MicPermission {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return .granted
    case .denied:
        return .denied
    case .restricted:
        return .restricted
    case .notDetermined:
        return .undetermined
    @unknown default:
        return .restricted
    }
}

func recorderBackendRequestPermission(_ callback: @escaping @Sendable (MicPermission) -> Void) {
    if case .failure = recorderBackendPreflight() {
        callback(.denied)
        return
    }
    let current = recorderBackendPermission()
    if current != .undetermined {
        callback(current)
        return
    }
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        callback(granted ? .granted : .denied)
    }
}

/// macOS ends a bundled app that touches the microphone without a usage description; refuse
/// instead. An unbundled binary is attributed to the terminal that ran it.
func recorderBackendPreflight() -> Result<Void, RecorderError> {
    let bundle = Bundle.main
    guard bundle.bundlePath.hasSuffix(".app") else {
        return .success(())
    }
    if bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil {
        return .success(())
    }
    return .failure(RecorderError(
        "the app's Info.plist has no NSMicrophoneUsageDescription, so macOS won't let it record"
    ))
}

/// An `AVAudioRecorder` for `path`, not yet prepared or recording: no file and no capture.
func makeMacAudioRecorder(_ path: String, _ opts: RecorderOptions) -> Result<AVAudioRecorder, RecorderError> {
    let url = URL(fileURLWithPath: path)
    var settings: [String: Any] = [
        AVSampleRateKey: Double(opts.sampleRate),
        AVNumberOfChannelsKey: Int(opts.channels),
    ]
    switch opts.format {
    case .aac:
        settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
    case .wav:
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = false
        settings[AVLinearPCMIsNonInterleaved] = false
    }
    do {
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        return .success(recorder)
    } catch {
        return .failure(RecorderError("couldn't record to \(path): \(error.localizedDescription)"))
    }
}

enum MacRecorderCommand {
    case pause
    case resume
    case stop(MacRecorderReply<Result<Double, RecorderError>>)
    case cancel(MacRecorderReply<Void>)
}

// PORT NOTE: Synchronized via `NSCondition` for bounded-timeout reply handoff between the app thread and `"rune-recorder"` thread.
final class MacRecorderReply<T>: @unchecked Sendable {
    private let cond = NSCondition()
    private var value: T? = nil

    func send(_ v: T) {
        cond.lock()
        value = v
        cond.signal()
        cond.unlock()
    }

    func wait(_ timeout: TimeInterval) -> T? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        cond.lock()
        defer { cond.unlock() }
        while value == nil {
            if !cond.wait(until: deadline) {
                break
            }
        }
        return value
    }
}

// PORT NOTE: Synchronized via `NSCondition`, matching `std::sync::mpsc::channel` in `crates/rune/src/recorder/macos.rs`.
final class MacRecorderQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var queue: [MacRecorderCommand] = []
    private var disconnected: Bool = false

    enum RecvResult {
        case item(MacRecorderCommand)
        case timeout
        case disconnected
    }

    func send(_ cmd: MacRecorderCommand) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        guard !disconnected else { return false }
        queue.append(cmd)
        cond.signal()
        return true
    }

    func disconnect() {
        cond.lock()
        disconnected = true
        cond.broadcast()
        cond.unlock()
    }

    func tryRecv() -> MacRecorderCommand? {
        cond.lock()
        defer { cond.unlock() }
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    func recvTimeout(_ timeout: TimeInterval) -> RecvResult {
        let deadline = Date(timeIntervalSinceNow: timeout)
        cond.lock()
        defer { cond.unlock() }
        while queue.isEmpty && !disconnected {
            if !cond.wait(until: deadline) {
                break
            }
        }
        if !queue.isEmpty {
            return .item(queue.removeFirst())
        }
        return disconnected ? .disconnected : .timeout
    }
}

// PORT NOTE: Wraps a thread-safe `MacRecorderQueue` and disconnects it on `deinit`, matching `Session { commands: Sender<Command> }` in Rust.
final class RecorderBackendSession: @unchecked Sendable {
    let queue: MacRecorderQueue

    init(queue: MacRecorderQueue) {
        self.queue = queue
    }

    deinit {
        queue.disconnect()
    }
}

func recorderBackendStart(
    _ shared: RecorderShared,
    _ attempt: UInt64,
    _ path: String,
    _ opts: RecorderOptions
) -> Result<RecorderBackendSession, RecorderError> {
    let queue = MacRecorderQueue()
    let thread = Thread { [weak shared] in
        runMacRecorderThread(shared, attempt: attempt, path: path, opts: opts, queue: queue)
    }
    thread.name = "rune-recorder"
    thread.start()
    return .success(RecorderBackendSession(queue: queue))
}

func recorderBackendPause(_ session: RecorderBackendSession) {
    _ = session.queue.send(.pause)
}

func recorderBackendResume(_ session: RecorderBackendSession) {
    _ = session.queue.send(.resume)
}

func recorderBackendStop(_ session: RecorderBackendSession) -> Result<Double, RecorderError> {
    let reply = MacRecorderReply<Result<Double, RecorderError>>()
    guard session.queue.send(.stop(reply)) else {
        return .failure(RecorderError("the recording already ended"))
    }
    return reply.wait(REPLY_PATIENCE_SECONDS) ?? .failure(RecorderError("the recorder didn't stop"))
}

func recorderBackendFinish(_ session: RecorderBackendSession) {
    let onRecorderThread = (Thread.current.threadDictionary[recorderThreadKey] as? Bool) == true
    if !onRecorderThread {
        _ = recorderBackendStop(session)
    }
}

func markMacRecorderThreadForTesting() {
    Thread.current.threadDictionary[recorderThreadKey] = true
}

func makeIdleMacRecorderSessionForTesting() -> (RecorderBackendSession, MacRecorderQueue) {
    let q = MacRecorderQueue()
    return (RecorderBackendSession(queue: q), q)
}

func recorderBackendCancel(_ session: RecorderBackendSession) {
    let reply = MacRecorderReply<Void>()
    if session.queue.send(.cancel(reply)) {
        _ = reply.wait(REPLY_PATIENCE_SECONDS)
    }
}

private func openMacAudioRecorder(_ path: String, _ opts: RecorderOptions) -> Result<(AVAudioRecorder, AudioDeviceID?), RecorderError> {
    guard let device = defaultAudioInputDevice() else {
        return .failure(RecorderError("no microphone is connected"))
    }
    switch makeMacAudioRecorder(path, opts) {
    case .failure(let err):
        return .failure(err)
    case .success(let recorder):
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            return .failure(RecorderError("couldn't create \(path)"))
        }
        guard recorder.record() else {
            recorder.deleteRecording()
            return .failure(RecorderError("couldn't start recording from the microphone"))
        }
        return .success((recorder, device))
    }
}

private func runMacRecorderThread(
    _ weakShared: RecorderShared?,
    attempt: UInt64,
    path: String,
    opts: RecorderOptions,
    queue: MacRecorderQueue
) {
    Thread.current.threadDictionary[recorderThreadKey] = true
    let opened = autoreleasepool { openMacAudioRecorder(path, opts) }
    let recorder: AVAudioRecorder
    let device: AudioDeviceID?
    switch opened {
    case .success(let pair):
        recorder = pair.0
        device = pair.1
    case .failure(let err):
        weakShared?.beganFailure(attempt, err.message)
        return
    }
    weakShared?.began(attempt)

    var meter = AudioMeter()
    var last = RuneInstant.now()
    var ticks: UInt32 = 0
    var paused = false
    var recorded: Double = 0.0
    let intervalSeconds = Double(Recorder.METER_INTERVAL.components.seconds)
        + Double(Recorder.METER_INTERVAL.components.attoseconds) * 1e-18

    while true {
        let received = queue.recvTimeout(intervalSeconds)
        let done: Bool = autoreleasepool {
            switch received {
            case .item(.pause):
                recorded = max(recorded, recorder.currentTime)
                recorder.pause()
                paused = true
                return false
            case .item(.resume):
                _ = recorder.record()
                paused = false
                last = RuneInstant.now()
                return false
            case .item(.stop(let reply)):
                recorded = max(recorded, recorder.currentTime)
                recorder.stop()
                reply.send(.success(recorded))
                return true
            case .item(.cancel(let reply)):
                recorder.stop()
                recorder.deleteRecording()
                reply.send(())
                return true
            case .timeout where paused:
                return false
            case .timeout:
                guard let shared = weakShared else {
                    recorder.stop()
                    return true
                }
                recorder.updateMeters()
                let peak = recorder.peakPower(forChannel: 0)
                let avg = recorder.averagePower(forChannel: 0)
                let isRec = recorder.isRecording
                recorded = max(recorded, recorder.currentTime)
                let now = RuneInstant.now()
                let dt = now.durationSince(last)
                let dtSec = Double(dt.components.seconds) + Double(dt.components.attoseconds) * 1e-18
                meter.pushDb(peak, avg, dtSec)
                last = now
                shared.metered(attempt, meter.level())
                ticks &+= 1
                let lost: String?
                if !isRec {
                    lost = "recording stopped: the input device went away"
                } else if ticks % DEVICE_CHECK_TICKS == 0 && defaultAudioInputDevice() != device {
                    lost = "the input device changed"
                } else {
                    lost = nil
                }
                if let reason = lost {
                    recorder.stop()
                    shared.interrupted(attempt, reason, recorded)
                    return true
                }
                return false
            case .disconnected:
                recorder.stop()
                return true
            }
        }
        if done { break }
    }
}
#endif
