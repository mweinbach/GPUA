// Ported from: crates/rune/src/runtime/web/runtime.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Web/WASM canvas host bridge helpers on `Runtime` (viewport DPR sync, visibility, web clipboard & URL drain).

extension Runtime {
    public func syncWebViewport(cssWidth: Float, cssHeight: Float, devicePixelRatio: Float, dark: Bool) {
        setEnv(Env(systemDark: dark, scale: max(devicePixelRatio, 0.5)))
        resize(cssWidth, cssHeight)
    }

    public func webFrame(_ nowMs: Double) -> ([Instance], [LayerSpec]) {
        let nowSec = nowMs * 0.001
        let dt: Double
        if let prev = lastWebTimestampSec {
            dt = min(max(nowSec - prev, 0.0), 0.1)
        } else {
            dt = 1.0 / 60.0
        }
        lastWebTimestampSec = nowSec
        return frame(dt)
    }
}
