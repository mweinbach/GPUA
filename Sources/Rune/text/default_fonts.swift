// Ported from: crates/rune/src/text/default_fonts.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Default fallback faces and pure-Swift built-in vector glyph outlines for environments where
//! bundled `.ttf` assets or system fonts are unavailable (such as WASI or minimal containers).

// PORT NOTE: Upstream `default_fonts.rs` embeds ~1.4 MiB of Inter & IBM Plex Mono `.ttf` binaries via
// `include_bytes!`. Because `Package.swift` does not attach `.ttf` resources to `Rune`, on Apple
// platforms `TextSystem` maps uninstalled `"Inter"` / `"IBM Plex Mono"` to guaranteed static system
// faces (`Helvetica Neue` / `Menlo`), on Linux/Windows/Android it scans system TrueType fonts, and
// on all platforms `BuiltinVectorFont` provides deterministic proportional-sans and monospace
// vector outlines (`upem = 1000`) so shaping, metrics, ink bounds, and glyph rasterization always succeed.

#if !os(WASI)
import Foundation

private let defaultFontsLock = LiveLock()
// PORT NOTE: Guarded by `defaultFontsLock`; memoizes the bundled Inter `.ttf` byte arrays once per process.
nonisolated(unsafe) private var cachedDefaultFonts: [[UInt8]]? = nil

/// Resolves `.upstream/rune/crates/rune` when running inside the GPUA checkout or any git worktree of it.
func upstreamRuneCrateDir(filePath: String = #filePath) -> URL? {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent() // text
        .deletingLastPathComponent() // Rune
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // repo / worktree root

    let direct = dir.appendingPathComponent(".upstream/rune/crates/rune")
    if fm.fileExists(atPath: direct.path) {
        return direct
    }
    let dotGit = dir.appendingPathComponent(".git")
    if let gitText = try? String(contentsOf: dotGit, encoding: .utf8) {
        let trimmed = gitText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("gitdir:") {
            let raw = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            if let range = raw.range(of: "/.git/worktrees/") {
                let mainRoot = String(raw[..<range.lowerBound])
                let candidate = URL(fileURLWithPath: mainRoot).appendingPathComponent(".upstream/rune/crates/rune")
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
    }
    while dir.path != "/" && !dir.path.isEmpty {
        let candidate = dir.appendingPathComponent(".upstream/rune/crates/rune")
        if fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    return nil
}

func defaultFontBlobs() -> [[UInt8]] {
    defaultFontsLock.withLock {
        if let cached = cachedDefaultFonts {
            return cached
        }
        let names = ["Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf"]
        var dirs: [URL] = []
        if let envDir = ProcessInfo.processInfo.environment["RUNE_ASSETS_DIR"], !envDir.isEmpty {
            dirs.append(URL(fileURLWithPath: envDir))
        }
        if let crateDir = upstreamRuneCrateDir() {
            dirs.append(crateDir.appendingPathComponent("assets"))
        }
        var loaded: [[UInt8]] = []
        for base in dirs {
            var batch: [[UInt8]] = []
            for name in names {
                let url = base.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    batch.append([UInt8](data))
                }
            }
            if batch.count == names.count {
                loaded = batch
                break
            }
        }
        cachedDefaultFonts = loaded
        return loaded
    }
}
#else
func defaultFontBlobs() -> [[UInt8]] {
    []
}
#endif

enum BuiltinFontKind: UInt64, Sendable, Equatable, Hashable {
    case sans = 0xB011_7100_0000_0001
    case mono = 0xB011_7100_0000_0002
}

enum BuiltinVectorFont {
    static let upem: Double = 1000.0
    static let ascent: Float = 800.0
    static let descent: Float = 200.0
    static let lineGap: Float = 0.0

    static let hintMetrics = HintMetrics(
        upem: 1000.0,
        xHeight: 520.0,
        capHeight: 720.0,
        maxY: 850.0,
        stemHeight: 0.0
    )

    static func glyphId(for scalar: UnicodeScalar) -> UInt16 {
        let v = scalar.value
        if v == 0x20 || v == 0xA0 || v == 0x202F || v == 0x09 || v == 0x0A || v == 0x0D {
            return 1 // whitespace glyph (empty outline)
        }
        if v < 0xFFFE {
            return UInt16(max(2, v))
        }
        return UInt16(0x8000 | (v & 0x7FFF))
    }

    static func advanceUnits(for scalar: UnicodeScalar, mono: Bool, weight: Float) -> Float {
        if mono {
            return 600.0
        }
        let v = scalar.value
        let weightBonus: Float = weight > 450.0 ? min((weight - 400.0) * 0.12, 48.0) : 0.0
        if v == 0x20 || v == 0xA0 {
            return 260.0
        }
        if v == 0x202F {
            return 160.0
        }
        switch scalar {
        case "i", "l", "I", "!", ".", ",", ":", ";", "'", "|":
            return 270.0 + weightBonus * 0.6
        case "j", "f", "t", "r", "(", ")", "[", "]":
            return 350.0 + weightBonus * 0.7
        case "m", "w", "M", "W", "@", "%":
            return 830.0 + weightBonus
        default:
            if (0x3000...0x9FFF).contains(v) || (0xAC00...0xD7AF).contains(v) || (0x1F300...0x1FAFF).contains(v) {
                return 1000.0
            }
            if scalar >= "A" && scalar <= "Z" {
                return 650.0 + weightBonus
            }
            if scalar >= "0" && scalar <= "9" {
                return 580.0 + weightBonus * 0.8
            }
            return 540.0 + weightBonus * 0.85
        }
    }

    static func designOutline(glyph: UInt16, mono: Bool, weight: Float, ppem: Double) -> MacosPath {
        if glyph <= 1 {
            return []
        }
        let scale = ppem / upem
        let scalarVal = UInt32(glyph)
        let scalar = UnicodeScalar(scalarVal) ?? UnicodeScalar(0x3F)!
        let adv = Double(advanceUnits(for: scalar, mono: mono, weight: weight))
        let stemBase = 84.0 + max(0.0, Double(weight - 400.0) * 0.14)
        let stem = min(stemBase, adv * 0.28)
        let padX = max(36.0, adv * 0.11)
        let x0 = padX
        let x1 = max(x0 + stem, adv - padX)
        let xm = 0.5 * (x0 + x1)

        var cmds: MacosPath = []
        func rect(_ lx: Double, _ by: Double, _ rx: Double, _ ty: Double) {
            guard rx > lx, ty > by else { return }
            cmds.append(.move(MacosPoint(lx * scale, by * scale)))
            cmds.append(.line(MacosPoint(lx * scale, ty * scale)))
            cmds.append(.line(MacosPoint(rx * scale, ty * scale)))
            cmds.append(.line(MacosPoint(rx * scale, by * scale)))
            cmds.append(.close)
        }

        // Character-class aware distinct silhouettes so ink bounds, baselines, ascenders, descenders,
        // punctuation, and glyph comparisons behave realistically across tests.
        switch scalar {
        case ".":
            rect(xm - stem * 0.6, 0.0, xm + stem * 0.6, stem * 1.3)
        case ",":
            rect(xm - stem * 0.6, -120.0, xm + stem * 0.6, stem * 1.2)
        case "-", "\u{2010}", "\u{2013}", "\u{2014}":
            rect(x0, 260.0, x1, 260.0 + stem)
        case "_":
            rect(x0, -80.0, x1, -80.0 + stem)
        case "=":
            rect(x0, 190.0, x1, 190.0 + stem * 0.85)
            rect(x0, 360.0, x1, 360.0 + stem * 0.85)
        case "'", "\"":
            rect(xm - stem * 0.5, 480.0, xm + stem * 0.5, 720.0)
        case "H":
            rect(x0, 0.0, x0 + stem, 720.0)
            rect(x1 - stem, 0.0, x1, 720.0)
            rect(x0, 320.0, x1, 320.0 + stem)
        case "I", "l", "|":
            rect(xm - stem * 0.5, 0.0, xm + stem * 0.5, 720.0)
        case "L":
            rect(x0, 0.0, x0 + stem, 720.0)
            rect(x0, 0.0, x1, stem)
        case "T":
            rect(xm - stem * 0.5, 0.0, xm + stem * 0.5, 720.0)
            rect(x0, 720.0 - stem, x1, 720.0)
        case "E", "F":
            rect(x0, 0.0, x0 + stem, 720.0)
            rect(x0, 720.0 - stem, x1, 720.0)
            rect(x0, 330.0, x1 - stem * 0.4, 330.0 + stem * 0.9)
            if scalar == "E" {
                rect(x0, 0.0, x1, stem)
            }
        case "p", "q", "g", "y", "j":
            // Lowercase with descender
            let stemX0 = (scalar == "p") ? x0 : (x1 - stem)
            rect(stemX0, -190.0, stemX0 + stem, 520.0)
            rect(x0, 0.0, x1, stem * 0.9)
            rect(x0, 520.0 - stem * 0.9, x1, 520.0)
            if scalar == "p" {
                rect(x1 - stem, 0.0, x1, 520.0)
            } else {
                rect(x0, 0.0, x0 + stem, 520.0)
            }
        case "b", "d", "h", "k", "f", "t":
            // Lowercase with ascender
            let top = (scalar == "t") ? 640.0 : 740.0
            let barX = (scalar == "d") ? (x1 - stem) : x0
            rect(barX, 0.0, barX + stem, top)
            rect(x0, 0.0, x1, stem * 0.9)
            rect(x0, 520.0 - stem * 0.9, x1, 520.0)
        default:
            let isUpperOrDigit = (scalar >= "A" && scalar <= "Z") ||
                                 (scalar >= "0" && scalar <= "9") ||
                                 scalarVal > 0x7F
            let top = isUpperOrDigit ? 720.0 : 520.0
            // Outer frame + glyph-dependent crossbar so different letters have distinct masks
            rect(x0, 0.0, x0 + stem, top)
            rect(x1 - stem, 0.0, x1, top)
            rect(x0, top - stem * 0.9, x1, top)
            if (scalarVal & 1) == 0 {
                rect(x0, 0.0, x1, stem * 0.9)
            }
            if (scalarVal & 2) != 0 {
                let midY = top * (0.35 + Double(scalarVal & 3) * 0.08)
                rect(x0, midY, x1, midY + stem * 0.8)
            }
        }
        return cmds
    }
}
