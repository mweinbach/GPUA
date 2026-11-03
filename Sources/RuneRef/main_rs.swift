// Ported from: crates/rune-ref/src/main.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif

public struct RuneRefCliError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Entry-point logic ported from `crates/rune-ref/src/main.rs` (`RuneRef` is a library target in SwiftPM).
public func runRuneRefCli(_ args: [String], output: (String) -> Void = { print($0) }) throws {
    func flagValue(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
    }

    let scene: Scene
    if let path = flagValue("--scene") {
        #if os(WASI)
        throw RuneRefCliError("--scene file I/O is unavailable on WASI")
        #else
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        scene = try JSONDecoder().decode(Scene.self, from: data)
        #endif
    } else {
        let seed: UInt64
        if let seedStr = flagValue("--seed") {
            guard let parsed = UInt64(seedStr) else {
                throw RuneRefCliError("invalid --seed value: \(seedStr)")
            }
            seed = parsed
        } else {
            seed = 0
        }
        scene = generate.seeded(seed, 8)
    }

    try scene.validate().get()
    var frame = Frame.new(scene.width, scene.height, true)
    frame.render(scene)
    output("blake3=\(frame.hash())")

    if let savePath = flagValue("--save") {
        #if os(WASI)
        throw RuneRefCliError("--save file I/O is unavailable on WASI")
        #else
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(scene)
        try encoded.write(to: URL(fileURLWithPath: savePath))
        #endif
    }

    if let xy = flagValue("--blame") {
        let parts = xy.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = UInt32(parts[0]),
              let y = UInt32(parts[1])
        else {
            throw RuneRefCliError("--blame expects x,y")
        }
        if x >= scene.width || y >= scene.height {
            throw RuneRefCliError("pixel outside viewport")
        }
        if let p = frame.blame(scene, x, y) {
            output("node=\(p.node) source=\(p.source) kind=\(p.params[1])")
        } else {
            output("clear")
        }
    }

    if args.contains("--diff") {
        let actual = GpuRenderer.default().render(scene)
        let report = compare(scene, frame, actual, 2)
        #if !os(WASI)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let str = String(data: data, encoding: .utf8) {
            output(str)
        }
        #else
        output("max_channel=\(report.maxChannel) outlier_pixels=\(report.outlierPixels)")
        #endif
        if report.outlierPixels > 0 {
            throw RuneRefCliError("GPU differs from reference")
        }
    }
}
