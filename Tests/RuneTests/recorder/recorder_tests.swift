// Tests ported from: crates/rune/src/recorder/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private final class RecorderScratch {
    let dir: URL

    init(_ name: String) {
        self.dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-recorder-\(ProcessInfo.processInfo.processIdentifier)-\(name)")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func join(_ name: String) -> String {
        dir.appendingPathComponent(name).path
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }
}

private final class TestRecorderClock {
    var clock: Double = 0.0

    init() {
        hostRecorderHeadlessReset()
    }

    func frame(_ dt: Double) {
        clock += dt
        hostRecorderHeadlessFrame(clock)
    }
}

private func expectNear(_ got: Double, _ want: Double, _ tolerance: Double) {
    #expect(abs(got - want) <= tolerance, "got \(got), want \(want)")
}

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Suite("RecorderTests", .serialized)
struct RecorderTests {
    @Test func aRecordingStartsPausesResumesAndStops() {
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let dir = RecorderScratch("states")
        let rec = Recorder.toFile(dir.join("note.wav"))
        let rt = TestRecorderClock()

        #expect(rec.state() == .idle)
        #expect(rec.stop() == .failure(RecorderError("not recording")))
        rec.start()
        #expect(rec.state() == .recording)
        #expect(rec.isRecording())
        rt.frame(0.25)
        expectNear(rec.elapsed(), 0.25, 1e-9)
        rec.pause()
        #expect(rec.state() == .paused)
        rt.frame(0.5)
        expectNear(rec.elapsed(), 0.25, 1e-9)
        rec.resume()
        rec.start()
        rt.frame(0.1)
        expectNear(rec.elapsed(), 0.35, 1e-9)
        guard case .success(let note) = rec.stop() else {
            Issue.record("Expected stop() success")
            return
        }
        #expect(note.path == dir.join("note.wav"))
        expectNear(note.duration, 0.35, 1e-9)
        #expect(rec.state() == .stopped)
        rt.frame(0.2)
        expectNear(rec.elapsed(), 0.35, 1e-9)
        #expect(rec.stop() == .failure(RecorderError("not recording")))
        rec.start()
        #expect(rec.elapsed() == 0.0)
        rt.frame(0.1)
        expectNear(rec.elapsed(), 0.1, 1e-9)
    }

    @Test func aNewRuntimeRestartsElapsedFromItsOwnClock() {
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let dir = RecorderScratch("clock")
        let old = TestRecorderClock()
        old.frame(5.0)
        let rec = Recorder.toFile(dir.join("note.wav"))
        rec.start()
        let rt = TestRecorderClock()
        rt.frame(0.1)
        rt.frame(0.1)
        expectNear(rec.elapsed(), 0.2, 1e-9)
    }

    @Test func aKnownSineReadsItsKnownPeakAndRms() {
        let dir = RecorderScratch("sine")
        FakeMicrophone.sine(1000.0, 0.5).install()
        defer { FakeMicrophone.uninstall() }
        let rec = Recorder.toFile(dir.join("a.wav"))
        let rt = TestRecorderClock()
        #expect(rec.level() == .SILENT)
        rec.start()
        rt.frame(1.0)
        let level = rec.level()
        expectNear(Double(level.peakDb()), 20.0 * log10(0.5), 0.01)
        expectNear(Double(level.rmsDb()), 20.0 * log10(0.5 / sqrt(2.0)), 0.01)
        expectNear(Double(level.meter()), (60.0 - 9.0309) / 60.0, 0.001)
        #expect(rec.liveLevel().get() == level.meter())
        rec.pause()
        #expect(rec.level() == .SILENT)
        #expect(rec.liveLevel().get() == 0.0)
        _ = rec.stop()

        let rec2 = Recorder.toFile(dir.join("b.wav"))
        let rt2 = TestRecorderClock()
        rec2.start()
        for _ in 0..<64 {
            rt2.frame(1.0 / 64.0)
        }
        #expect(rec2.level() == level)

        FakeMicrophone.silence().install()
        let quiet = Recorder.toFile(dir.join("c.wav"))
        quiet.start()
        rt2.frame(0.5)
        #expect(quiet.level() == .SILENT)
        #expect(quiet.level().meter() == 0.0)
    }

    @Test func theMeterRisesFastAndFallsSlowly() {
        var m = AudioMeter()
        for _ in 0..<3 {
            m.push(0.5, 0.125, 0.01)
        }
        let rising = m.level()
        #expect(rising.rmsDb() > -12.0)
        for _ in 0..<10 {
            m.push(0.0, 0.0, 0.01)
        }
        let falling = m.level()
        #expect(falling.rmsDb() > -13.0 && falling.rmsDb() < rising.rmsDb())
        expectNear(Double(falling.peakDb()), -6.0206 - 2.0, 0.01)
        m.push(.nan, .infinity, 0.01)
        #expect(m.level().rmsDb().isFinite)
    }

    @Test func stoppingWritesAWavOfTheRecordedLength() {
        let dir = RecorderScratch("length")
        FakeMicrophone.sine(1000.0, 0.5).install()
        defer { FakeMicrophone.uninstall() }
        let rec = Recorder.toFile(dir.join("note.wav"))
        let rt = TestRecorderClock()
        rec.start()
        rt.frame(1.5)
        guard case .success(let note) = rec.stop() else {
            Issue.record("Expected stop() success")
            return
        }
        expectNear(note.duration, 1.5, 1e-9)
        guard case .success(let (rate, samples)) = readWavFile(note.path) else {
            Issue.record("Expected readWavFile success")
            return
        }
        #expect(rate == 48_000 && samples.count == 72_000)
        expectNear(Double(samples[12]), 0.5, 1.0 / 32_000.0)
        expectNear(Double(samples[36]), -0.5, 1.0 / 32_000.0)
    }

    @Test func anAacRecorderOnAFakeMicrophoneWritesWavBesideItsPath() {
        let dir = RecorderScratch("aac")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let rec = Recorder.toFile(dir.join("note.m4a"))
        let rt = TestRecorderClock()
        rec.start()
        rt.frame(0.2)
        guard case .success(let note) = rec.stop() else {
            Issue.record("Expected stop() success")
            return
        }
        #expect(note.path == dir.join("note.wav"))
        #expect(FileManager.default.fileExists(atPath: note.path))
        #expect(!FileManager.default.fileExists(atPath: dir.join("note.m4a")))
        #expect(rec.path() == dir.join("note.m4a"))
    }

    @Test func theFormatDecidesTheFileExtension() {
        let dir = RecorderScratch("extension")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let rel: (Recorder) -> String = { rec in
            URL(fileURLWithPath: rec.path()).lastPathComponent
        }
        #expect(rel(Recorder.toFile(dir.join("x.wav")).format(.aac)) == "x.m4a")
        #expect(rel(Recorder.toFile(dir.join("x.m4a")).format(.wav)) == "x.wav")
        #expect(rel(Recorder.toFile(dir.join("x"))) == "x.m4a")
        #expect(rel(Recorder.toFile(dir.join("x.mp3"))) == "x.m4a")
        #expect(rel(Recorder.toFile(dir.join("x.MP4"))) == "x.MP4")
        #expect(rel(Recorder.toFile(dir.join("x.WAV"))) == "x.WAV")

        let wav = Recorder.toFile(dir.join("note.m4a")).format(.wav)
        _ = TestRecorderClock()
        wav.start()
        guard case .success(let note) = wav.stop() else {
            Issue.record("Expected stop() success")
            return
        }
        #expect(note.path == dir.join("note.wav"))
        let data = (try? Data(contentsOf: URL(fileURLWithPath: note.path))) ?? Data()
        #expect(Array(data.prefix(4)) == Array("RIFF".utf8))
        #expect(!FileManager.default.fileExists(atPath: dir.join("note.m4a")))
    }

    @Test func droppingTheLastHandleKeepsTheRecording() {
        let dir = RecorderScratch("drop")
        FakeMicrophone.sine(1000.0, 0.5).install()
        defer { FakeMicrophone.uninstall() }
        let rt = TestRecorderClock()
        do {
            var rec: Recorder? = Recorder.toFile(dir.join("a.wav"))
            rec?.start()
            rt.frame(0.25)
            let clone = rec
            rec = nil
            rt.frame(0.25)
            #expect(clone?.isRecording() == true)
            _ = clone
        }
        if case .success(let (_, samples)) = readWavFile(dir.join("a.wav")) {
            #expect(samples.count == 24_000)
        } else {
            Issue.record("Expected a.wav")
        }

        do {
            let rec = Recorder.toFile(dir.join("b.wav"))
            rec.start()
            rt.frame(0.1)
            rec.pause()
            rt.frame(0.5)
        }
        if case .success(let (_, samples)) = readWavFile(dir.join("b.wav")) {
            #expect(samples.count == 4_800)
        } else {
            Issue.record("Expected b.wav")
        }

        do {
            let rec = Recorder.toFile(dir.join("c.wav"))
            rec.start()
            rt.frame(0.1)
            rec.cancel()
        }
        #expect(!FileManager.default.fileExists(atPath: dir.join("c.wav")))
    }

    @Test func cancellingAPendingStartKeepsAnEarlierFile() {
        let dir = RecorderScratch("pending")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let path = dir.join("note.wav")
        let rec = Recorder.toFile(path)
        let rt = TestRecorderClock()
        rec.start()
        rt.frame(0.2)
        _ = rec.stop()
        rec.shared.ctlLock.withLock {
            rec.shared.ctl.attempt &+= 1
            rec.shared.ctl.set(.starting)
        }
        rec.cancel()
        #expect(rec.state() == .idle)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func frameRateNeverMovesASampleLevelOrUnplug() {
        let dir = RecorderScratch("rate")
        FakeMicrophone.default().install()
        defer { FakeMicrophone.uninstall() }
        let rt1 = TestRecorderClock()
        let one = Recorder.toFile(dir.join("one.wav"))
        one.start()
        rt1.frame(1.0)
        let level = one.level()
        guard case .success(let note) = one.stop() else {
            Issue.record("Expected one.stop() success")
            return
        }

        let rt2 = TestRecorderClock()
        let sixty = Recorder.toFile(dir.join("sixty.wav"))
        sixty.start()
        for _ in 0..<60 {
            rt2.frame(1.0 / 60.0)
        }
        #expect(sixty.level() == level)
        guard case .success(let other) = sixty.stop() else {
            Issue.record("Expected sixty.stop() success")
            return
        }
        #expect(other.duration == note.duration)
        if case .success(let (_, samples)) = readWavFile(other.path) {
            #expect(samples.count == 48_000)
        } else {
            Issue.record("Expected sixty.wav")
        }

        FakeMicrophone.silence().unplugAfter(0.3).install()
        let rt3 = TestRecorderClock()
        let rec = Recorder.toFile(dir.join("unplug.wav"))
        rec.start()
        for _ in 0..<18 {
            rt3.frame(1.0 / 60.0)
        }
        if case .interrupted = rec.state() {
            // expected
        } else {
            Issue.record("Expected interrupted on 18th frame, got \(rec.state())")
        }
        if case .success(let saved) = rec.stop() {
            #expect(saved.duration == 0.3)
        } else {
            Issue.record("Expected saved recording")
        }
    }

    @Test func aRestartedRecorderIsFollowedOnce() {
        let dir = RecorderScratch("restart")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let rt = TestRecorderClock()
        let rec = Recorder.toFile(dir.join("note.wav"))
        for _ in 0..<3 {
            rec.start()
            rt.frame(0.1)
            _ = rec.stop()
        }
        #expect(recorderHeadlessFollowedCount(for: rec.shared) == 1)
    }

    @Test func cancelDeletesTheFileOfARecordingInProgress() {
        let dir = RecorderScratch("cancel")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let path = dir.join("note.wav")
        let rec = Recorder.toFile(path)
        let rt = TestRecorderClock()
        rec.start()
        #expect(FileManager.default.fileExists(atPath: path))
        rt.frame(0.3)
        rec.cancel()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(rec.state() == .idle)
        if case .failure = rec.stop() {} else { Issue.record("Expected stop() error") }

        rec.start()
        rt.frame(0.3)
        rec.pause()
        rec.cancel()
        #expect(!FileManager.default.fileExists(atPath: path))

        rec.start()
        rt.frame(0.3)
        _ = rec.stop()
        rec.cancel()
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(rec.state() == .stopped)
    }

    @Test func startingWithoutPermissionFailsClearly() {
        let dir = RecorderScratch("permission")
        let path = dir.join("note.wav")
        FakeMicrophone.silence().permission(.denied).install()
        defer { FakeMicrophone.uninstall() }
        #expect(Recorder.permission() == .denied)
        let rec = Recorder.toFile(path)
        rec.start()
        guard case .failed(let message) = rec.state() else {
            Issue.record("Expected failed state, got \(rec.state())")
            return
        }
        #expect(message.contains("denied"))
        #expect(!rec.isRecording())
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(rec.stop() == .failure(RecorderError(message)))

        FakeMicrophone.silence().permission(.restricted).install()
        rec.start()
        if case .failed(let m) = rec.state() {
            #expect(m.contains("restricted"))
        } else {
            Issue.record("Expected restricted failure")
        }

        FakeMicrophone.silence().permission(.undetermined).answers(.denied).install()
        rec.start()
        if case .failed(let m) = rec.state() {
            #expect(m.contains("denied"))
        } else {
            Issue.record("Expected undetermined->denied failure")
        }
        #expect(Recorder.permission() == .denied)

        FakeMicrophone.silence().permission(.undetermined).install()
        let lock = NSLock()
        nonisolated(unsafe) var heard: MicPermission? = nil
        Recorder.requestPermission { p in
            lock.lock()
            heard = p
            lock.unlock()
        }
        #expect(heard == .granted)
        #expect(Recorder.permission() == .granted)
        rec.start()
        #expect(rec.state() == .recording)

        let own = Recorder.toFile(dir.join("own.wav"))
            .fake(FakeMicrophone.silence().permission(.undetermined).answers(.granted))
        own.start()
        #expect(own.state() == .recording)
    }

    @Test func anUnpluggedMicrophoneKeepsWhatWasCaptured() {
        let dir = RecorderScratch("unplug")
        FakeMicrophone.sine(440.0, 0.25).unplugAfter(0.5).install()
        defer { FakeMicrophone.uninstall() }
        let rec = Recorder.toFile(dir.join("note.wav"))
        let changes = AtomicCounter()
        rec.setWaker { changes.increment() }
        let rt = TestRecorderClock()
        rec.start()
        rt.frame(0.3)
        #expect(rec.state() == .recording)
        let before = changes.load()
        rt.frame(0.4)
        #expect(changes.load() == before + 1)
        #expect(rec.state() == .interrupted("the microphone went away"))
        expectNear(rec.elapsed(), 0.5, 1e-9)
        #expect(rec.level() == .SILENT)
        guard case .success(let note) = rec.stop() else {
            Issue.record("Expected saved recording on stop()")
            return
        }
        expectNear(note.duration, 0.5, 1e-9)
        if case .success(let (_, samples)) = readWavFile(note.path) {
            #expect(samples.count == 24_000)
        } else {
            Issue.record("Expected 24000 samples")
        }
        #expect(rec.state() == .stopped)

        rec.start()
        rt.frame(0.6)
        if case .interrupted = rec.state() {} else { Issue.record("Expected interrupted") }
        rec.cancel()
        #expect(!FileManager.default.fileExists(atPath: note.path))
    }

    @Test func theWakerHearsStateChangesNotProgress() {
        let dir = RecorderScratch("waker")
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let rec = Recorder.toFile(dir.join("note.wav"))
        let calls = AtomicCounter()
        rec.setWaker { calls.increment() }
        #expect(calls.load() == 0)
        let rt = TestRecorderClock()
        rec.start()
        #expect(calls.load() == 1)
        rt.frame(0.1)
        rt.frame(0.1)
        _ = (rec.elapsed(), rec.level())
        #expect(calls.load() == 1)
        rec.pause()
        rec.resume()
        _ = rec.stop()
        #expect(calls.load() == 4)
    }

    @Test func wavAndSampleInputsRecordTheirSamples() {
        let dir = RecorderScratch("wav")
        let ramp: [Float] = (0..<800).map { Float($0) / 800.0 - 0.5 }
        let rec = Recorder.toFile(dir.join("ramp.wav")).fake(FakeMicrophone.samples(8_000, ramp))
        let rt = TestRecorderClock()
        rec.start()
        rt.frame(0.25)
        guard case .success(let rampNote) = rec.stop(),
              case .success(let (rate, got)) = readWavFile(rampNote.path)
        else {
            Issue.record("Expected ramp wav")
            return
        }
        #expect(rate == 8_000 && got.count == 2_000)
        for (i, s) in got.enumerated() {
            expectNear(Double(s), Double(ramp[i % 800]), 1.0 / 32_000.0)
        }

        let again = Recorder.toFile(dir.join("again.wav")).fake(FakeMicrophone.wav(rampNote.path))
        again.start()
        rt.frame(0.125)
        guard case .success(let againNote) = again.stop(),
              case .success(let (_, copy)) = readWavFile(againNote.path)
        else {
            Issue.record("Expected again wav")
            return
        }
        #expect(copy.count == 1_000)
        for (a, b) in zip(copy, got) {
            expectNear(Double(a), Double(b), 1.0 / 32_000.0)
        }

        let missing = Recorder.toFile(dir.join("x.wav")).fake(FakeMicrophone.wav(dir.join("missing.wav")))
        missing.start()
        if case .failed(let m) = missing.state() {
            #expect(m.contains("couldn't read"))
        } else {
            Issue.record("Expected couldn't read failure")
        }
    }

    @Test func anUnwritablePathFailsToStart() {
        FakeMicrophone.silence().install()
        defer { FakeMicrophone.uninstall() }
        let badPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-recorder-missing-dir")
            .appendingPathComponent("deeper")
            .appendingPathComponent("note.wav").path
        let rec = Recorder.toFile(badPath)
        rec.start()
        if case .failed(let m) = rec.state() {
            #expect(m.contains("couldn't write"))
        } else {
            Issue.record("Expected couldn't write failure, got \(rec.state())")
        }
    }

    @Test func wavFilesParseFormatsAndRejectOthers() {
        if case .failure = parseWavBytes(Array("RIFF\0\0\0\0WAVE".utf8)) {} else { Issue.record("Expected error") }
        if case .failure = parseWavBytes(Array("not a wav".utf8)) {} else { Issue.record("Expected error") }

        var b: [UInt8] = []
        func pushU16(_ v: UInt16) {
            b.append(UInt8(truncatingIfNeeded: v))
            b.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        func pushU32(_ v: UInt32) {
            b.append(UInt8(truncatingIfNeeded: v))
            b.append(UInt8(truncatingIfNeeded: v >> 8))
            b.append(UInt8(truncatingIfNeeded: v >> 16))
            b.append(UInt8(truncatingIfNeeded: v >> 24))
        }
        b.append(contentsOf: "RIFF\0\0\0\0WAVEfmt ".utf8)
        pushU32(16)
        pushU16(3)
        pushU16(2)
        pushU32(22_050)
        pushU32(22_050 * 8)
        pushU16(8)
        pushU16(32)
        b.append(contentsOf: "data".utf8)
        pushU32(16)
        for s: Float in [0.5, -0.5, 1.0, 0.0] {
            pushU32(s.bitPattern)
        }
        guard case .success(let (rate, samples)) = parseWavBytes(b) else {
            Issue.record("Expected stereo 32-bit float WAV parse")
            return
        }
        #expect(rate == 22_050 && samples == [0.0, 0.5])
    }
}
