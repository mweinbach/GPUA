// Ported from: crates/rune/src/open_url.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

public enum OpenUrlError: Error, CustomStringConvertible, Sendable, Equatable {
    case empty
    case disallowedScheme(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .empty: return "empty URL"
        case .disallowedScheme(let s): return "disallowed URL scheme: \(s)"
        case .malformed(let why): return "malformed URL: \(why)"
        }
    }
}

struct OpenUrlLink: Sendable, Equatable {
    var url: String
    var sameTab: Bool
}

func checkOpenUrl(_ raw: String) throws(OpenUrlError) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .empty }
    guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else {
        throw .malformed("whitespace in URL")
    }
    guard let colonIdx = trimmed.firstIndex(of: ":") else {
        throw .malformed("missing scheme")
    }
    let scheme = trimmed[..<colonIdx].lowercased()
    switch scheme {
    case "http", "https":
        let rest = trimmed[trimmed.index(after: colonIdx)...]
        guard rest.hasPrefix("//"), rest.dropFirst(2).first != nil else {
            throw .malformed("missing host")
        }
        return trimmed
    case "mailto":
        let rest = trimmed[trimmed.index(after: colonIdx)...]
        guard !rest.isEmpty else { throw .malformed("empty mailto") }
        return trimmed
    default:
        throw .disallowedScheme(scheme)
    }
}

func checkOpenUrlSameTab(_ raw: String) throws(OpenUrlError) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .empty }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix("?") || trimmed.hasPrefix("#") {
        return trimmed
    }
    return try checkOpenUrl(trimmed)
}
