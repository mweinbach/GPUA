// Tests ported from: crates/rune/src/video/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Video macOS Backend Unit Tests")
struct VideoMacosTests {
    #if os(macOS)
    @Test("extensions come from the last path segment")
    func extensionsComeFromTheLastPathSegment() {
        func ext(_ s: String) -> String? {
            videoMacosExtension(MediaSource(s))
        }
        #expect(ext("https://example.com/media/clip") == nil)
        #expect(ext("https://host.ogg/clip") == nil)
        #expect(ext("https://host.ogg") == nil)
        #expect(ext("https://example.com/a.b/clip?x=1.ogg#t=2.webm") == nil)
        #expect(ext("https://example.com/media/clip.OGG?v=2#t") == "ogg")
        #expect(ext("file:///tmp/a.b/clip.opus") == "opus")
        #expect(ext("sounds.d/clip") == nil)
        #expect(ext("sounds/clip.webm") == "webm")
        #expect(ext("sounds/clip.") == nil)
    }

    @Test("parking never releases a playing clip")
    func parkingNeverReleasesAPlayingClip() {
        let path = VideoTestFixtures.writeFixture(name: "rgbw.mp4", base64: VideoTestFixtures.rgbwMP4Base64)
        let clips = (0..<6).map { _ in Video.file(path) }
        var released: [VideoShared] = []
        released.append(contentsOf: videoMacosParkedWith(clips[0].shared))
        clips[0].play()
        for clip in clips.dropFirst() {
            released.append(contentsOf: videoMacosParkedWith(clip.shared))
        }
        #expect(!released.contains(where: { $0 === clips[0].shared }), "the playing clip stays")
        #expect(released.count == 1, "four of the five paused clips stay parked")
        #expect(released.first === clips[1].shared, "the oldest paused clip goes")
    }
    #else
    @Test("Non-macOS stub compiles cleanly")
    func nonMacosStub() {
        #expect(Bool(true))
    }
    #endif
}
