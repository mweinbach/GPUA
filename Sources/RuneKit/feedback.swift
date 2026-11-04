// Ported from: crates/rune-kit/src/feedback.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Spinner, Loader, Progress and ProgressCircle (`@opencode/ui` components/spinner,
//! feedback/loader, components/progress, feedback/progress-circle).
//!
//! Renderer-owned loops share Rune's deterministic clock and cool through presence on removal.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif
import Rune

/// The 4×4 pulse grid: corners hidden, outer squares dim (0.15), inner squares 0.4.
public struct Spinner: Sendable {
    private var sizeVal: Float
    private var colorVal: Color?

    public init() {
        self.sizeVal = 18.0
        self.colorVal = nil
    }

    public static func new() -> Spinner {
        Spinner()
    }

    public static let `default` = Spinner()

    public func size(_ s: Float) -> Spinner {
        var copy = self
        copy.sizeVal = s
        return copy
    }

    public func color(_ c: Color) -> Spinner {
        var copy = self
        copy.colorVal = c
        return copy
    }

    public func build(_ k: Kit) -> El {
        let ink = colorVal ?? k.c.stdText
        let u = sizeVal / 15.0
        var e = el().role("progressbar").label("Loading").size(sizeVal, sizeVal)
        for i in 0..<16 {
            let x = Float(i % 4) * 4.0
            let y = Float(i / 4) * 4.0
            let corner = i == 0 || i == 3 || i == 12 || i == 15
            let outer = i == 1 || i == 2 || i == 4 || i == 7 || i == 8 || i == 11 || i == 13 || i == 14
            if corner {
                continue
            }
            let a: Float = outer ? 0.15 : 0.4
            e = e.child(
                el()
                    .key("sq\(i)")
                    .size(3.0 * u, 3.0 * u)
                    .absolute(x * u, y * u)
                    .radius(u)
                    .fill(ink)
                    // Web chooses random 1–2 s periods and 0–1.5 s delays at module load.
                    // A fixed per-cell seed preserves that timing range in replays/goldens.
                    .looping(
                        LoopSpec.opacity(
                            1.0 + Double((i * 37) % 101) / 100.0,
                            Double((i * 53) % 101) * 0.015,
                            a,
                            outer ? 0.35 : 1.0
                        )
                    )
            )
        }
        return e
    }
}

private let LOADER_RING = Icon(
    name: "kit-loader-ring",
    view: 16.0,
    body: #"<circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="2" fill="none"/>"#
)

/// A third of the ring, from 12 o'clock clockwise, round caps.
private let LOADER_ARC = Icon(
    name: "kit-loader-arc",
    view: 16.0,
    body: #"<path d="M8 2A6 6 0 0 1 13.258 10.89" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>"#
)

/// The v2 loader: a faint ring with a third-arc (`Loader`), 16 points by default.
public struct Loader: Sendable {
    private var sizeVal: Float

    public init() {
        self.sizeVal = 16.0
    }

    public static func new() -> Loader {
        Loader()
    }

    public static let `default` = Loader()

    public func size(_ s: Float) -> Loader {
        var copy = self
        copy.sizeVal = s
        return copy
    }

    public func build(_ k: Kit) -> El {
        let ink = k.c.iconMuted
        return el()
            .role("progressbar")
            .label("Loading")
            .size(sizeVal, sizeVal)
            .child(icon(LOADER_RING, sizeVal).absolute(0.0, 0.0).color(ink).opacity(0.2))
            .child(
                icon(LOADER_ARC, sizeVal)
                    .absolute(0.0, 0.0)
                    .color(ink)
                    .looping(LoopSpec.rotation(0.9))
            )
    }
}

/// A linear progress bar with an optional label and value label (`Progress`).
public struct Progress: Sendable {
    private var labelVal: String?
    private var valueVal: Float?
    private var showValueVal: Bool

    /// `value` in 0..=1; `nil` is indeterminate.
    public init(_ value: Float? = nil) {
        self.labelVal = nil
        self.valueVal = value
        self.showValueVal = false
    }

    /// `value` in 0..=1; `nil` is indeterminate.
    public static func new(_ value: Float?) -> Progress {
        Progress(value)
    }

    public func label(_ l: String) -> Progress {
        var copy = self
        copy.labelVal = l
        return copy
    }

    public func showValue() -> Progress {
        var copy = self
        copy.showValueVal = true
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        var root = col().role("progressbar").wFull().gap(4.0)
        if labelVal != nil || showValueVal {
            var header = row().key("header").gap(8.0).centerY()
            if let l = labelVal {
                root = root.label(l)
                header = header.child(text(l).key("label").font(k.ty.textSmall).color(c.stdText))
            }
            header = header.child(spacer())
            if showValueVal, let v = valueVal {
                let pct: String
                if v.isFinite {
                    pct = "\(Int((v * 100.0).rounded(.toNearestOrAwayFromZero)))%"
                } else {
                    pct = "\(v)%"
                }
                header = header.child(
                    text(pct).key("value").font(k.ty.textSmall).color(c.textWeak)
                )
            }
            root = root.child(header)
        }
        var track = row()
            .key("track")
            .wFull()
            .h(8.0)
            .radius(999.0)
            .fill(c.surfaceBase)
            .border(1.0, c.borderWeak)
            .clipSoft(0.0)
        let fill = el().key("fill").hFull().radius(999.0).fill(c.borderActive)
        if let v = valueVal {
            let clamped = v.isNaN ? v : min(max(v, 0.0), 1.0)
            track = track.child(fill.wFrac(clamped))
        } else {
            // A quarter-width segment crosses the whole track, then wraps from the left.
            track = track.child(
                fill.wFrac(0.25).looping(LoopSpec.slide(1.4, [-1.0, 0.0], [4.0, 0.0]))
            )
        }
        return root.child(track.key("track"))
    }
}

/// A small ring that fills clockwise (`ProgressCircle`): `value` in 0..=1.
public struct ProgressCircle: Sendable {
    private var valueVal: Float
    private var sizeVal: Float

    public init(_ value: Float) {
        self.valueVal = value
        self.sizeVal = 16.0
    }

    public static func new(_ value: Float) -> ProgressCircle {
        ProgressCircle(value)
    }

    public func size(_ s: Float) -> ProgressCircle {
        var copy = self
        copy.sizeVal = s
        return copy
    }

    public func build(_ k: Kit) -> El {
        let ink = k.c.iconMuted
        return el()
            .role("progressbar")
            .size(sizeVal, sizeVal)
            .child(icon(LOADER_RING, sizeVal).absolute(0.0, 0.0).color(ink).opacity(0.2))
            .child(icon(arcIcon(valueVal), sizeVal).absolute(0.0, 0.0).color(ink))
    }
}

private func formatFixed3(_ v: Float) -> String {
    let scaled = Int((Double(v) * 1000.0).rounded(.toNearestOrAwayFromZero))
    let sign = scaled < 0 ? "-" : ""
    let absVal = abs(scaled)
    let whole = absVal / 1000
    let frac = absVal % 1000
    let fracStr: String
    if frac < 10 {
        fracStr = "00\(frac)"
    } else if frac < 100 {
        fracStr = "0\(frac)"
    } else {
        fracStr = "\(frac)"
    }
    return "\(sign)\(whole).\(fracStr)"
}

// PORT NOTE: Upstream caches leaked `&'static Icon` references behind a `Mutex`; since `Rune.Icon`
// is a `Sendable` value type in Swift, precomputing all 51 quantised 2% steps once avoids locks and leaks.
private let PROGRESS_ARC_ICONS: [Icon] = (0...50).map { step in
    let body: String
    if step == 0 {
        body = ""
    } else if step == 50 {
        body = #"<circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="2" fill="none"/>"#
    } else {
        let a = Double(step) / 50.0 * (2.0 * .pi) - (.pi / 2.0)
        let x = Float(8.0 + 6.0 * cos(a))
        let y = Float(8.0 + 6.0 * sin(a))
        let large = step > 25 ? 1 : 0
        body = #"<path d="M8 2A6 6 0 \#(large) 1 \#(formatFixed3(x)) \#(formatFixed3(y))" stroke="currentColor" stroke-width="2" fill="none"/>"#
    }
    return Icon(name: "kit-progress-arc", view: 16.0, body: body)
}

/// Arcs for progress values, quantised to 2%.
private func arcIcon(_ v: Float) -> Icon {
    guard v.isFinite else { return PROGRESS_ARC_ICONS[0] }
    let clamped = min(max(v, 0.0), 1.0)
    let step = Int((clamped * 50.0).rounded(.toNearestOrAwayFromZero))
    return PROGRESS_ARC_ICONS[min(max(step, 0), 50)]
}

/// Namespace mirroring `rune_kit::feedback` module exports.
public enum feedback {
    public typealias Spinner = RuneKit.Spinner
    public typealias Loader = RuneKit.Loader
    public typealias Progress = RuneKit.Progress
    public typealias ProgressCircle = RuneKit.ProgressCircle
}
