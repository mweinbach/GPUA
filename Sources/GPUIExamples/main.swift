// Swift-only: SwiftPM entry point for the example gallery.
// Upstream builds every file in crates/gpui_examples/examples/ as its own Cargo
// binary. SwiftPM gets a single executable that dispatches by example name, so
// each ported example wraps its contents in `enum <PascalName>Example` with a
// `static func main()` and registers itself below (see docs/PORTING_GUIDE.md).

/// Example name (upstream file stem) → entry point. Keep alphabetical.
var examples: [String: @MainActor () -> Void] = [:]
// examples["hello_world"] = HelloWorldExample.main

let requested = CommandLine.arguments.dropFirst().first

if let requested, let run = examples[requested] {
    run()
} else {
    if let requested {
        print("Unknown example '\(requested)'.\n")
    }
    print("usage: swift run gpui-examples <example>\n")
    if examples.isEmpty {
        print("No examples have been ported yet. See docs/PORTING_STATUS.md.")
    } else {
        print("Available examples:")
        for name in examples.keys.sorted() { print("  \(name)") }
    }
}
