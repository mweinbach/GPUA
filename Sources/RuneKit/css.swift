// Ported from: crates/rune-kit/src/css.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Reading theme data authored for the web: computed CSS `box-shadow` lists.

import Rune

/// Namespace mirroring `rune_kit::css` module exports.
public enum css {
    /// Parses a computed `box-shadow` list (`#rrggbbaa 0px 1px 1.5px 0px [inset], ...`). Colours
    /// go through `color` (so a theme can re-solve translucency); fully transparent layers drop.
    public static func boxShadows(_ src: String, _ color: (Color) -> Color) -> [Shadow] {
        var out: [Shadow] = []
        for layer in splitLayers(src) {
            var c: Color? = nil
            var nums: [Float] = []
            var inset = false
            for rawTok in layer.split(whereSeparator: \.isWhitespace) {
                let tok = String(rawTok)
                if tok == "inset" {
                    inset = true
                } else if tok.hasPrefix("#") {
                    c = Rune.theme.hex(tok)
                } else {
                    let trimmed = tok.hasSuffix("px") ? String(tok.dropLast(2)) : tok
                    if let v = Float(trimmed) {
                        nums.append(v)
                    }
                }
            }
            guard let resolved = c, resolved.a > 0.0 else { continue }
            @inline(__always)
            func n(_ i: Int) -> Float {
                i < nums.count ? nums[i] : 0.0
            }
            out.append(Shadow(x: n(0), y: n(1), blur: n(2), spread: n(3), color: color(resolved), inset: inset))
        }
        return out
    }
}

private func splitLayers(_ src: String) -> [String] {
    var depth = 0
    var start = src.startIndex
    var out: [String] = []
    var i = src.startIndex
    while i < src.endIndex {
        let ch = src[i]
        if ch == "(" {
            depth += 1
        } else if ch == ")" {
            depth -= 1
        } else if ch == "," && depth == 0 {
            out.append(src[start..<i].trimmingCharacters(in: .whitespacesAndNewlines))
            start = src.index(after: i)
        }
        i = src.index(after: i)
    }
    out.append(src[start...].trimmingCharacters(in: .whitespacesAndNewlines))
    return out
}

extension Substring {
    fileprivate func trimmingCharacters(in _: _AsciiWhitespace) -> String {
        var s = startIndex
        var e = endIndex
        while s < e && self[s].isWhitespace {
            s = index(after: s)
        }
        while e > s {
            let prev = index(before: e)
            if self[prev].isWhitespace {
                e = prev
            } else {
                break
            }
        }
        return String(self[s..<e])
    }
}

private enum _AsciiWhitespace {
    case whitespacesAndNewlines
}
