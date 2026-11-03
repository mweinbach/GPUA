// Ported from: crates/rune/src/runtime/input/press_clicks.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Multi-click counter (double-click, triple-click, N-click) within temporal and spatial (4 pt) thresholds.

struct ClickTracker: Sendable {
    static let maxIntervalSeconds: Double = 0.5
    static let maxDistancePx: Float = 4.0

    var lastTime: Double = -100.0
    var lastX: Float = 0.0
    var lastY: Float = 0.0
    var lastButton: PointerButton = .primary
    var count: UInt32 = 0

    mutating func record(
        x: Float,
        y: Float,
        button: PointerButton,
        now: Double,
        maxInterval: Double = ClickTracker.maxIntervalSeconds
    ) -> UInt32 {
        let dt = now - lastTime
        let dx = x - lastX
        let dy = y - lastY
        let distSq = dx * dx + dy * dy
        if button == lastButton && dt >= 0.0 && dt <= maxInterval && distSq <= Self.maxDistancePx * Self.maxDistancePx {
            count &+= 1
        } else {
            count = 1
        }
        lastTime = now
        lastX = x
        lastY = y
        lastButton = button
        return count
    }

    mutating func reset() {
        count = 0
        lastTime = -100.0
    }
}
