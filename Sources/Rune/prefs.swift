// Ported from: crates/rune/src/prefs.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A small store for an app's settings (text size, last-used options): JSON in the platform's
//! config directory, read and written with Codable.

import Foundation

public enum PrefsError: Error, CustomStringConvertible, Sendable {
    case serialize(String)
    case io(String)

    public var description: String {
        switch self {
        case .serialize(let why): return "can't store the value: \(why)"
        case .io(let err): return "can't save preferences: \(err)"
        }
    }
}

private let prefsFileName = "prefs.json"
private let prefsTmpLock = LiveLock()
// PORT NOTE: Protected by `prefsTmpLock` for unique atomic temp filenames across concurrent writers.
nonisolated(unsafe) private var nextPrefsTmpSeq: UInt64 = 0

/// An app's settings, keyed by name (`crates/rune/src/prefs.rs`).
public struct Prefs: Sendable {
    private var rawEntries: [String: Data]
    private var filePath: String?

    public static func open(_ appId: String) -> Prefs {
        #if os(WASI)
        let lookup: (String) -> String? = { _ in nil }
        #else
        let env = ProcessInfo.processInfo.environment
        let lookup: (String) -> String? = { env[$0] }
        #endif
        if let dir = resolvePrefsConfigDir(lookup) {
            let folder = sanitizePrefsAppId(appId)
            let full = (dir as NSString)
                .appendingPathComponent(folder)
                .appending("/\(prefsFileName)")
            return Prefs.at(full)
        }
        return Prefs.memory()
    }

    public static func at(_ path: String) -> Prefs {
        let entries = loadPrefsEntries(path)
        return Prefs(rawEntries: entries, filePath: path)
    }

    public static func memory() -> Prefs {
        Prefs(rawEntries: [:], filePath: nil)
    }

    public func path() -> String? {
        filePath
    }

    public var isPersistent: Bool {
        filePath != nil
    }

    public func get<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let data = rawEntries[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public mutating func set<T: Encodable>(_ key: String, _ value: T) throws(PrefsError) {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(value)
        } catch {
            throw .serialize(String(describing: error))
        }
        rawEntries[key] = encoded
        try save()
    }

    public mutating func remove(_ key: String) throws(PrefsError) {
        guard rawEntries.removeValue(forKey: key) != nil else { return }
        try save()
    }

    public func contains(_ key: String) -> Bool {
        rawEntries[key] != nil
    }

    private func save() throws(PrefsError) {
        guard let filePath else { return }
        #if os(WASI)
        _ = filePath
        return
        #else
        var jsonObject: [String: Any] = [:]
        for (k, data) in rawEntries {
            if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                jsonObject[k] = obj
            }
        }
        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw .serialize(String(describing: error))
        }
        do {
            try writeAtomicPrefs(filePath, payload)
        } catch {
            throw .io(String(describing: error))
        }
        #endif
    }
}

private func loadPrefsEntries(_ path: String) -> [String: Data] {
    #if os(WASI)
    return [:]
    #else
    let url = URL(fileURLWithPath: path)
    guard let bytes = try? Data(contentsOf: url) else {
        return [:]
    }
    if let obj = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
        var out: [String: Data] = [:]
        for (k, v) in obj {
            if let encoded = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) {
                out[k] = encoded
            }
        }
        return out
    }
    let badPath = path + ".bad"
    let fm = FileManager.default
    try? fm.removeItem(atPath: badPath)
    if (try? fm.moveItem(atPath: path, toPath: badPath)) == nil {
        try? bytes.write(to: URL(fileURLWithPath: badPath))
    }
    return [:]
    #endif
}

#if !os(WASI)
private func writeAtomicPrefs(_ path: String, _ bytes: Data) throws {
    let fm = FileManager.default
    let parent = (path as NSString).deletingLastPathComponent
    if !parent.isEmpty {
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
    }
    let seq = prefsTmpLock.withLock { () -> UInt64 in
        let s = nextPrefsTmpSeq
        nextPrefsTmpSeq &+= 1
        return s
    }
    let pid = ProcessInfo.processInfo.processIdentifier
    let tmpPath = "\(path).\(pid).\(seq).tmp"
    let tmpURL = URL(fileURLWithPath: tmpPath)
    let dstURL = URL(fileURLWithPath: path)
    do {
        try bytes.write(to: tmpURL, options: .withoutOverwriting)
        _ = try fm.replaceItemAt(dstURL, withItemAt: tmpURL)
    } catch {
        try? fm.removeItem(at: tmpURL)
        throw error
    }
}
#endif

func sanitizePrefsAppId(_ appId: String) -> String {
    let trimmedInput = appId.trimmingCharacters(in: .whitespacesAndNewlines)
    let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
    var mapped = ""
    mapped.reserveCapacity(trimmedInput.count)
    for ch in trimmedInput {
        if ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) || forbidden.contains(ch) {
            mapped.append("_")
        } else {
            mapped.append(ch)
        }
    }
    while let last = mapped.last, last.isWhitespace || last == "." {
        mapped.removeLast()
    }
    return mapped.isEmpty ? "app" : mapped
}

func resolvePrefsConfigDir(_ envLookup: (String) -> String?) -> String? {
    func nonEmpty(_ key: String) -> String? {
        guard let v = envLookup(key), !v.isEmpty else { return nil }
        return v
    }
    if let overrideDir = nonEmpty("RUNE_PREFS_DIR") {
        return overrideDir
    }
    #if os(WASI)
    return nil
    #elseif os(macOS) || os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
    guard let home = nonEmpty("HOME") else { return nil }
    return (home as NSString)
        .appendingPathComponent("Library")
        .appending("/Application Support")
    #elseif os(Windows)
    return nonEmpty("APPDATA")
    #else
    if let xdg = nonEmpty("XDG_CONFIG_HOME"), xdg.hasPrefix("/") {
        return xdg
    }
    guard let home = nonEmpty("HOME") else { return nil }
    return (home as NSString).appendingPathComponent(".config")
    #endif
}
