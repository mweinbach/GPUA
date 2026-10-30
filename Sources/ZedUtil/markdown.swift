// Ported from: crates/util/src/markdown.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Generates a URL-friendly slug from heading text (e.g. "Hello World" -> "hello-world").
public func generateHeadingSlug(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var result = ""
    for character in trimmed {
        if character.isLetter || character.isNumber || character == "-" || character == "_" {
            result.append(contentsOf: character.lowercased())
        } else if character == " " {
            result.append("-")
        }
    }
    return result
}

/// Returns true if the URL starts with a URI scheme (RFC 3986 sec. 3.1).
func hasUriScheme(_ url: String) -> Bool {
    var chars = url.makeIterator()
    guard let first = chars.next(), first.isASCII && first.isLetter else {
        return false
    }
    while let c = chars.next() {
        if c == ":" {
            return true
        }
        if !(c.isASCII && (c.isLetter || c.isNumber) || c == "+" || c == "-" || c == ".") {
            return false
        }
    }
    return false
}

/// Splits a relative URL into its path and `#fragment` parts.
/// Absolute URLs are returned as-is with no fragment.
public func splitLocalUrlFragment(_ url: String) -> (String, String?) {
    if hasUriScheme(url) {
        return (url, nil)
    }
    if let hashIndex = url.firstIndex(of: "#") {
        let path = String(url[..<hashIndex])
        let fragmentIndex = url.index(after: hashIndex)
        let fragment = String(url[fragmentIndex...])
        return (path, fragment.isEmpty ? nil : fragment)
    }
    return (url, nil)
}

/// Indicates that the wrapped `String` is markdown text.
public struct MarkdownString: CustomStringConvertible, Sendable, Equatable, Hashable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// Escapes markdown special characters in markdown text blocks.
public struct MarkdownEscaped: CustomStringConvertible, Sendable, Equatable, Hashable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        var result = ""
        for c in rawValue {
            switch c {
            case "\\", "`", "*", "_", "[", "^", "$", "~", "&", "#", "+", "=", "-":
                result.append("\\")
                result.append(c)
            case "<":
                result.append("&lt;")
            case ">":
                result.append("&gt;")
            default:
                result.append(c)
            }
        }
        return result
    }
}

/// Implements `Display` to format markdown inline code (wrapped in backticks), handling code that
/// contains backticks and spaces.
public struct MarkdownInlineCode: CustomStringConvertible, Sendable, Equatable, Hashable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        var allWhitespace = true
        var text = ""
        for c in rawValue {
            if c.isWhitespace {
                text.append(" ")
            } else {
                allWhitespace = false
                text.append(c)
            }
        }

        if allWhitespace {
            return "`\(text)`"
        } else {
            let backtickCount = countMaxConsecutiveChars(text, "`") + 1
            let backticks = String(repeating: "`", count: backtickCount)

            let needsSpace: Bool
            if text.hasPrefix("`") || text.hasSuffix("`") {
                needsSpace = true
            } else if text.hasPrefix(" ") && text.hasSuffix(" ") {
                needsSpace = true
            } else {
                needsSpace = false
            }

            let space = needsSpace ? " " : ""
            return "\(backticks)\(space)\(text)\(space)\(backticks)"
        }
    }
}

/// Implements `Display` to format markdown code blocks, wrapped in 3 or more backticks as needed.
public struct MarkdownCodeBlock: CustomStringConvertible, Sendable, Equatable, Hashable {
    public var tag: String
    public var text: String

    public init(tag: String, text: String) {
        self.tag = tag
        self.text = text
    }

    public var description: String {
        let backtickCount = max(3, countMaxConsecutiveChars(text, "`") + 1)
        let backticks = String(repeating: "`", count: backtickCount)
        return "\(backticks)\(tag)\n\(text)\n\(backticks)\n"
    }
}

/// Counts the maximum number of consecutive occurrences of `search` character in `text`.
public func countMaxConsecutiveChars(_ text: String, _ search: Character) -> Int {
    var inSearchChars = false
    var maxCount = 0
    var curCount = 0

    for ch in text {
        if ch == search {
            curCount += 1
            inSearchChars = true
        } else if inSearchChars {
            maxCount = max(maxCount, curCount)
            curCount = 0
            inSearchChars = false
        }
    }
    return max(maxCount, curCount)
}

/// Escapes markdown special characters in text blocks.
public func markdownEscaped(_ text: String) -> String {
    MarkdownEscaped(text).description
}

/// Wraps text in markdown inline code backticks with necessary spacing.
public func markdownInlineCode(_ text: String) -> String {
    MarkdownInlineCode(text).description
}

/// Formats a markdown code block with appropriate backticks fence.
public func markdownCodeBlock(tag: String, text: String) -> String {
    MarkdownCodeBlock(tag: tag, text: text).description
}
