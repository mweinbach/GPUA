// Ported from: crates/rune/src/tooling/interaction/stack.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Remote thread stack sampling on Apple Silicon macOS and symbol demangling.

#if canImport(Darwin)
import Darwin
#endif

let INTERACTION_STACK_DEPTH = 32

struct InteractionRawSample: Sendable {
    var pcs: [UInt]
    var len: Int
    var waiting: Bool
    var cpuUs: UInt64

    init(
        pcs: [UInt] = [UInt](repeating: 0, count: INTERACTION_STACK_DEPTH),
        len: Int = 0,
        waiting: Bool = false,
        cpuUs: UInt64 = 0
    ) {
        self.pcs = pcs
        self.len = len
        self.waiting = waiting
        self.cpuUs = cpuUs
    }
}

struct InteractionStackFrame: Sendable, Equatable {
    var name: String
    var app: Bool
}

#if os(macOS) && arch(arm64)
@_silgen_name("_dyld_get_image_header")
private func dyldGetImageHeader(_ index: UInt32) -> UnsafeRawPointer?

private let armThreadState64Flavor: thread_state_flavor_t = 6
private let armThreadState64Words: mach_msg_type_number_t = 68 // 272 bytes / 4
private let threadBasicInfoFlavor: thread_flavor_t = thread_flavor_t(THREAD_BASIC_INFO)
private let thStateRunning: integer_t = TH_STATE_RUNNING
private let pacAddressMask: UInt = (1 << 47) - 1

/// A thread that can be sampled from another: its Mach port and stack bounds.
struct InteractionTarget: Sendable {
    let port: mach_port_t
    let low: UInt
    let high: UInt

    static func current() -> InteractionTarget? {
        let me = pthread_self()
        let highAddr = UInt(bitPattern: pthread_get_stackaddr_np(me))
        let size = pthread_get_stacksize_np(me)
        guard highAddr > size && size > 0 else { return nil }
        return InteractionTarget(port: mach_thread_self(), low: highAddr - UInt(size), high: highAddr)
    }

    func sample(_ still: () -> Bool) -> InteractionRawSample? {
        var basic = thread_basic_info_data_t()
        var basicCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let infoKr = withUnsafeMutablePointer(to: &basic) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { intPtr in
                thread_info(port, threadBasicInfoFlavor, intPtr, &basicCount)
            }
        }
        guard infoKr == KERN_SUCCESS else { return nil }
        let userUs = UInt64(max(basic.user_time.seconds, 0)) * 1_000_000 + UInt64(max(basic.user_time.microseconds, 0))
        let sysUs = UInt64(max(basic.system_time.seconds, 0)) * 1_000_000 + UInt64(max(basic.system_time.microseconds, 0))
        var raw = InteractionRawSample(
            pcs: [UInt](repeating: 0, count: INTERACTION_STACK_DEPTH),
            len: 0,
            waiting: basic.run_state != thStateRunning,
            cpuUs: userUs + sysUs
        )
        guard thread_suspend(port) == KERN_SUCCESS else { return nil }
        let walked = still() && walk(&raw)
        _ = thread_resume(port)
        return walked ? raw : nil
    }

    private func walk(_ raw: inout InteractionRawSample) -> Bool {
        var words = (
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
            UInt32(0), UInt32(0), UInt32(0), UInt32(0)
        )
        var count = armThreadState64Words
        let kr = withUnsafeMutablePointer(to: &words) { ptr in
            ptr.withMemoryRebound(to: natural_t.self, capacity: Int(armThreadState64Words)) { natPtr in
                thread_get_state(port, armThreadState64Flavor, natPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return false }

        // Layout of arm_thread_state64: x[0..28] (29*8=232B = words 0..57), fp (words 58..59), lr (words 60..61), sp (words 62..63), pc (words 64..65)
        let (fp, lr, pc) = withUnsafePointer(to: &words) { ptr -> (UInt, UInt, UInt) in
            let u64Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt64.self)
            return (UInt(u64Ptr[29]), UInt(u64Ptr[30]), UInt(u64Ptr[32]))
        }

        func push(_ addr: UInt) {
            let masked = addr & pacAddressMask
            if masked != 0 && raw.len < INTERACTION_STACK_DEPTH && (raw.len == 0 || raw.pcs[raw.len - 1] != masked) {
                raw.pcs[raw.len] = masked
                raw.len += 1
            }
        }

        func readSaved(_ framePtr: UInt) -> (UInt, UInt)? {
            guard framePtr >= low && (framePtr & 7) == 0 && framePtr &+ 16 <= high else { return nil }
            guard let p = UnsafeRawPointer(bitPattern: framePtr)?.assumingMemoryBound(to: UInt.self) else { return nil }
            return (p[0], p[1])
        }

        push(pc)
        var curFp = fp
        if let (_, ret) = readSaved(curFp), (ret & pacAddressMask) != (lr & pacAddressMask) {
            push(lr)
        }
        while let (next, ret) = readSaved(curFp) {
            if (ret & pacAddressMask) == 0 || raw.len == INTERACTION_STACK_DEPTH { break }
            push(ret)
            if next <= curFp { break }
            curFp = next
        }
        return true
    }
}

struct InteractionSymbols {
    private var known: [UInt: InteractionStackFrame] = [:]

    init() {}

    mutating func frame(_ pc: UInt, inner: Bool) -> InteractionStackFrame {
        let at = inner ? pc : (pc > 0 ? pc - 1 : 0)
        if let existing = known[at] {
            return existing
        }
        let resolved = resolveAddress(at)
        known[at] = resolved
        return resolved
    }

    private func resolveAddress(_ at: UInt) -> InteractionStackFrame {
        var info = Dl_info()
        guard let ptr = UnsafeRawPointer(bitPattern: at),
              dladdr(ptr, &info) != 0,
              let sname = info.dli_sname
        else {
            return InteractionStackFrame(name: "0x" + String(at, radix: 16), app: false)
        }
        let rawSym = String(cString: sname)
        var name = interactionDemangled(rawSym)
        let mainHeader = dyldGetImageHeader(0)
        let fbase = UnsafeRawPointer(info.dli_fbase)
        // Under `swift test` / XCTest, the test bundle is a `.xctest` Mach-O image rather than image 0 (`xctest`),
        // so treat either image 0 or a `.xctest` bundle symbol outside stdlib as app code!
        var fnameStr = ""
        if let fname = info.dli_fname {
            fnameStr = String(cString: fname)
        }
        let isMainOrTestImage = (fbase == mainHeader) || fnameStr.contains(".xctest/")
        let isApp = isMainOrTestImage && !interactionIsLibrary(name)
        if fbase != mainHeader && !fnameStr.isEmpty && !fnameStr.contains(".xctest/") {
            var image = fnameStr.split(separator: "/").last.map(String.init) ?? ""
            if image.hasSuffix(".dylib") {
                image.removeLast(".dylib".count)
            }
            if !image.isEmpty {
                name = "\(name) (\(image))"
            }
        }
        return InteractionStackFrame(name: name, app: isApp)
    }
}
#endif

/// Demangles Rust legacy (`_ZN...E`), Rust v0 (`_RNv...`), and Swift (`_$s...`) symbols, capped at 160 chars.
func interactionDemangled(_ symbol: String) -> String {
    let trimmed: String
    if symbol.hasPrefix("__ZN") || symbol.hasPrefix("__R") {
        trimmed = String(symbol.dropFirst())
    } else {
        trimmed = symbol
    }
    var name: String
    if trimmed.hasPrefix("_ZN") {
        name = demangleRustLegacy(trimmed) ?? symbol
    } else if trimmed.hasPrefix("_R") {
        name = demangleRustV0(trimmed) ?? symbol
    } else if symbol.hasPrefix("_$s") || symbol.hasPrefix("$s") {
        let raw = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        name = demangleSwiftRuntime(raw) ?? symbol
    } else {
        name = symbol
    }
    if name.utf8.count > 160 {
        var out = ""
        var bytes = 0
        for sc in name.unicodeScalars {
            if bytes + sc.utf8.count > 157 { break }
            out.unicodeScalars.append(sc)
            bytes += sc.utf8.count
        }
        out.append("...")
        name = out
    }
    return name
}

private func demangleSwiftRuntime(_ mangled: String) -> String? {
    #if canImport(Darwin)
    typealias SwiftDemangleFn = @convention(c) (
        UnsafePointer<CChar>,
        Int,
        UnsafeMutablePointer<CChar>?,
        UnsafeMutablePointer<Int>?,
        UInt32
    ) -> UnsafeMutablePointer<CChar>?
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard let sym = dlsym(rtldDefault, "swift_demangle") else { return nil }
    let fn = unsafeBitCast(sym, to: SwiftDemangleFn.self)
    return mangled.withCString { cstr in
        guard let outPtr = fn(cstr, strlen(cstr), nil, nil, 0) else { return nil }
        defer { free(outPtr) }
        return String(cString: outPtr)
    }
    #else
    return nil
    #endif
}

private func demangleRustLegacy(_ sym: String) -> String? {
    guard sym.hasPrefix("_ZN"), sym.hasSuffix("E") else { return nil }
    let chars = Array(sym.dropFirst(3).dropLast())
    var idx = 0
    var parts: [String] = []
    while idx < chars.count {
        var len = 0
        let startIdx = idx
        while idx < chars.count, let d = chars[idx].wholeNumberValue {
            len = len * 10 + d
            idx += 1
        }
        guard idx > startIdx, idx + len <= chars.count else { return nil }
        let seg = String(chars[idx..<(idx + len)])
        parts.append(seg)
        idx += len
    }
    // Strip trailing `h<16 hex>` hash component (`{:#}` alternate display in `rustc_demangle`)
    if let last = parts.last, last.count == 17, last.hasPrefix("h"),
       last.dropFirst().allSatisfy({ $0.isHexDigit })
    {
        parts.removeLast()
    }
    return parts.isEmpty ? nil : parts.joined(separator: "::")
}

private func demangleRustV0(_ sym: String) -> String? {
    // Minimal Rust v0 `_RNv...` path parser for crate + nested identifiers (`_RNvCs<disambiguator>_<len><crate><len><ident>`)
    guard sym.hasPrefix("_R") else { return nil }
    let chars = Array(sym.dropFirst(2))
    var idx = 0

    func parseNested() -> [String]? {
        guard idx < chars.count else { return nil }
        if chars[idx] == "N" {
            idx += 1
            guard idx < chars.count else { return nil }
            let _ = chars[idx] // namespace tag e.g. 'v'
            idx += 1
            guard var prefix = parseNested() else { return nil }
            guard let ident = parseDisambiguatedIdent() else { return nil }
            prefix.append(ident)
            return prefix
        } else if chars[idx] == "C" {
            idx += 1
            guard let crateIdent = parseDisambiguatedIdent() else { return nil }
            return [crateIdent]
        }
        return nil
    }

    func parseDisambiguatedIdent() -> String? {
        if idx < chars.count && chars[idx] == "s" {
            idx += 1
            while idx < chars.count && chars[idx] != "_" {
                idx += 1
            }
            guard idx < chars.count && chars[idx] == "_" else { return nil }
            idx += 1
        }
        if idx < chars.count && chars[idx] == "u" {
            idx += 1
        }
        var len = 0
        let start = idx
        while idx < chars.count, let d = chars[idx].wholeNumberValue {
            len = len * 10 + d
            idx += 1
        }
        guard idx > start else { return nil }
        if idx < chars.count && chars[idx] == "_" {
            idx += 1
        }
        guard idx + len <= chars.count else { return nil }
        let s = String(chars[idx..<(idx + len)])
        idx += len
        return s
    }

    guard let parts = parseNested(), !parts.isEmpty else { return nil }
    return parts.joined(separator: "::")
}

/// Whether `name` belongs to the standard library rather than app code.
func interactionIsLibrary(_ name: String) -> Bool {
    var trimmed = name[...]
    while trimmed.first == "<" {
        trimmed.removeFirst()
    }
    let prefixes = ["std::", "core::", "alloc::", "__rust", "rust_", "Swift."]
    return prefixes.contains { trimmed.hasPrefix($0) }
}
