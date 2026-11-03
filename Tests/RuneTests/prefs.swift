// Tests ported from: crates/rune/src/prefs.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Dispatch
#endif
import Foundation
import Testing
@testable import Rune

private struct TempPrefsDir {
    let path: String

    init(_ name: String) {
        #if os(WASI)
        self.path = "/tmp/rune-prefs-\(name)"
        #else
        let pid = ProcessInfo.processInfo.processIdentifier
        let unique = UUID().uuidString
        self.path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("rune-prefs-\(name)-\(pid)-\(unique)")
        try? FileManager.default.removeItem(atPath: self.path)
        #endif
    }

    func cleanup() {
        #if !os(WASI)
        try? FileManager.default.removeItem(atPath: path)
        #endif
    }
}

@Suite("PrefsTests")
struct PrefsTests {
    #if !os(WASI)
    @Test("values round trip through the file")
    func valuesRoundTripThroughTheFile() throws {
        let dir = TempPrefsDir("roundtrip")
        defer { dir.cleanup() }
        let path = (dir.path as NSString).appendingPathComponent("app/prefs.json")
        var prefs = Prefs.at(path)
        #expect(prefs.get("text_size", as: Float.self) == nil)
        try prefs.set("text_size", Float(15.5))
        try prefs.set("window", [UInt32(800), UInt32(600)])
        try prefs.set("recent", ["a", "b"])

        let again = Prefs.at(path)
        #expect(again.get("text_size", as: Float.self) == 15.5)
        #expect(again.get("window", as: [UInt32].self) == [800, 600])
        #expect(again.get("recent", as: [String].self) == ["a", "b"])
        #expect(again.get("text_size", as: String.self) == nil)

        var mutableAgain = again
        try mutableAgain.remove("text_size")
        #expect(!Prefs.at(path).contains("text_size"))
        let parent = (path as NSString).deletingLastPathComponent
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix(".tmp") })
    }

    @Test("a corrupt file starts empty and is kept as bad")
    func corruptFileStartsEmptyAndIsKeptAsBad() throws {
        let dir = TempPrefsDir("corrupt")
        defer { dir.cleanup() }
        try FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let path = (dir.path as NSString).appendingPathComponent("prefs.json")
        let badPath = path + ".bad"

        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: path))
        var prefs = Prefs.at(path)
        #expect(!prefs.contains("anything"))
        #expect((try? Data(contentsOf: URL(fileURLWithPath: badPath))) == Data("{ not json".utf8))
        try prefs.set("k", UInt8(1))
        #expect(Prefs.at(path).get("k", as: UInt8.self) == 1)

        try Data("[1, 2]".utf8).write(to: URL(fileURLWithPath: path))
        #expect(!Prefs.at(path).contains("k"))
        #expect((try? Data(contentsOf: URL(fileURLWithPath: badPath))) == Data("[1, 2]".utf8))
    }

    @Test("concurrent writers do not clobber temp files")
    func concurrentWritersDoNotClobberTempFiles() {
        let dir = TempPrefsDir("concurrent")
        defer { dir.cleanup() }
        let path = (dir.path as NSString).appendingPathComponent("prefs.json")
        DispatchQueue.concurrentPerform(iterations: 4) { t in
            var prefs = Prefs.at(path)
            for i in 0..<20 {
                try? prefs.set("k_\(t)", UInt32(t * 100 + i))
            }
        }
        let finalPrefs = Prefs.at(path)
        #expect(finalPrefs.isPersistent)
        #expect(!FileManager.default.fileExists(atPath: path + ".bad"))
    }
    #endif

    @Test("memory stores touch no file")
    func memoryStoresTouchNoFile() throws {
        var prefs = Prefs.memory()
        try prefs.set("k", "v")
        #expect(prefs.get("k", as: String.self) == "v")
        #expect(!prefs.isPersistent && prefs.path() == nil)
    }

    @Test("app ids stay inside the config directory")
    func appIdsStayInsideConfigDirectory() {
        #expect(sanitizePrefsAppId("com.example.notes") == "com.example.notes")
        #expect(sanitizePrefsAppId("../evil/id") == ".._evil_id")
        #expect(sanitizePrefsAppId("..") == "app")
        #expect(sanitizePrefsAppId("...") == "app")
        #expect(sanitizePrefsAppId("com.example.") == "com.example")
        #expect(sanitizePrefsAppId("") == "app")
    }

    @Test("the config directory follows the platform and the override")
    func configDirectoryFollowsPlatformAndOverride() {
        func lookup(_ pairs: [(String, String)]) -> (String) -> String? {
            { key in pairs.first { $0.0 == key }?.1 }
        }
        #expect(resolvePrefsConfigDir(lookup([("RUNE_PREFS_DIR", "/scratch"), ("HOME", "/home/x")])) == "/scratch")
        #expect(resolvePrefsConfigDir(lookup([])) == nil)
        #if os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        #expect(resolvePrefsConfigDir(lookup([("HOME", "/h")])) == "/h/Library/Application Support")
        #elseif os(Windows)
        #expect(resolvePrefsConfigDir(lookup([("APPDATA", "C:\\Roaming")])) == "C:\\Roaming")
        #elseif !os(WASI)
        #expect(resolvePrefsConfigDir(lookup([("HOME", "/h")])) == "/h/.config")
        #expect(resolvePrefsConfigDir(lookup([("HOME", "/h"), ("XDG_CONFIG_HOME", "/xdg")])) == "/xdg")
        #expect(resolvePrefsConfigDir(lookup([("HOME", "/h"), ("XDG_CONFIG_HOME", "rel")])) == "/h/.config")
        #endif
    }
}
