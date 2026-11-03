// Tests ported from: crates/rune/src/tooling/record.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ToolingRecordTests")
struct ToolingRecordTests {
    @Test func videoContainersFollowTheExtension() throws {
        #expect(try ToolingVideoContainer.of("a/b.MP4").get() == .mp4)
        #expect(try ToolingVideoContainer.of("b.mov").get() == .mov)
        #expect(try ToolingVideoContainer.of("b.webm").get() == .webm)
        if case .success = ToolingVideoContainer.of("b.gif") {
            Issue.record("Expected b.gif to be rejected")
        }
        let args = try toolingFfmpegArgs("out.mp4", (1920, 1200), 60.0).get()
        let joined = args.joined(separator: " ")
        #expect(joined.contains("-f rawvideo -pix_fmt rgba -s 1920x1200 -r 60 -i -"))
        #expect(joined.contains("libx264") && joined.contains("+faststart") && joined.hasSuffix("out.mp4"))
        for (path, output) in [("-out.mp4", "./-out.mp4"), ("-dir/out.mov", "./-dir/out.mov"), ("dir/-out.webm", "dir/-out.webm")] {
            let a = try toolingFfmpegArgs(path, (2, 2), 60.0).get()
            #expect(a.last == output)
        }
    }

    @Test func unpadDropsRowPadding() {
        let data: [UInt8] = [1, 2, 3, 4, 9, 9, 9, 9, 5, 6, 7, 8, 9, 9, 9, 9]
        #expect(toolingUnpad(data, 1, 2, 8) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    #if os(macOS) || os(Linux)
    @Test func encoderErrorsCloseStdinAndReportTheExitStatus() throws {
        func start(_ command: String) throws -> ToolingWriter {
            let writer = ToolingWriter((64, 64))
            try writer.encodeShellForTest(command, "test.mp4").get()
            return writer
        }

        let early = try start("exit 17")
        let blank = [UInt8](repeating: 0, count: 64 * 64 * 4)
        var earlyError: String? = nil
        for _ in 0..<20 {
            if case .failure(let err) = early.frame(blank) {
                earlyError = err.message
                break
            }
        }
        #expect(earlyError?.contains("17") == true && earlyError?.contains("stopped reading") == true)

        let late = try start("cat >/dev/null; exit 23")
        try late.frame(blank).get()
        if case .failure(let err) = late.finish() {
            #expect(err.message.contains("23") && err.message.contains("failed writing"))
        } else {
            Issue.record("Expected late exit 23 failure")
        }

        let success = try start("cat >/dev/null")
        try success.frame(blank).get()
        #expect(try success.finish().get() == "test.mp4")
    }
    #endif

    @Test func pipelinedReadbacksMatchSerialPixelsInOrderAcrossWraps() {
        let width: UInt32 = 37
        let height: UInt32 = 23
        let ring = ToolingReadback<Int>(width: width, height: height, depth: TOOLING_READBACK_DEPTH)
        var actual: [(Int, [UInt8])] = []
        var expected: [(Int, [UInt8])] = []

        func makePixels(_ idx: Int) -> [UInt8] {
            let r = UInt8((idx * 21) % 256)
            var px: [UInt8] = []
            px.reserveCapacity(Int(width * height * 4))
            for y in 0..<Int(height) {
                for x in 0..<Int(width) {
                    px.append(r &+ UInt8(x & 15))
                    px.append(UInt8(y & 31))
                    px.append(77)
                    px.append(255)
                }
            }
            return px
        }

        for i in 0..<11 {
            actual.append(contentsOf: ring.makeRoom())
            ring.copy(makePixels(i), i)
            ring.submitted()
            if i % 4 == 0 {
                actual.append(contentsOf: ring.ready())
            }
        }
        actual.append(contentsOf: ring.finish())

        for i in 0..<11 {
            expected.append((i, makePixels(i)))
        }

        #expect(actual.count == expected.count)
        for idx in expected.indices {
            #expect(actual[idx].0 == expected[idx].0)
            #expect(actual[idx].1 == expected[idx].1)
        }
    }
}
