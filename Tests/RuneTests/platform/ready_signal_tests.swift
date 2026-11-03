// Tests ported from: crates/rune/src/platform/ready_signal_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if !os(WASI)
import Foundation

@Suite("ReadySignalTests", .serialized)
struct ReadySignalTests {
    private func scratchDir(_ name: String) -> URL {
        let nanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let pid = ProcessInfo.processInfo.processIdentifier
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-\(name)-\(pid)-\(nanos)", isDirectory: true)
    }

    @Test("a launcher can wait for the ready file")
    func launcherCanWaitForTheReadyFile() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }
        readySignalResetForTests()
        let root = scratchDir("ready")
        defer {
            readySignalClear()
            readySignalResetForTests()
            try? FileManager.default.removeItem(at: root)
        }
        let dir = root.appendingPathComponent("ready", isDirectory: true)
        readySignalReadyIn(dir.path)

        let pid = ProcessInfo.processInfo.processIdentifier
        let bundle = readySignalBundleId()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let pathURL = dir.appendingPathComponent("\(bundle).\(pid)")
        let text = try String(contentsOf: pathURL, encoding: .utf8)
        #expect(text.hasSuffix("\n"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2 && lines[1].isEmpty)

        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        #expect((parsed?["pid"] as? Int) == Int(pid))
        #expect((parsed?["bundle_id"] as? String) == readySignalBundleId())
        #expect((parsed?["rune"] as? String) == runeReadyPackageVersion)
        #expect((parsed?["ready_ms"] as? NSNumber) != nil)

        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(entries.count == 1)

        #if !os(Windows)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((perms & 0o777) == 0o700)
        #endif

        let other = root.appendingPathComponent("other", isDirectory: true)
        readySignalReadyIn(other.path)
        #expect(!FileManager.default.fileExists(atPath: other.path))

        readySignalClear()
        #expect(!FileManager.default.fileExists(atPath: pathURL.path))
    }

    @Test("without the variable nothing is written")
    func withoutTheVariableNothingIsWritten() {
        let signal = ReadySignal(pid: 7, bundleId: "com.example.app", readyMs: 412)
        #expect(signal.writeIn(nil) == nil)
        #expect(signal.writeIn("") == nil)
        #expect(
            signal.json()
                == "{\"pid\":7,\"bundle_id\":\"com.example.app\",\"ready_ms\":412,\"rune\":\"\(runeReadyPackageVersion)\"}"
        )
    }
}
#endif
