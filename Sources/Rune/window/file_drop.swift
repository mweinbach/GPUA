// Ported from: crates/rune/src/window/file_drop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window file-drop state machine (`crates/rune/src/window/file_drop.rs`).

#if !os(WASI)
import Foundation
#endif
#if os(macOS)
import AppKit
#endif

let DROP_SAMPLE: Duration = .milliseconds(16)

enum WindowFileStep: Sendable, Equatable {
    case hovered(String)
    case moved
    case left
    case dropped(String)
}

struct FileDrop {
    private var hoveredPaths: [String] = []
    private var droppedPaths: [String] = []
    #if os(macOS)
    private var macViewKey: UInt = 0
    #endif

    init() {}

    mutating func attach(_ window: NativeWindow) {
        #if os(macOS)
        if let rawView = window.rawNSViewPointer(), Thread.isMainThread {
            let addr = UInt(bitPattern: rawView)
            macViewKey = addr
            MainActor.assumeIsolated {
                guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeUnretainedValue()
                macDropInstall(view: nsView)
            }
        }
        #else
        _ = window
        #endif
    }

    var isHovering: Bool {
        !hoveredPaths.isEmpty
    }

    mutating func step<S>(_ event: WindowFileStep, _ rt: Runtime<S>) -> Bool {
        switch event {
        case .hovered(let path):
            if !hoveredPaths.contains(path) {
                hoveredPaths.append(path)
            }
            return rt.hostDragHover(hoveredPaths)
        case .moved:
            guard !hoveredPaths.isEmpty else { return false }
            return rt.hostDragHover(hoveredPaths)
        case .left:
            let had = !hoveredPaths.isEmpty
            hoveredPaths.removeAll()
            droppedPaths.removeAll()
            return had ? rt.hostDragLeave() : false
        case .dropped(let path):
            droppedPaths.append(path)
            hoveredPaths.removeAll { $0 == path }
            if hoveredPaths.isEmpty {
                let paths = droppedPaths
                droppedPaths.removeAll()
                return rt.hostFileDrop(paths)
            }
            return false
        }
    }

    mutating func flushPendingDrops<S>(_ rt: Runtime<S>) -> Bool {
        guard !droppedPaths.isEmpty else { return false }
        let paths = droppedPaths
        droppedPaths.removeAll()
        hoveredPaths.removeAll()
        return rt.hostFileDrop(paths)
    }

    mutating func sampleCursor<S>(
        window: NativeWindow,
        scale: Float,
        rt: Runtime<S>
    ) -> Duration? {
        #if os(macOS)
        if macViewKey != 0 {
            for macEv in macDropTakeSteps(macViewKey) {
                switch macEv {
                case .enter(let paths, let pt):
                    hoveredPaths = paths
                    _ = rt.hostPointerMove(pt.0, pt.1)
                    _ = rt.hostDragHover(paths)
                case .move(let pt):
                    _ = rt.hostPointerMove(pt.0, pt.1)
                    if !hoveredPaths.isEmpty {
                        _ = rt.hostDragHover(hoveredPaths)
                    }
                case .leave:
                    hoveredPaths.removeAll()
                    _ = rt.hostDragLeave()
                case .drop(let paths, let pt):
                    hoveredPaths.removeAll()
                    _ = rt.hostPointerMove(pt.0, pt.1)
                    _ = rt.hostFileDrop(paths)
                }
            }
        }
        #endif
        guard isHovering else { return nil }
        #if os(Windows)
        if let screenPt = win32PointerPosition() {
            let inner = window.innerPosition()
            let lx = Float(screenPt.0 - inner.0) / max(scale, 0.001)
            let ly = Float(screenPt.1 - inner.1) / max(scale, 0.001)
            _ = rt.hostPointerMove(lx, ly)
            _ = rt.hostDragHover(hoveredPaths)
        }
        #elseif os(Linux)
        if let screenPt = x11PointerPosition() {
            let inner = window.innerPosition()
            let lx = Float(screenPt.0 - inner.0) / max(scale, 0.001)
            let ly = Float(screenPt.1 - inner.1) / max(scale, 0.001)
            _ = rt.hostPointerMove(lx, ly)
            _ = rt.hostDragHover(hoveredPaths)
        }
        #else
        _ = window
        _ = scale
        _ = rt
        #endif
        return DROP_SAMPLE
    }
}
