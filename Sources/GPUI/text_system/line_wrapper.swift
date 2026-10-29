// Ported from: crates/gpui/src/text_system/line_wrapper.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Determines whether to truncate text from the start or end.
public enum TruncateFrom: Sendable, Equatable, Hashable {
    /// Truncate text from the start.
    case start
    /// Truncate text from the end.
    case end
}

/// The candidate boundary item during line wrapping.
public enum WrapBoundaryCandidate: Sendable, Equatable {
    case char(character: Character)
    case element(width: Pixels, lenUtf8: Int)

    public func lenUtf8() -> Int {
        switch self {
        case .char(let c):
            return c.utf8.count
        case .element(_, let len):
            return len
        }
    }
}

/// A fragment of a line that can be wrapped.
public enum LineFragment: Sendable, Equatable {
    /// A text fragment consisting of characters.
    case text(text: String)
    /// A non-text element with a fixed width.
    case element(width: Pixels, lenUtf8: Int)

    public static func text(_ text: String) -> LineFragment {
        .text(text: text)
    }

    public static func element(_ width: Pixels, _ lenUtf8: Int) -> LineFragment {
        .element(width: width, lenUtf8: lenUtf8)
    }

    public func wrapBoundaryCandidates() -> [WrapBoundaryCandidate] {
        switch self {
        case .text(let text):
            return text.map { WrapBoundaryCandidate.char(character: $0) }
        case .element(let width, let len):
            return [WrapBoundaryCandidate.element(width: width, lenUtf8: len)]
        }
    }
}

/// A boundary between two lines of text.
public struct Boundary: Sendable, Equatable, Hashable {
    /// The index of the last character in a line.
    public var ix: Int
    /// The indent of the next line.
    public var nextIndent: UInt32

    public init(ix: Int, nextIndent: UInt32) {
        self.ix = ix
        self.nextIndent = nextIndent
    }

    public static func new(ix: Int, nextIndent: UInt32) -> Boundary {
        Boundary(ix: ix, nextIndent: nextIndent)
    }
}

/// The GPUI line wrapper, used to wrap lines of text to a given width.
public final class LineWrapper {
    public static let maxIndent: UInt32 = 256

    public var textSystem: TextSystem
    public var fontId: FontId
    public var fontSize: Pixels
    private var cachedAsciiCharWidths: [Pixels?]
    private var cachedOtherCharWidths: [Character: Pixels]

    public init(fontId: FontId, fontSize: Pixels, textSystem: TextSystem) {
        self.fontId = fontId
        self.fontSize = fontSize
        self.textSystem = textSystem
        self.cachedAsciiCharWidths = Array(repeating: nil, count: 128)
        self.cachedOtherCharWidths = [:]
    }

    public static func new(fontId: FontId, fontSize: Pixels, textSystem: TextSystem) -> LineWrapper {
        LineWrapper(fontId: fontId, fontSize: fontSize, textSystem: textSystem)
    }

    public func widthForChar(_ c: Character) -> Pixels {
        if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1, scalar.value < 128 {
            let asciiIdx = Int(scalar.value)
            if let cached = cachedAsciiCharWidths[asciiIdx] {
                return cached
            }
            let width = textSystem.layoutWidth(fontId: fontId, fontSize: fontSize, ch: c)
            cachedAsciiCharWidths[asciiIdx] = width
            return width
        } else {
            if let cached = cachedOtherCharWidths[c] {
                return cached
            }
            let width = textSystem.layoutWidth(fontId: fontId, fontSize: fontSize, ch: c)
            cachedOtherCharWidths[c] = width
            return width
        }
    }

    public func wrapLine(
        fragments: [LineFragment],
        wrapWidth: Pixels
    ) -> [Boundary] {
        var boundaries: [Boundary] = []
        var width = px(0)
        var firstNonWhitespaceIx: Int? = nil
        var indent: UInt32? = nil
        var lastCandidateIx = 0
        var lastCandidateWidth = px(0)
        var lastWrapIx = 0
        var prevC: Character = "\0"
        var index = 0

        var candidates: [WrapBoundaryCandidate] = []
        for fragment in fragments {
            candidates.append(contentsOf: fragment.wrapBoundaryCandidates())
        }

        for candidate in candidates {
            let ix = index
            index += candidate.lenUtf8()
            var newPrevC = prevC

            let itemWidth: Pixels
            switch candidate {
            case .char(let c):
                if c == "\n" {
                    continue
                }

                if Self.isWordChar(c) {
                    if prevC == " " && c != " " && firstNonWhitespaceIx != nil {
                        lastCandidateIx = ix
                        lastCandidateWidth = width
                    }
                } else {
                    if c != " " && firstNonWhitespaceIx != nil {
                        lastCandidateIx = ix
                        lastCandidateWidth = width
                    }
                }

                if c != " " && firstNonWhitespaceIx == nil {
                    firstNonWhitespaceIx = ix
                }

                newPrevC = c
                itemWidth = widthForChar(c)

            case .element(let elementWidth, _):
                if prevC == " " && firstNonWhitespaceIx != nil {
                    lastCandidateIx = ix
                    lastCandidateWidth = width
                }

                if firstNonWhitespaceIx == nil {
                    firstNonWhitespaceIx = ix
                }

                itemWidth = elementWidth
            }

            width += itemWidth
            if width > wrapWidth && ix > lastWrapIx {
                if indent == nil, let firstNonWs = firstNonWhitespaceIx {
                    let diff = UInt32(max(0, firstNonWs - lastWrapIx))
                    indent = min(Self.maxIndent, diff)
                }

                if lastCandidateIx > 0 {
                    lastWrapIx = lastCandidateIx
                    width -= lastCandidateWidth
                    lastCandidateIx = 0
                } else {
                    lastWrapIx = ix
                    width = itemWidth
                }

                if let ind = indent {
                    width += widthForChar(" ") * Float(ind)
                }

                boundaries.append(Boundary.new(ix: lastWrapIx, nextIndent: indent ?? 0))
            }

            prevC = newPrevC
        }

        return boundaries
    }

    public func shouldTruncateLine(
        line: String,
        truncateWidth: Pixels,
        truncationAffix: String,
        truncateFrom: TruncateFrom
    ) -> Int? {
        var width = px(0)
        var suffixWidth = px(0)
        for c in truncationAffix {
            suffixWidth += widthForChar(c)
        }

        var charIndices: [(Int, Character)] = []
        var byteOffset = 0
        for c in line {
            charIndices.append((byteOffset, c))
            byteOffset += c.utf8.count
        }

        var truncateIx = 0

        switch truncateFrom {
        case .start:
            for (ix, c) in charIndices.reversed() {
                if width + suffixWidth < truncateWidth {
                    truncateIx = ix
                }

                let charWidth = widthForChar(c)
                width += charWidth

                if floor(width.value) > truncateWidth.value {
                    return truncateIx
                }
            }
        case .end:
            for (ix, c) in charIndices {
                if width + suffixWidth < truncateWidth {
                    truncateIx = ix
                }

                let charWidth = widthForChar(c)
                width += charWidth

                if floor(width.value) > truncateWidth.value {
                    return truncateIx
                }
            }
        }

        return nil
    }

    public func truncateLine(
        line: SharedString,
        truncateWidth: Pixels,
        truncationAffix: String,
        runs: [TextRun],
        truncateFrom: TruncateFrom
    ) -> (SharedString, [TextRun]) {
        let lineStr = line.asString
        if let truncateIx = shouldTruncateLine(
            line: lineStr,
            truncateWidth: truncateWidth,
            truncationAffix: truncationAffix,
            truncateFrom: truncateFrom
        ) {
            let result: String
            switch truncateFrom {
            case .start:
                let targetByte = truncateIx + 1
                var ceilByte = lineStr.utf8.count
                var currentByte = 0
                for c in lineStr {
                    if currentByte >= targetByte {
                        ceilByte = currentByte
                        break
                    }
                    currentByte += c.utf8.count
                }
                let suffixUtf8 = lineStr.utf8.dropFirst(ceilByte)
                let suffixStr = String(suffixUtf8) ?? ""
                result = "\(truncationAffix)\(suffixStr)"

            case .end:
                let prefixUtf8 = lineStr.utf8.prefix(truncateIx)
                let prefixStr = String(prefixUtf8) ?? ""
                result = "\(prefixStr)\(truncationAffix)"
            }

            var updatedRuns = runs
            updateRunsAfterTruncation(
                result: result,
                ellipsis: truncationAffix,
                runs: &updatedRuns,
                truncateFrom: truncateFrom
            )
            return (SharedString(result), updatedRuns)
        } else {
            return (line, runs)
        }
    }

    public static func isWordChar(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            // ASCII alphanumeric
            if (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) {
                return true
            }
            // Latin-1 Supplement, Latin Extended-A, Latin Extended-B
            if (v >= 0x00C0 && v <= 0x00FF) || (v >= 0x0100 && v <= 0x017F) || (v >= 0x0180 && v <= 0x024F) {
                return true
            }
            // Cyrillic, Vietnamese Latin Extended Additional, Combining Diacritical Marks, Bengali
            if (v >= 0x0400 && v <= 0x04FF) || (v >= 0x1E00 && v <= 0x1EFF) || (v >= 0x0300 && v <= 0x036F) || (v >= 0x0980 && v <= 0x09FF) {
                return true
            }
        }
        switch c {
        case "-", "_", ".", "'", "$", "%", "@", "#", "^", "~", ",", "=", ":", "⋯":
            return true
        default:
            return false
        }
    }
}

public func updateRunsAfterTruncation(
    result: String,
    ellipsis: String,
    runs: inout [TextRun],
    truncateFrom: TruncateFrom
) {
    var truncateAt = result.utf8.count - ellipsis.utf8.count
    switch truncateFrom {
    case .start:
        for runIndex in stride(from: runs.count - 1, through: 0, by: -1) {
            if runs[runIndex].len <= truncateAt {
                truncateAt -= runs[runIndex].len
            } else {
                runs[runIndex].len = truncateAt + ellipsis.utf8.count
                runs.removeSubrange(..<runIndex)
                break
            }
        }
    case .end:
        for runIndex in 0..<runs.count {
            if runs[runIndex].len <= truncateAt {
                truncateAt -= runs[runIndex].len
            } else {
                runs[runIndex].len = truncateAt + ellipsis.utf8.count
                runs = Array(runs[0...runIndex])
                break
            }
        }
    }
}
