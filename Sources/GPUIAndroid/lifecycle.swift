// Swift-only: Android Activity, SurfaceHolder, and thermal lifecycle state machine per ADR-0012

import Foundation
import GPUI

/// Mirrors the Android `Activity` lifecycle states reported over JNI.
public enum AndroidLifecyclePhase: Int32, Sendable, Equatable, Hashable, CaseIterable {
    case created = 0
    case started = 1
    case resumed = 2
    case paused = 3
    case stopped = 4
    case destroyed = 5

    public init(rawState: Int32) {
        self = AndroidLifecyclePhase(rawValue: rawState) ?? .created
    }
}

/// Tracks the attachment and geometry of the underlying `SurfaceView` / `ANativeWindow`.
public struct AndroidSurfaceState: Sendable, Equatable {
    public var isAttached: Bool
    public var widthPx: Int32
    public var heightPx: Int32
    public var format: Int32

    public init(
        isAttached: Bool = false,
        widthPx: Int32 = 0,
        heightPx: Int32 = 0,
        format: Int32 = 0
    ) {
        self.isAttached = isAttached
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.format = format
    }

    public var hasValidDimensions: Bool {
        isAttached && widthPx > 0 && heightPx > 0
    }
}

/// Side-effect directives emitted when the Activity or Surface lifecycle transitions.
public struct AndroidLifecycleEffects: Sendable, Equatable {
    /// Non-nil when window active focus status transitioned (`true` on resume, `false` on pause/stop/destroy).
    public var activeChanged: Bool?
    /// True when frame scheduling / vsync callbacks must pause.
    public var shouldPauseRendering: Bool
    /// True when both foreground lifecycle and valid `ANativeWindow` surface allow rendering to resume.
    public var shouldResumeRendering: Bool
    /// True when the Vulkan `WGPUSurface` must be torn down immediately (e.g. `surfaceDestroyed` or `onDestroy`).
    public var shouldReleaseGpuSurface: Bool
    /// True when the Activity reached `onDestroy` and GPUI quit callbacks should run.
    public var shouldQuitApp: Bool
    /// True when returning to the foreground after having been stopped in the background.
    public var didReopen: Bool

    public init(
        activeChanged: Bool? = nil,
        shouldPauseRendering: Bool = false,
        shouldResumeRendering: Bool = false,
        shouldReleaseGpuSurface: Bool = false,
        shouldQuitApp: Bool = false,
        didReopen: Bool = false
    ) {
        self.activeChanged = activeChanged
        self.shouldPauseRendering = shouldPauseRendering
        self.shouldResumeRendering = shouldResumeRendering
        self.shouldReleaseGpuSurface = shouldReleaseGpuSurface
        self.shouldQuitApp = shouldQuitApp
        self.didReopen = didReopen
    }
}

/// Maps Android `PowerManager.THERMAL_STATUS_*` constants to GPUI `ThermalState`.
public func mapAndroidThermalStatus(_ status: Int32) -> ThermalState {
    switch status {
    case ..<1:
        return .nominal
    case 1, 2: // THERMAL_STATUS_LIGHT, THERMAL_STATUS_MODERATE
        return .fair
    case 3: // THERMAL_STATUS_SEVERE
        return .serious
    default: // THERMAL_STATUS_CRITICAL (4), EMERGENCY (5), SHUTDOWN (6)
        return .critical
    }
}

/// Thread-safe state machine coordinating Android `Activity` lifecycle, `SurfaceHolder`
/// attachment, and system thermal throttling.
// PORT NOTE: Synchronized via NSLock so JNI lifecycle and UI callbacks safely read/update state.
public final class AndroidLifecycleController: @unchecked Sendable {
    private let lock = NSLock()
    private var _phase: AndroidLifecyclePhase
    private var _surface: AndroidSurfaceState
    private var _thermalState: ThermalState
    private var _wasStoppedInBackground: Bool = false

    public init(
        initialPhase: AndroidLifecyclePhase = .created,
        surface: AndroidSurfaceState = AndroidSurfaceState(),
        thermalState: ThermalState = .nominal
    ) {
        self._phase = initialPhase
        self._surface = surface
        self._thermalState = thermalState
    }

    public var phase: AndroidLifecyclePhase {
        lock.lock()
        defer { lock.unlock() }
        return _phase
    }

    public var surface: AndroidSurfaceState {
        lock.lock()
        defer { lock.unlock() }
        return _surface
    }

    public var thermalState: ThermalState {
        lock.lock()
        defer { lock.unlock() }
        return _thermalState
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _phase == .resumed
    }

    public var isForeground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.isForegroundPhase(_phase)
    }

    public var canRender: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.canRender(phase: _phase, surface: _surface)
    }

    private static func isForegroundPhase(_ phase: AndroidLifecyclePhase) -> Bool {
        // On Android API 29+ (split-screen / multi-window / DeX), a paused Activity remains
        // visible on screen until `onStop()`; only active focus (`isActive`) drops on `onPause()`.
        phase == .started || phase == .resumed || phase == .paused
    }

    private static func canRender(phase: AndroidLifecyclePhase, surface: AndroidSurfaceState) -> Bool {
        isForegroundPhase(phase) && surface.hasValidDimensions
    }

    /// Transitions the Activity lifecycle phase and computes resulting window/GPU side effects.
    @discardableResult
    public func transition(to newPhase: AndroidLifecyclePhase) -> AndroidLifecycleEffects {
        lock.lock()
        defer { lock.unlock() }

        let oldPhase = _phase
        let wasActive = oldPhase == .resumed
        let wasRenderable = Self.canRender(phase: oldPhase, surface: _surface)

        var didReopen = false
        if _wasStoppedInBackground && (newPhase == .started || newPhase == .resumed) {
            didReopen = true
            _wasStoppedInBackground = false
        }
        if newPhase == .stopped {
            _wasStoppedInBackground = true
        }

        _phase = newPhase
        if newPhase == .destroyed {
            _surface.isAttached = false
        }

        let nowActive = newPhase == .resumed
        let nowRenderable = Self.canRender(phase: newPhase, surface: _surface)

        let activeChanged: Bool?
        if wasActive != nowActive {
            activeChanged = nowActive
        } else {
            activeChanged = nil
        }

        return AndroidLifecycleEffects(
            activeChanged: activeChanged,
            shouldPauseRendering: wasRenderable && !nowRenderable,
            shouldResumeRendering: !wasRenderable && nowRenderable,
            shouldReleaseGpuSurface: newPhase == .destroyed,
            shouldQuitApp: newPhase == .destroyed && oldPhase != .destroyed,
            didReopen: didReopen
        )
    }

    /// Records `SurfaceHolder.Callback.surfaceCreated` and returns rendering directives.
    @discardableResult
    public func onSurfaceCreated(widthPx: Int32, heightPx: Int32, format: Int32) -> AndroidLifecycleEffects {
        lock.lock()
        defer { lock.unlock() }

        let wasRenderable = Self.canRender(phase: _phase, surface: _surface)
        _surface = AndroidSurfaceState(
            isAttached: true,
            widthPx: max(0, widthPx),
            heightPx: max(0, heightPx),
            format: format
        )
        let nowRenderable = Self.canRender(phase: _phase, surface: _surface)

        return AndroidLifecycleEffects(
            activeChanged: nil,
            shouldPauseRendering: false,
            shouldResumeRendering: !wasRenderable && nowRenderable,
            shouldReleaseGpuSurface: false,
            shouldQuitApp: false,
            didReopen: false
        )
    }

    /// Records `SurfaceHolder.Callback.surfaceChanged` and returns rendering directives.
    @discardableResult
    public func onSurfaceChanged(widthPx: Int32, heightPx: Int32, format: Int32) -> AndroidLifecycleEffects {
        lock.lock()
        defer { lock.unlock() }

        let wasRenderable = Self.canRender(phase: _phase, surface: _surface)
        _surface.isAttached = true
        _surface.widthPx = max(0, widthPx)
        _surface.heightPx = max(0, heightPx)
        _surface.format = format
        let nowRenderable = Self.canRender(phase: _phase, surface: _surface)

        return AndroidLifecycleEffects(
            activeChanged: nil,
            shouldPauseRendering: wasRenderable && !nowRenderable,
            shouldResumeRendering: !wasRenderable && nowRenderable,
            shouldReleaseGpuSurface: false,
            shouldQuitApp: false,
            didReopen: false
        )
    }

    /// Records `SurfaceHolder.Callback.surfaceDestroyed`; always instructs immediate Vulkan surface release.
    @discardableResult
    public func onSurfaceDestroyed() -> AndroidLifecycleEffects {
        lock.lock()
        defer { lock.unlock() }

        let wasAttached = _surface.isAttached
        let wasRenderable = Self.canRender(phase: _phase, surface: _surface)
        _surface.isAttached = false

        return AndroidLifecycleEffects(
            activeChanged: nil,
            shouldPauseRendering: wasRenderable,
            shouldResumeRendering: false,
            shouldReleaseGpuSurface: wasAttached,
            shouldQuitApp: false,
            didReopen: false
        )
    }

    /// Updates thermal state from Android `PowerManager` status; returns the new state if changed.
    public func updateThermalStatus(_ androidStatus: Int32) -> ThermalState? {
        let mapped = mapAndroidThermalStatus(androidStatus)
        lock.lock()
        defer { lock.unlock() }
        guard mapped != _thermalState else {
            return nil
        }
        _thermalState = mapped
        return mapped
    }
}
