// Ported from: crates/rune/src/edit/display.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a `TextEdit` draws: the display text with any preedit spliced in, and the spans,
//! links, pills and blocks mapped onto it.

extension TextEdit {
    /// Map a model byte range `start..<end` (in `self.text`) onto `self.display().0` byte ranges,
    /// shifting or splitting around any active IME `preedit` splice.
    func mapRangeToDisplay(_ start: Int, _ end: Int) -> [(UInt32, UInt32)] {
        if (secureFlag && !revealedFlag) || start >= end {
            return []
        }
        let s = Self.clampCharBoundary(text, start)
        let e = Self.clampCharBoundary(text, end)
        if s >= e {
            return []
        }
        guard let (p, _) = preedit else {
            return [(UInt32(s), UInt32(e))]
        }
        let (a, b) = range()
        let delLen = b - a
        let insLen = p.utf8.count
        if e <= a {
            return [(UInt32(s), UInt32(e))]
        } else if s >= b {
            return [(UInt32(s - delLen + insLen), UInt32(e - delLen + insLen))]
        } else {
            var out: [(UInt32, UInt32)] = []
            if s < a {
                out.append((UInt32(s), UInt32(a)))
            }
            if e > b {
                out.append((UInt32(a + insLen), UInt32(e - delLen + insLen)))
            }
            return out
        }
    }

    /// Build the `Span`s, strikethrough ranges, `Link`s, and per-line `Block`s for
    /// `self.display()` so `textInput` renders inline marks, pending IME style, and blocks.
    func richDisplaySpecs(
        _ baseStyle: TextStyle,
        _ style: RichStyle
    ) -> ([Span], [(UInt32, UInt32, Color?)], [Link], [Block]) {
        if secureFlag {
            return ([], [], [], [])
        }
        var spans: [Span] = []
        var strikes: [(UInt32, UInt32, Color?)] = []
        var links: [Link] = []

        func pushMarkSpan(_ rStart: UInt32, _ rEnd: UInt32, _ mark: Mark) {
            if rStart >= rEnd {
                return
            }
            switch mark {
            case .bold:
                let w = min(max(baseStyle.weight + 250.0, 600.0), 900.0)
                spans.append(Span(start: Int(rStart), end: Int(rEnd), weight: w))
            case .italic:
                spans.append(Span(start: Int(rStart), end: Int(rEnd), italic: true))
            case .underline:
                spans.append(Span(start: Int(rStart), end: Int(rEnd), underline: Color.TRANSPARENT))
            case .strike:
                strikes.append((rStart, rEnd, nil))
            case .code:
                spans.append(Span(
                    start: Int(rStart),
                    end: Int(rEnd),
                    mono: true,
                    color: style.codeFg,
                    bg: style.codeBg,
                    bgPad: 2.0
                ))
            case .link(let url):
                spans.append(Span(
                    start: Int(rStart),
                    end: Int(rEnd),
                    color: style.link,
                    underline: style.link.alpha(0.65)
                ))
                links.append(Link.new(Int(rStart)..<Int(rEnd), url))
            case .pill:
                // The chip and its colours come from `displayPills`.
                break
            }
        }

        for m in marksStorage {
            for (ds, de) in mapRangeToDisplay(m.start, m.end) {
                pushMarkSpan(ds, de, m.mark)
            }
        }

        // If IME preedit is active, style the preedit range with `self.activeMarks()` (which
        // includes any pending typing style or inherited marks at the caret).
        if let (p, _) = preedit, !p.isEmpty {
            let (a, _) = range()
            let ps = UInt32(a)
            let pe = UInt32(a + p.utf8.count)
            for m in activeMarks() where !m.isPill {
                pushMarkSpan(ps, pe, m)
            }
        }

        // Compute display blocks per `\n`-separated line of `display().0`, and add `mono: true`
        // spans for any `Block.code` lines.
        let (dispText, _) = display()
        let dispBytes = Array(dispText.utf8)
        let dispBlocks = displayBlocks(dispText)
        var lineStart = 0
        var lineIdx = 0
        for i in 0..<dispBytes.count where dispBytes[i] == UInt8(ascii: "\n") {
            if lineIdx < dispBlocks.count && dispBlocks[lineIdx] == .code && lineStart < i {
                spans.append(Span(
                    start: lineStart,
                    end: i,
                    mono: true,
                    color: style.codeFg
                ))
            }
            lineStart = i + 1
            lineIdx += 1
        }
        if lineIdx < dispBlocks.count && dispBlocks[lineIdx] == .code && lineStart < dispBytes.count {
            spans.append(Span(
                start: lineStart,
                end: dispBytes.count,
                mono: true,
                color: style.codeFg
            ))
        }

        return (spans, strikes, links, dispBlocks)
    }

    /// Each `Mark.pill`'s byte range in `self.display().0`, with its id.
    func displayPills() -> [(UInt32, UInt32, String)] {
        if secureFlag {
            return []
        }
        if preedit == nil {
            var out: [(UInt32, UInt32, String)] = []
            for m in marksStorage {
                guard let id = m.mark.pillId() else { continue }
                let s = Self.clampCharBoundary(text, m.start)
                let e = Self.clampCharBoundary(text, m.end)
                if s < e && e - s == m.end - m.start {
                    out.append((UInt32(s), UInt32(e), id))
                }
            }
            return out
        }
        var out: [(UInt32, UInt32, String)] = []
        for m in marksStorage {
            guard let id = m.mark.pillId() else { continue }
            let mapped = mapRangeToDisplay(m.start, m.end)
            if mapped.count == 1 {
                let (s, e) = mapped[0]
                if Int(e - s) == m.end - m.start {
                    out.append((s, e, id))
                }
            }
        }
        return out
    }

    func displayBlocks(_ dispText: String) -> [Block] {
        let lineCount = 1 + editCountNewlines(dispText)
        if blocksStorage.isEmpty {
            return Array(repeating: .paragraph, count: lineCount)
        }
        if preedit == nil {
            var out = blocksStorage
            if out.count < lineCount {
                out.append(contentsOf: repeatElement(.paragraph, count: lineCount - out.count))
            } else if out.count > lineCount {
                out.removeLast(out.count - lineCount)
            }
            return out
        }
        let (a, b) = range()
        let lineA = lineOfByte(a)
        let lineB = lineOfByte(b)
        var out = blocksStorage
        if lineB > lineA && lineB < out.count {
            out.removeSubrange((lineA + 1)...lineB)
        }
        let padBlock = lineA < out.count ? out[lineA] : .paragraph
        if out.count < lineCount {
            out.append(contentsOf: repeatElement(padBlock, count: lineCount - out.count))
        } else if out.count > lineCount {
            out.removeLast(out.count - lineCount)
        }
        return out
    }

    /// The text to lay out: committed text with any preedit spliced in at the caret, and the
    /// UTF-8 byte range of the preedit within it.
    public func display() -> (String, (Int, Int)?) {
        if secureFlag {
            let masked: String
            if revealedFlag {
                masked = text
            } else if isSingleLine {
                masked = String(repeating: "•", count: text.unicodeScalars.count)
            } else if text.isEmpty {
                masked = ""
            } else {
                masked = MULTILINE_SECURE_MASK
            }
            return (masked, nil)
        }
        if let (p, _) = preedit {
            let (a, b) = range()
            let s = editReplaceUtf8Range(Array(text.utf8), a..<b, p)
            return (s, (a, a + p.utf8.count))
        }
        return (text, nil)
    }
}
