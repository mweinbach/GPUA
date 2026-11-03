// Ported from: crates/rune/src/video/unsupported.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Platforms without a player yet: every clip fails with a clear message, and video draws the
//! neutral placeholder.

#if !os(macOS)

private func unsupportedMessage(_ kind: VideoKind) -> String {
    switch kind {
    case .video:
        return "video playback isn't supported on this platform yet"
    case .audio:
        return "audio playback isn't supported on this platform yet"
    }
}

struct VideoBackendNative: Sendable {
    init() {}
}

func videoBackendCreated(_ shared: VideoShared) {
    shared.ctlLock.withLock {
        shared.ctl.fail(unsupportedMessage(shared.kind))
    }
}

func videoBackendEnable() {}

func videoBackendProbe(
    _ native: inout VideoBackendNative,
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ kind: VideoKind
) -> Result<VideoMeta, SurfaceError> {
    _ = (native, source, headers)
    return .failure(SurfaceError(unsupportedMessage(kind)))
}

func videoBackendDecode(
    _ native: inout VideoBackendNative,
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ at: Double
) -> Result<ByteFrame, SurfaceError> {
    _ = (native, source, headers, at)
    return .failure(SurfaceError(unsupportedMessage(.video)))
}

func videoBackendApply(_ shared: VideoShared) {
    _ = shared
}

func videoBackendDrive(_ shared: VideoShared) {
    _ = shared
}

func videoBackendPreload(_ shared: VideoShared) {
    _ = shared
}

func videoBackendLiveTime(_ shared: VideoShared) -> Double? {
    _ = shared
    return nil
}

func videoBackendPull(_ shared: VideoShared, _ surface: NativeSurface, _ target: RuneInstant) -> Bool {
    _ = (shared, surface, target)
    return false
}

#endif
