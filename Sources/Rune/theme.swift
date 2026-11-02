// Ported from: crates/rune/src/theme.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Themes as data. A theme file names a palette and, per appearance, semantic tokens that point
//! at palette entries (or literal colours) plus plain numbers.

import Foundation

// PORT NOTE: Thread-local blend mode uses `Thread.current.threadDictionary` on multi-threaded targets
// and a single-threaded variable on WASI, matching Rust's `thread_local! { static SRGB: Cell<bool> }`.
#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; `srgbBlendStorage` is accessed on the sole execution thread.
nonisolated(unsafe) private var srgbBlendStorage: Bool = true
#endif

private let srgbThreadKey = "gpua.rune.theme.srgbBlend"

@inline(__always)
private func getThreadSrgb() -> Bool {
    #if os(WASI)
    return srgbBlendStorage
    #else
    if let val = Thread.current.threadDictionary[srgbThreadKey] as? Bool {
        return val
    }
    return true
    #endif
}

@inline(__always)
private func setThreadSrgb(_ value: Bool) -> Bool {
    let previous = getThreadSrgb()
    #if os(WASI)
    srgbBlendStorage = value
    #else
    Thread.current.threadDictionary[srgbThreadKey] = value
    #endif
    return previous
}

/// Whether colours resolve for sRGB-space blending on this thread.
public func blendsSrgb() -> Bool {
    getThreadSrgb()
}

/// Runs `f` with colours resolving for `srgb` blending, then restores the mode before it.
public func withBlend<R>(_ srgb: Bool, _ f: () throws -> R) rethrows -> R {
    let prev = setThreadSrgb(srgb)
    defer { _ = setThreadSrgb(prev) }
    return try f()
}

/// `c`, authored for sRGB blending (as CSS colours are), as it should be painted over the
/// opaque `bg` in the current blend mode (``blendsSrgb()``).
public func forBlend(_ c: Color, _ bg: Color) -> Color {
    blendsSrgb() ? c : srgbEquivalent(c, bg)
}

/// Compensate a translucent colour authored for sRGB blending, for a known opaque backdrop,
/// in a window that blends in linear light (`App.srgbBlend(false)`).
public func srgbEquivalent(_ c: Color, _ bg: Color) -> Color {
    if c.a >= 0.999 || c.a <= 0.0 {
        return c
    }
    @inline(__always)
    func ch(_ cv: Float, _ bv: Float) -> (Float, Float, Float) {
        let t = c.a * srgbEncode(cv) + (1.0 - c.a) * srgbEncode(bv)
        return (srgbDecode(t), cv, bv)
    }
    let parts = [ch(c.r, bg.r), ch(c.g, bg.g), ch(c.b, bg.b)]
    let w: [Float] = [0.2126, 0.7152, 0.0722]
    var num: Float = 0.0
    var den: Float = 0.0
    for i in 0..<3 {
        let (t, cv, bv) = parts[i]
        let d = cv - bv
        num += w[i] * d * (t - bv)
        den += w[i] * d * d
    }
    let resolvedAlpha: Float = den > 1e-9 ? min(max(num / den, 0.0), 1.0) : c.a
    return Color(r: c.r, g: c.g, b: c.b, a: resolvedAlpha)
}

public struct ThemeError: Error, CustomStringConvertible, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Data-driven theme loaded from JSON (`crates/rune/src/theme.rs`).
public struct Theme: Sendable, Equatable {
    public var name: String
    public var dark: Bool
    private var blendBg: Color?
    private var colors: [String: Color]
    private var numbers: [String: Float]

    public init(
        name: String,
        dark: Bool,
        blendBg: Color? = nil,
        colors: [String: Color] = [:],
        numbers: [String: Float] = [:]
    ) {
        self.name = name
        self.dark = dark
        self.blendBg = blendBg
        self.colors = colors
        self.numbers = numbers
    }

    public static func fromJson(_ src: String, _ dark: Bool) -> Result<Theme, ThemeError> {
        guard let data = src.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failure(ThemeError("theme: invalid JSON object"))
        }
        let palette = raw["palette"] as? [String: Any]
        let mode = dark ? "dark" : "light"
        guard let tokens = raw[mode] as? [String: Any] else {
            return .failure(ThemeError("theme: no \"\(mode)\" section"))
        }

        func resolve(_ val: String) -> Result<Color, ThemeError> {
            if let c = hex(val) {
                return .success(c)
            }
            guard let p = palette?[val] as? String else {
                return .failure(ThemeError("theme: unknown colour \(val)"))
            }
            guard let c = hex(p) else {
                return .failure(ThemeError("theme: bad hex \(p) for \(val)"))
            }
            return .success(c)
        }

        var colors: [String: Color] = [:]
        for (k, val) in tokens {
            guard let s = val as? String else { continue }
            switch resolve(s) {
            case .success(let c):
                colors[k] = c
            case .failure(let err):
                return .failure(ThemeError("\(err.message) (token \(k))"))
            }
        }
        if let palette {
            for (k, val) in palette where colors[k] == nil {
                if let s = val as? String, let c = hex(s) {
                    colors[k] = c
                }
            }
        }
        var blendBg: Color? = nil
        if let blend = raw["blend"] as? [String: Any],
           (blend["mode"] as? String) == "srgb"
        {
            let overKey = (blend["over"] as? String) ?? ""
            blendBg = colors[overKey]
        }
        var numbers: [String: Float] = [:]
        if let nums = raw["numbers"] as? [String: Any] {
            for (k, val) in nums {
                if let n = val as? NSNumber {
                    numbers[k] = n.floatValue
                } else if let d = val as? Double {
                    numbers[k] = Float(d)
                }
            }
        }
        let name = (raw["name"] as? String) ?? "theme"
        return .success(Theme(name: name, dark: dark, blendBg: blendBg, colors: colors, numbers: numbers))
    }

    /// A colour token for the current blend mode (``blendsSrgb()``), or nil.
    public func tryColor(_ name: String) -> Color? {
        guard let c = colors[name] else { return nil }
        return blended(c)
    }

    /// A colour token for the current blend mode (``blendsSrgb()``). Traps naming closest tokens when missing.
    public func color(_ name: String) -> Color {
        if let c = tryColor(name) {
            return c
        }
        let suffix = String(name.split(separator: "-").last ?? Substring(name))
        let near = colors.keys.filter { $0.contains(suffix) }.sorted().prefix(6)
        preconditionFailure("theme \(self.name) has no colour \(name); similar: \(Array(near))")
    }

    /// `c` at opacity `a`, re-solved when the window blends in linear light and the theme's colours are sRGB-authored.
    public func alpha(_ c: Color, _ a: Float) -> Color {
        blended(c.alpha(a))
    }

    private func blended(_ c: Color) -> Color {
        if let bg = blendBg {
            return forBlend(c, bg)
        }
        return c
    }

    public func tryNum(_ name: String) -> Float? {
        numbers[name]
    }

    public func num(_ name: String) -> Float {
        guard let v = numbers[name] else {
            preconditionFailure("theme \(self.name) has no number \(name)")
        }
        return v
    }
}

/// Namespace mirroring `rune::theme` module exports.
public enum theme {
    public typealias Theme = Rune.Theme
    public static func blendsSrgb() -> Bool { Rune.blendsSrgb() }
    public static func withBlend<R>(_ srgb: Bool, _ f: () throws -> R) rethrows -> R { try Rune.withBlend(srgb, f) }
    public static func forBlend(_ c: Color, _ bg: Color) -> Color { Rune.forBlend(c, bg) }
    public static func srgbEquivalent(_ c: Color, _ bg: Color) -> Color { Rune.srgbEquivalent(c, bg) }
    public static func hex(_ s: String) -> Color? { Rune.hex(s) }
}
