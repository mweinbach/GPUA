// Tests ported from: crates/rune/src/recorder/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AVFAudio
import Foundation
import Testing
@testable import Rune

@Suite("RecorderMacOSTests")
struct RecorderMacOSTests {
    @Test func aStaleFailureLeavesTheCurrentSession() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-recorder-stale.m4a").path
        let rec = Recorder.toFile(path)
        let (session, _) = makeIdleMacRecorderSessionForTesting()
        rec.shared.nativeLock.withLock { rec.shared.nativeSession = (2, session) }
        rec.shared.ctlLock.withLock { rec.shared.ctl.attempt = 2 }
        rec.shared.beganFailure(1, "late")
        #expect(rec.shared.nativeLock.withLock { rec.shared.nativeSession != nil })
        rec.shared.beganFailure(2, "now")
        #expect(rec.shared.nativeLock.withLock { rec.shared.nativeSession == nil })
    }

    @Test func finishingOnTheRecorderThreadDoesntWaitOnItself() {
        let (session, queue) = makeIdleMacRecorderSessionForTesting()
        let begun = RuneInstant.now()
        let sem = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            markMacRecorderThreadForTesting()
            recorderBackendFinish(session)
            sem.signal()
        }
        sem.wait()
        #expect(begun.elapsedSeconds() < 1.0)
        #expect(queue.tryRecv() == nil)
    }

    @Test func theMacosRecorderBuildsWithoutCapturing() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-recorder-\(ProcessInfo.processInfo.processIdentifier)-macos")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (name, fmt) in [("a.m4a", RecordFormat.aac), ("b.wav", RecordFormat.wav)] {
            let opts = RecorderOptions(format: fmt, sampleRate: 44_100, channels: 1, fake: nil)
            switch makeMacAudioRecorder(dir.appendingPathComponent(name).path, opts) {
            case .success(let recorder):
                #expect(!recorder.isRecording)
            case .failure(let err):
                Issue.record("\(name): \(err)")
            }
        }
        #expect(voidOk(recorderBackendPreflight()))
        _ = recorderBackendPermission()
    }
}
#endif
