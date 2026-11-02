// Ported from: crates/rune/src/runtime/cx.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! View environment (`Env`), commit generation counter, and view context (`Cx`).

#if !os(WASI)
import Foundation
#endif

public struct Env: Sendable, Equatable {
    public var systemDark: Bool
    public var scale: Float

    public init(systemDark: Bool = true, scale: Float = 1.0) {
        self.systemDark = systemDark
        self.scale = scale
    }

    public static func new(_ systemDark: Bool, _ scale: Float) -> Env {
        Env(systemDark: systemDark, scale: scale)
    }
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; `commitsWasi` is accessed on the sole execution thread.
nonisolated(unsafe) private var commitsWasi: UInt64 = 0
#endif
private let commitsThreadKey = "gpua.rune.runtime.commits"

/// How many commits have started on this thread across all windows; 0 before the first.
public func commitGeneration() -> UInt64 {
    #if os(WASI)
    return commitsWasi
    #else
    return (Thread.current.threadDictionary[commitsThreadKey] as? UInt64) ?? 0
    #endif
}

func bumpCommitGeneration() {
    let next = commitGeneration() &+ 1
    #if os(WASI)
    commitsWasi = next
    #else
    Thread.current.threadDictionary[commitsThreadKey] = next
    #endif
}

/// Passed to view functions: the environment, plus runtime settings a view may declare.
public final class Cx<S> {
    var envValue: Env
    var titlebarInsetValue: Float
    var systemAccentValue: SystemAccent
    var systemReducedMotionValue: Bool
    var reducedMotionValue: Bool
    var timeScaleValue: Float
    var caretEntry: (String, [Float])?
    var caretRead: Bool = false
    var layoutRects: [String: [Float]]
    var windowRects: [String: [Float]]
    var layoutReadKeys: Set<String> = []

    public init(
        env: Env = Env(),
        titlebarInset: Float = 0.0,
        systemAccent: SystemAccent = .DEFAULT,
        systemReducedMotion: Bool = false,
        reducedMotion: Bool = false,
        timeScale: Float = 1.0,
        caret: (String, [Float])? = nil,
        layoutRects: [String: [Float]] = [:],
        windowRects: [String: [Float]] = [:]
    ) {
        self.envValue = env
        self.titlebarInsetValue = titlebarInset
        self.systemAccentValue = systemAccent
        self.systemReducedMotionValue = systemReducedMotion
        self.reducedMotionValue = reducedMotion
        self.timeScaleValue = timeScale
        self.caretEntry = caret
        self.layoutRects = layoutRects
        self.windowRects = windowRects
    }

    func retype<T>() -> Cx<T> {
        Cx<T>(
            env: envValue,
            titlebarInset: titlebarInsetValue,
            systemAccent: systemAccentValue,
            systemReducedMotion: systemReducedMotionValue,
            reducedMotion: reducedMotionValue,
            timeScale: timeScaleValue,
            caret: caretEntry,
            layoutRects: layoutRects,
            windowRects: windowRects
        )
    }

    func absorb<T>(_ other: Cx<T>) {
        reducedMotionValue = other.reducedMotionValue
        timeScaleValue = other.timeScaleValue
        caretRead = caretRead || other.caretRead
        layoutReadKeys.formUnion(other.layoutReadKeys)
    }

    public func env() -> Env {
        envValue
    }

    public func systemDark() -> Bool {
        envValue.systemDark
    }

    public func titlebarInset() -> Float {
        titlebarInsetValue
    }

    public func accent() -> Color {
        systemAccentValue.accent(envValue.systemDark)
    }

    public func focusColor() -> Color {
        systemAccentValue.focus(envValue.systemDark)
    }

    public func safeArea() -> [Float] {
        [0, 0, 0, 0]
    }

    public func systemReducedMotion() -> Bool {
        systemReducedMotionValue
    }

    public func isReducedMotion() -> Bool {
        reducedMotionValue
    }

    public func reducedMotion(_ on: Bool) {
        reducedMotionValue = on
    }

    public func timeScale(_ scale: Float) {
        timeScaleValue = min(max(scale, 0.0), 8.0)
    }

    public func caret(_ key: String) -> [Float]? {
        caretRead = true
        let rect = caretOf(caretEntry, key)
        recordMemoCaretRead(key, rect)
        return rect
    }

    public func layout(_ key: String) -> [Float]? {
        layoutReadKeys.insert(key)
        let rect = layoutRects[key]
        recordMemoLayoutRead(key, rect)
        return rect
    }

    public func windowLayout(_ key: String) -> [Float]? {
        let winKey = "@win:\(key)"
        layoutReadKeys.insert(winKey)
        let rect = windowRects[key] ?? layoutRects[key]
        recordMemoLayoutRead(winKey, rect)
        return rect
    }
}

func caretOf(_ caret: (String, [Float])?, _ key: String) -> [Float]? {
    guard let (path, rect) = caret else { return nil }
    return path.split(separator: "/").contains(Substring(key)) ? rect : nil
}
