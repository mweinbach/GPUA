// Ported from: crates/rune/src/runtime/commit/text_layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Text shaping, line breaking (`wrap`, `wrapAnywhere`), clamping (`maxLines`), ellipsis/fade
//! truncation (`truncate`, `truncateFade`), alignment, and byte-offset <-> geometry queries.

struct TextLayoutCacheKey: Hashable, Sendable {
    var content: String
    var sizeBits: UInt32
    var weightBits: UInt32
    var lineHeightBits: UInt32
    var trackingBits: UInt32
    var family: Family
    var wrap: Bool
    var wrapAnywhere: Bool
    var truncate: Bool
    var maxLines: Int
    var truncateFade: Bool
    var fadeEmBits: UInt32
    var textCase: TextCase?
    var redacted: Bool
    var secureRevealed: Bool
    var maxWidthBits: UInt32
    var spanCount: Int
    var firstColorBits: UInt32
}

@inline(__always)
private func charAdvancePx(_ ch: Character, _ style: TextStyle, monoOverride: Bool = false, sizeOverride: Float? = nil) -> Float {
    let sz = sizeOverride ?? style.size
    let isMono = monoOverride || style.family == .mono || style.family == .systemMono
    if ch == "\t" {
        return (isMono ? sz * 0.6 : sz * 0.55) * 4.0 + style.tracking
    }
    let base: Float = isMono ? (sz * 0.6) : (sz * 0.55)
    return max(0.0, base + style.tracking)
}

func caretIndex(_ e: TextEdit, _ content: String) -> Int {
    let contentLen = content.utf8.count
    if let (p, sel) = e.preedit {
        let pLen = p.utf8.count
        if let (_, c) = sel {
            return min(e.range().0 + min(c, pLen), contentLen)
        } else {
            return min(e.range().0 + pLen, contentLen)
        }
    }
    return min(e.displayIndex(e.focus), contentLen)
}

func edited(_ was: String, _ now: String) -> Bool {
    let a = Array(was.utf8)
    let b = Array(now.utf8)
    guard a != b else { return false }
    var prefix = 0
    let minLen = min(a.count, b.count)
    while prefix < minLen && a[prefix] == b[prefix] {
        prefix += 1
    }
    var suffix = 0
    while suffix < (minLen - prefix) && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
        suffix += 1
    }
    return 2 * (prefix + suffix) >= max(a.count, b.count)
}

func makeTextLayoutCacheKey(_ spec: TextSpec, maxWidth: Float?) -> TextLayoutCacheKey {
    let quantizedWidth: Float = {
        guard let w = maxWidth, w.isFinite else { return -1.0 }
        return (max(w, 0.0) * 4.0).rounded() * 0.25
    }()
    let keyContent = (spec.redacted && !spec.secureRevealed)
        ? String(repeating: "•", count: spec.content.count)
        : spec.content
    return TextLayoutCacheKey(
        content: keyContent,
        sizeBits: spec.style.size.bitPattern,
        weightBits: spec.style.weight.bitPattern,
        lineHeightBits: spec.style.lineHeight.bitPattern,
        trackingBits: spec.style.tracking.bitPattern,
        family: spec.style.family,
        wrap: spec.wrap,
        wrapAnywhere: spec.wrapAnywhere,
        truncate: spec.truncate,
        maxLines: spec.maxLines,
        truncateFade: spec.truncateFade,
        fadeEmBits: spec.fadeEm.bitPattern,
        textCase: spec.textCase,
        redacted: spec.redacted,
        secureRevealed: spec.secureRevealed,
        maxWidthBits: quantizedWidth.bitPattern,
        spanCount: spec.spans.count,
        firstColorBits: spec.color.r.bitPattern ^ spec.color.g.bitPattern ^ spec.color.b.bitPattern ^ spec.color.a.bitPattern
    )
}

private struct ClusterToken {
    var ch: Character
    var sourceByteStart: Int
    var sourceByteLen: Int
    var advance: Float
    var color: Color
    var bg: Color?
    var bgPad: Float
    var underline: Color?
}

/// Lay out `TextSpec` within optional `maxWidth`, updating `textSys.shaped` / `textSys.rebroken`.
func layoutTextSpec(
    _ spec: TextSpec,
    maxWidth: Float?,
    textSys: TextSystem,
    previouslyShapedText: String? = nil
) -> RtTextLayout {
    if previouslyShapedText == spec.content {
        textSys.rebroken &+= 1
    } else {
        textSys.shaped &+= 1
    }

    let lineH = max(spec.style.linePx(), 1.0)
    let rawSource = spec.content

    // Apply TextCase or secure redaction while maintaining source UTF-8 byte offsets.
    var caseSource: TextCaseSource? = nil
    var caseUp = false
    let workingText: String
    if let tc = spec.textCase {
        let (shownStr, src) = TextCaseSource.new(tc, rawSource)
        caseSource = src
        caseUp = (tc == .uppercase)
        workingText = shownStr
    } else {
        workingText = rawSource
    }

    let shouldRedact = spec.redacted && !spec.secureRevealed

    // Build per-character tokens mapped back to source byte offsets.
    var tokens: [ClusterToken] = []
    tokens.reserveCapacity(workingText.count)

    var byteCursor = 0
    for ch in rawSource {
        let chByteLen = ch.utf8.count
        let displayChar: Character
        if shouldRedact && ch != "\n" {
            displayChar = "•"
        } else if let tc = spec.textCase {
            let s = tc == .uppercase ? String(ch).uppercased() : String(ch).lowercased()
            displayChar = s.first ?? ch
        } else {
            displayChar = ch
        }

        // Resolve span styling covering `[byteCursor, byteCursor + chByteLen)`
        var fg = spec.color
        var bg: Color? = nil
        var bgPad: Float = 0.0
        var underline: Color? = nil
        var mono = false
        var sizeOverride: Float? = nil
        let b32 = UInt32(byteCursor)
        for sp in spec.spans where sp.start <= b32 && b32 < sp.end {
            if let c = sp.color { fg = c }
            if let b = sp.bg {
                bg = b
                bgPad = sp.bgPad
            }
            if let u = sp.underline { underline = u }
            if sp.mono { mono = true }
            if let sz = sp.size { sizeOverride = sz }
        }
        // Apply highlight foreground overrides
        for hl in spec.highlights where hl.start <= b32 && b32 < hl.end {
            if let hfg = hl.fg { fg = hfg }
        }

        let adv = (ch == "\n") ? 0.0 : charAdvancePx(displayChar, spec.style, monoOverride: mono, sizeOverride: sizeOverride)
        tokens.append(
            ClusterToken(
                ch: displayChar,
                sourceByteStart: byteCursor,
                sourceByteLen: chByteLen,
                advance: adv,
                color: fg,
                bg: bg,
                bgPad: bgPad,
                underline: underline
            )
        )
        byteCursor += chByteLen
    }
    let totalBytes = byteCursor

    let effectiveWrapWidth: Float? = {
        guard let w = maxWidth, w.isFinite, w > 0.0 else { return nil }
        if spec.wrap || spec.truncate || spec.maxLines > 0 {
            return w
        }
        return nil
    }()

    // Split into hard paragraphs at `\n`, then wrap if `spec.wrap` is enabled.
    var rawLines: [(startByte: Int, endByte: Int, tokens: [ClusterToken])] = []
    var idx = 0
    while true {
        var paraTokens: [ClusterToken] = []
        let paraStartByte = idx < tokens.count ? tokens[idx].sourceByteStart : totalBytes
        while idx < tokens.count && tokens[idx].ch != "\n" {
            paraTokens.append(tokens[idx])
            idx += 1
        }
        let paraEndByte: Int
        if let last = paraTokens.last {
            paraEndByte = last.sourceByteStart + last.sourceByteLen
        } else {
            paraEndByte = paraStartByte
        }

        if spec.wrap, let limitW = effectiveWrapWidth, limitW > 0.0, !paraTokens.isEmpty {
            wrapParagraphTokens(
                paraTokens,
                limitWidth: limitW,
                wrapAnywhere: spec.wrapAnywhere,
                into: &rawLines
            )
        } else {
            rawLines.append((startByte: paraStartByte, endByte: paraEndByte, tokens: paraTokens))
        }

        if idx < tokens.count && tokens[idx].ch == "\n" {
            idx += 1
            if idx == tokens.count {
                // Trailing newline creates an empty final line at `totalBytes`.
                rawLines.append((startByte: totalBytes, endByte: totalBytes, tokens: []))
                break
            }
        } else {
            break
        }
    }

    if rawLines.isEmpty {
        rawLines.append((startByte: 0, endByte: 0, tokens: []))
    }

    // Clamp to `maxLines` (or 1 line when single-line `truncate` without `wrap`).
    let lineLimit: Int? = {
        if spec.maxLines > 0 {
            return spec.maxLines
        }
        if spec.truncate && !spec.wrap {
            return 1
        }
        return nil
    }()

    var wasClampedByLines = false
    if let limit = lineLimit, rawLines.count > limit {
        rawLines.removeSubrange(limit..<rawLines.count)
        wasClampedByLines = true
    }

    let ellipsisAdv = charAdvancePx("…", spec.style)
    var anyTruncated = false
    var widestLine: Float = 0.0
    var builtLines: [RtTextLine] = []
    builtLines.reserveCapacity(rawLines.count)

    for lineIdx in rawLines.indices {
        let entry = rawLines[lineIdx]
        let isLastLine = (lineIdx == rawLines.count - 1)
        var lineToks = entry.tokens
        var lineWidth: Float = lineToks.reduce(0.0) { $0 + $1.advance }
        var lineTruncated = false

        let needsEllipsisOrFade = (isLastLine && wasClampedByLines)
            || ((spec.truncate || (spec.maxLines > 0 && isLastLine))
                && (effectiveWrapWidth != nil && lineWidth > effectiveWrapWidth! + 0.01))

        if needsEllipsisOrFade, let limitW = effectiveWrapWidth {
            lineTruncated = true
            anyTruncated = true
            if spec.truncateFade {
                // Keep characters up to `limitW`; fade is applied in glyph alpha / clip fade.
                var kept: [ClusterToken] = []
                var w: Float = 0.0
                for tok in lineToks {
                    if w + tok.advance <= limitW || kept.isEmpty {
                        kept.append(tok)
                        w += tok.advance
                    } else {
                        break
                    }
                }
                lineToks = kept
                lineWidth = min(w, limitW)
            } else {
                // Standard ellipsis `…` truncation
                let budget = max(0.0, limitW - ellipsisAdv)
                var kept: [ClusterToken] = []
                var w: Float = 0.0
                for tok in lineToks {
                    if w + tok.advance <= budget {
                        kept.append(tok)
                        w += tok.advance
                    } else {
                        break
                    }
                }
                lineToks = kept
                lineWidth = w + ellipsisAdv
            }
        } else if isLastLine && wasClampedByLines {
            lineTruncated = true
            anyTruncated = true
            if !spec.truncateFade {
                lineWidth += ellipsisAdv
            }
        }

        let y = Float(lineIdx) * lineH
        var cursorX: Float = 0.0
        var glyphs: [RtGlyph] = []
        glyphs.reserveCapacity(lineToks.count + (lineTruncated ? 1 : 0))

        let fadeW: Float = (lineTruncated && spec.truncateFade) ? max(spec.fadeEm * spec.style.size, 1.0) : 0.0
        let fadeStartX: Float = (effectiveWrapWidth ?? lineWidth) - fadeW

        for tok in lineToks {
            var alpha: Float = 1.0
            if fadeW > 0.0 {
                let midX = cursorX + tok.advance * 0.5
                if midX > fadeStartX {
                    alpha = min(max(1.0 - (midX - fadeStartX) / fadeW, 0.0), 1.0)
                }
            }
            glyphs.append(
                RtGlyph(
                    byteOffset: tok.sourceByteStart,
                    byteLen: tok.sourceByteLen,
                    x: cursorX,
                    y: y,
                    advance: tok.advance,
                    height: lineH,
                    color: tok.color,
                    bg: tok.bg,
                    bgPad: tok.bgPad,
                    underline: tok.underline,
                    alpha: alpha,
                    isEllipsis: false
                )
            )
            cursorX += tok.advance
        }

        if lineTruncated && !spec.truncateFade {
            let ellByte = lineToks.last.map { $0.sourceByteStart + $0.sourceByteLen } ?? entry.startByte
            glyphs.append(
                RtGlyph(
                    byteOffset: ellByte,
                    byteLen: 0,
                    x: cursorX,
                    y: y,
                    advance: ellipsisAdv,
                    height: lineH,
                    color: spec.color,
                    bg: nil,
                    bgPad: 0.0,
                    underline: nil,
                    alpha: 1.0,
                    isEllipsis: true
                )
            )
            cursorX += ellipsisAdv
        }

        let endByte: Int
        if let lastReal = lineToks.last {
            endByte = lastReal.sourceByteStart + lastReal.sourceByteLen
        } else {
            endByte = entry.startByte
        }

        widestLine = max(widestLine, cursorX)
        builtLines.append(
            RtTextLine(
                byteStart: entry.startByte,
                byteEnd: endByte,
                x: 0.0,
                y: y,
                width: cursorX,
                height: lineH,
                truncated: lineTruncated,
                glyphs: glyphs
            )
        )
    }

    let totalHeight = Float(max(builtLines.count, 1)) * lineH
    let fadePx: Float = (anyTruncated && spec.truncateFade) ? max(spec.fadeEm * spec.style.size, 0.0) : 0.0

    return RtTextLayout(
        text: rawSource,
        displayText: shouldRedact ? String(repeating: "•", count: rawSource.count) : workingText,
        lines: builtLines,
        width: widestLine,
        height: totalHeight,
        lineHeight: lineH,
        truncated: anyTruncated,
        truncatedFadeWidth: fadePx,
        caseSource: caseSource,
        caseUp: caseUp
    )
}

private func wrapParagraphTokens(
    _ tokens: [ClusterToken],
    limitWidth: Float,
    wrapAnywhere: Bool,
    into out: inout [(startByte: Int, endByte: Int, tokens: [ClusterToken])]
) {
    if wrapAnywhere {
        var current: [ClusterToken] = []
        var curW: Float = 0.0
        for tok in tokens {
            if !current.isEmpty && curW + tok.advance > limitWidth + 0.01 {
                let s = current.first!.sourceByteStart
                let e = current.last!.sourceByteStart + current.last!.sourceByteLen
                out.append((startByte: s, endByte: e, tokens: current))
                current = [tok]
                curW = tok.advance
            } else {
                current.append(tok)
                curW += tok.advance
            }
        }
        if !current.isEmpty {
            let s = current.first!.sourceByteStart
            let e = current.last!.sourceByteStart + current.last!.sourceByteLen
            out.append((startByte: s, endByte: e, tokens: current))
        }
        return
    }

    // Word-boundary wrapping with character-level fallback for words wider than `limitWidth`.
    var i = 0
    var current: [ClusterToken] = []
    var curW: Float = 0.0

    func flushLine() {
        guard !current.isEmpty else { return }
        // Trim trailing spaces from wrapped line width if desired, keeping source byte range intact
        let s = current.first!.sourceByteStart
        let e = current.last!.sourceByteStart + current.last!.sourceByteLen
        out.append((startByte: s, endByte: e, tokens: current))
        current.removeAll(keepingCapacity: true)
        curW = 0.0
    }

    while i < tokens.count {
        if tokens[i].ch.isWhitespace {
            // Space token
            let sp = tokens[i]
            if current.isEmpty {
                // Skip leading spaces at a soft wrap boundary unless it's the very first token of paragraph
                if out.isEmpty {
                    current.append(sp)
                    curW += sp.advance
                }
            } else if curW + sp.advance <= limitWidth + 0.01 {
                current.append(sp)
                curW += sp.advance
            } else {
                flushLine()
            }
            i += 1
            continue
        }

        // Collect contiguous word tokens
        var wordEnd = i
        var wordW: Float = 0.0
        while wordEnd < tokens.count && !tokens[wordEnd].ch.isWhitespace {
            wordW += tokens[wordEnd].advance
            wordEnd += 1
        }
        let wordSlice = tokens[i..<wordEnd]

        if !current.isEmpty && curW + wordW > limitWidth + 0.01 {
            flushLine()
        }

        if wordW <= limitWidth + 0.01 {
            current.append(contentsOf: wordSlice)
            curW += wordW
        } else {
            // Break long word by character so it never overflows `limitWidth`
            for tok in wordSlice {
                if !current.isEmpty && curW + tok.advance > limitWidth + 0.01 {
                    flushLine()
                }
                current.append(tok)
                curW += tok.advance
            }
        }
        i = wordEnd
    }

    if !current.isEmpty {
        flushLine()
    }
}

/// Apply horizontal alignment (`.start`, `.center`, `.end`) once final node width is known.
func alignTextLayout(_ layout: inout RtTextLayout, containerWidth: Float, align: Align) {
    for idx in layout.lines.indices {
        let lw = layout.lines[idx].width
        let targetX: Float
        switch align {
        case .start:
            targetX = 0.0
        case .center:
            targetX = max(0.0, (containerWidth - lw) * 0.5)
        case .end:
            targetX = max(0.0, containerWidth - lw)
        }
        let dx = targetX - layout.lines[idx].x
        if abs(dx) > 1e-4 {
            layout.lines[idx].x = targetX
            for g in layout.lines[idx].glyphs.indices {
                layout.lines[idx].glyphs[g].x += dx
            }
        }
    }
}
