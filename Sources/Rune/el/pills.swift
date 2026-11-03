// Ported from: crates/rune/src/el/pills.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.pill` and `El.pills`: rounded chips around byte ranges of static text, drawn and
//! wrapped like a `textInput`'s `Mark.pill` chips.

extension El {
    /// Draws bytes `range` of a `text` or `rich` element as a pill: a rounded chip in `style`'s
    /// colour with its label in `style`'s text colour and its icon before it.
    public func pill(_ range: Range<Int>, _ style: PillStyle) -> El {
        pills([(range, style)])
    }

    /// ``pill(_:_:)`` for several ranges.
    public func pills<S: Swift.Sequence>(_ pills: S) -> El where S.Element == (Range<Int>, PillStyle) {
        if input != nil {
            return self
        }
        var copy = self
        guard copy.textSpec != nil else { return copy }
        copy.textSpec?.modify { t in
            let len = t.content.utf8.count
            for (r, st) in pills {
                let ok = r.lowerBound >= 0
                    && r.lowerBound < r.upperBound
                    && r.upperBound <= len
                    && isUtf8ScalarBoundary(t.content, r.lowerBound)
                    && isUtf8ScalarBoundary(t.content, r.upperBound)
                guard ok else { continue }
                let start = UInt32(r.lowerBound)
                let end = UInt32(r.upperBound)
                if t.pills.contains(where: { $0.start < end && start < $0.end }) {
                    continue
                }
                let at = t.pills.firstIndex(where: { $0.start >= start }) ?? t.pills.count
                t.pills.insert(
                    PillChip(start: start, end: end, icon: st.leadingIcon, bg: st.bgColor, fg: st.fgColor),
                    at: at
                )
            }
            t.spans = withPillColors(t.spans, t.pills)
        }
        return copy
    }
}

/// `spans` with each pill's label colour over it.
func withPillColors(_ spans: [Span], _ pills: [PillChip]) -> [Span] {
    if pills.allSatisfy({ $0.fg == nil }) {
        return flattenSpans(spans)
    }
    var all = spans
    for p in pills {
        if let fg = p.fg {
            var sp = Span(start: Int(p.start), end: Int(p.end))
            sp.color = fg
            all.append(sp)
        }
    }
    return flattenSpans(all)
}

private func isUtf8ScalarBoundary(_ s: String, _ byteOffset: Int) -> Bool {
    let utf8 = s.utf8
    guard byteOffset >= 0 && byteOffset <= utf8.count else { return false }
    if byteOffset == 0 || byteOffset == utf8.count { return true }
    let idx = utf8.index(utf8.startIndex, offsetBy: byteOffset)
    return (utf8[idx] & 0xC0) != 0x80
}
