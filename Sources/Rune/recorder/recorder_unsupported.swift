// Ported from: crates/rune/src/recorder/unsupported.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Platforms without a recorder yet: starting fails with a clear message. Fake microphones
//! still work everywhere.

#if !os(macOS)

struct RecorderBackendSession {
    fileprivate init() {}
}

func recorderBackendPermission() -> MicPermission {
    .restricted
}

func recorderBackendRequestPermission(_ callback: @escaping @Sendable (MicPermission) -> Void) {
    callback(.restricted)
}

func recorderBackendPreflight() -> Result<Void, RecorderError> {
    .failure(RecorderError("recording isn't supported on this platform"))
}

func recorderBackendStart(
    _ shared: RecorderShared,
    _ attempt: UInt64,
    _ path: String,
    _ opts: RecorderOptions
) -> Result<RecorderBackendSession, RecorderError> {
    _ = (shared, attempt, path, opts)
    return .failure(RecorderError("recording isn't supported on this platform"))
}

func recorderBackendPause(_ session: RecorderBackendSession) {
    _ = session
}

func recorderBackendResume(_ session: RecorderBackendSession) {
    _ = session
}

func recorderBackendStop(_ session: RecorderBackendSession) -> Result<Double, RecorderError> {
    _ = session
    return .failure(RecorderError("recording isn't supported on this platform"))
}

func recorderBackendFinish(_ session: RecorderBackendSession) {
    _ = session
}

func recorderBackendCancel(_ session: RecorderBackendSession) {
    _ = session
}

#endif
