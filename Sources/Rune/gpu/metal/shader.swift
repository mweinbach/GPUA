// Ported from: crates/rune/src/gpu/metal/shader.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! WGSL parsing, validation, and WGSL-to-MSL 3.0 compilation into `MTLLibrary` / `MTLFunction`
//! for Rune's native Metal backend (`gpu/metal/shader.rs`).
//!
//! PORT NOTE: Upstream Rust uses `wgpu::naga` to translate WGSL to MSL. Because GPUA avoids adding
//! external Rust/C shader transpiler dependencies (`ADR-0014`), this file implements a native Swift
//! WGSL front-end and MSL 3.0 code generator supporting structs, `const`/`override` specialization,
//! `@group/@binding` uniform/storage/texture/storage-texture/sampler bindings, `var<immediate>`,
//! runtime-sized `array<T>` (`arrayLength(&arr)` via `_buffer_sizes`), `atomic<u32>`, vertex
//! descriptors (`[[stage_in]]`), multiple color targets, and compute `@workgroup_size`.

#if canImport(Metal)
import Metal
#endif
import Foundation

public struct WgslStructField: Sendable, Equatable {
    public var name: String
    public var wgslType: String
    public var builtinName: String?
    public var location: UInt32?
    public var flat: Bool
}

public struct WgslStructDecl: Sendable, Equatable {
    public var name: String
    public var fields: [WgslStructField]
}

public struct WgslParamDecl: Sendable, Equatable {
    public var name: String
    public var wgslType: String
    public var builtinName: String?
    public var location: UInt32?
}

public struct WgslFunctionDecl: Sendable, Equatable {
    public var name: String
    public var stage: MetalShaderStages?
    public var workgroupSize: [UInt32]
    public var params: [WgslParamDecl]
    public var returnType: String?
    public var returnBuiltin: String?
    public var returnLocation: UInt32?
    public var body: String
}

public struct WgslConstDecl: Sendable, Equatable {
    public var name: String
    public var isOverride: Bool
    public var wgslType: String?
    public var expr: String
}

/// Parsed WGSL or passthrough `.metallib` shader module.
// PORT NOTE: Wraps immutable parsed WGSL AST and optional `MTLLibrary` created at init time.
public final class MetalShaderModule: @unchecked Sendable {
    public let label: String?
    public let wgslSource: String?
    public let hashHex: String
    public let globals: [WgslGlobalBinding]
    public let immediateName: String?
    public let immediateType: String?
    public let immediateSize: UInt32
    public let structs: [WgslStructDecl]
    public let consts: [WgslConstDecl]
    public let functions: [WgslFunctionDecl]
    public let isReady: Bool
    #if canImport(Metal)
    public let passthroughLibrary: (any MTLLibrary)?
    #endif

    public init(shared: MetalShared, label: String? = nil, wgsl: String) {
        _ = shared
        self.label = label
        self.wgslSource = wgsl
        self.hashHex = runeBlake3Hex(wgsl)
        let (parsedGlobals, immSize) = parseWgslBindings(wgsl)
        self.globals = parsedGlobals
        self.immediateSize = immSize

        let ast = Self.parseAst(wgsl)
        self.immediateName = ast.immediateName
        self.immediateType = ast.immediateType
        self.structs = ast.structs
        self.consts = ast.consts
        self.functions = ast.functions
        self.isReady = !ast.functions.isEmpty || !ast.structs.isEmpty || !parsedGlobals.isEmpty
        #if canImport(Metal)
        self.passthroughLibrary = nil
        #endif
    }

    public init(shared: MetalShared, label: String? = nil, metallibBytes: [UInt8], entryPoints: [String]) {
        self.label = label
        self.wgslSource = nil
        self.hashHex = runeBlake3Hex(metallibBytes)
        self.globals = []
        self.immediateName = nil
        self.immediateType = nil
        self.immediateSize = 0
        self.structs = []
        self.consts = []
        self.functions = []
        #if canImport(Metal)
        if metallibBytes.count > 4,
           Array(metallibBytes.prefix(4)) == Array("MTLB".utf8),
           let dev = shared.mtlDevice {
            let dispatchData = metallibBytes.withUnsafeBytes { rawBuf in
                DispatchData(bytes: rawBuf)
            }
            if let lib = try? dev.makeLibrary(data: dispatchData) {
                let allFound = entryPoints.allSatisfy { lib.makeFunction(name: $0) != nil }
                self.passthroughLibrary = allFound ? lib : nil
                self.isReady = allFound
            } else {
                self.passthroughLibrary = nil
                self.isReady = false
            }
        } else {
            self.passthroughLibrary = nil
            self.isReady = false
        }
        #else
        _ = (shared, entryPoints)
        self.isReady = false
        #endif
    }

    public func entryPointFunction(stage: MetalShaderStages, name: String?) -> WgslFunctionDecl? {
        if let name {
            return functions.first { $0.stage == stage && $0.name == name }
        }
        return functions.first { $0.stage == stage }
    }

    public func reachableBody(stage: MetalShaderStages, entryPoint: String?) -> String {
        guard let ep = entryPointFunction(stage: stage, name: entryPoint) else {
            return wgslSource ?? ""
        }
        var visited: Set<String> = [ep.name]
        var combined = ep.body
        for p in ep.params { combined += " " + p.wgslType }
        if let rt = ep.returnType { combined += " " + rt }
        var changed = true
        while changed {
            changed = false
            for fn in functions where fn.stage == nil && !visited.contains(fn.name) {
                if identifierOccurs(fn.name, in: combined) {
                    visited.insert(fn.name)
                    combined += "\n" + fn.body
                    changed = true
                }
            }
        }
        return combined
    }

    // MARK: - Lightweight WGSL AST Parser

    private static func parseAst(_ wgsl: String) -> (
        structs: [WgslStructDecl],
        consts: [WgslConstDecl],
        functions: [WgslFunctionDecl],
        immediateName: String?,
        immediateType: String?
    ) {
        let clean = stripWgslComments(wgsl)
        let stmts = splitTopLevelStatements(clean)
        var structs: [WgslStructDecl] = []
        var consts: [WgslConstDecl] = []
        var functions: [WgslFunctionDecl] = []
        var immName: String? = nil
        var immType: String? = nil

        for raw in stmts {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if s.hasPrefix("struct ") {
                if let st = parseStruct(s) { structs.append(st) }
            } else if s.hasPrefix("const ") || s.hasPrefix("override ") || s.contains("override ") && s.hasPrefix("@") {
                if let c = parseConst(s) { consts.append(c) }
            } else if s.contains("var<immediate>") {
                if let range = s.range(of: "var<immediate>") {
                    let after = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let colon = after.firstIndex(of: ":") {
                        immName = String(after[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                        immType = String(after[after.index(after: colon)...])
                            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
                    }
                }
            } else if s.hasPrefix("fn ") || (s.hasPrefix("@") && s.contains("fn ")) {
                if let fn = parseFunction(s) { functions.append(fn) }
            }
        }
        return (structs, consts, functions, immName, immType)
    }

    private static func parseStruct(_ s: String) -> WgslStructDecl? {
        guard let open = s.firstIndex(of: "{"), let close = s.lastIndex(of: "}") else { return nil }
        let name = s.dropFirst("struct ".count)[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(s[s.index(after: open)..<close])
        let parts = splitTopLevelCommaOrSemicolon(body)
        var fields: [WgslStructField] = []
        for p in parts {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, let colon = t.lastIndex(of: ":") else { continue }
            let left = String(t[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let ty = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let builtin = extractAttributeString(left, name: "builtin")
            let loc = extractAttributeUInt32(left, name: "location")
            let flat = left.contains("@interpolate(flat)")
            let fieldName = stripAllAttributes(left)
            fields.append(WgslStructField(name: fieldName, wgslType: ty, builtinName: builtin, location: loc, flat: flat))
        }
        return WgslStructDecl(name: name, fields: fields)
    }

    private static func parseConst(_ s: String) -> WgslConstDecl? {
        let noAttrs = stripAllAttributes(s)
        let isOverride: Bool
        let rest: String
        if noAttrs.hasPrefix("override ") {
            isOverride = true
            rest = String(noAttrs.dropFirst("override ".count))
        } else if noAttrs.hasPrefix("const ") {
            isOverride = false
            rest = String(noAttrs.dropFirst("const ".count))
        } else {
            return nil
        }
        guard let eq = rest.firstIndex(of: "=") else { return nil }
        let lhs = String(rest[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = String(rest[rest.index(after: eq)...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
        if let colon = lhs.firstIndex(of: ":") {
            let name = String(lhs[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let ty = String(lhs[lhs.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return WgslConstDecl(name: name, isOverride: isOverride, wgslType: ty, expr: rhs)
        } else {
            return WgslConstDecl(name: lhs, isOverride: isOverride, wgslType: nil, expr: rhs)
        }
    }

    private static func parseFunction(_ s: String) -> WgslFunctionDecl? {
        guard let bodyOpen = findFunctionBodyBrace(s), let bodyClose = s.lastIndex(of: "}") else { return nil }
        let header = String(s[..<bodyOpen])
        let body = String(s[s.index(after: bodyOpen)..<bodyClose])

        var stage: MetalShaderStages? = nil
        var wgSize: [UInt32] = [1, 1, 1]
        if header.contains("@vertex") {
            stage = .vertex
        } else if header.contains("@fragment") {
            stage = .fragment
        } else if header.contains("@compute") {
            stage = .compute
            if let wgStr = extractAttributeString(header, name: "workgroup_size") {
                let nums = wgStr.split(separator: ",").compactMap {
                    UInt32($0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "u")))
                }
                if nums.count >= 1 { wgSize[0] = nums[0] }
                if nums.count >= 2 { wgSize[1] = nums[1] }
                if nums.count >= 3 { wgSize[2] = nums[2] }
            }
        }

        guard let fnRange = header.range(of: "fn ") else { return nil }
        let afterFn = String(header[fnRange.upperBound...])
        guard let parenOpen = afterFn.firstIndex(of: "("),
              let parenClose = findMatchingParen(afterFn, from: parenOpen)
        else { return nil }

        let fnName = String(afterFn[..<parenOpen]).trimmingCharacters(in: .whitespacesAndNewlines)
        let paramText = String(afterFn[afterFn.index(after: parenOpen)..<parenClose])
        let afterParams = String(afterFn[afterFn.index(after: parenClose)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var params: [WgslParamDecl] = []
        for rawParam in splitTopLevelCommaOrSemicolon(paramText) {
            let p = rawParam.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty, let colon = p.lastIndex(of: ":") else { continue }
            let left = String(p[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let ty = String(p[p.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let builtin = extractAttributeString(left, name: "builtin")
            let loc = extractAttributeUInt32(left, name: "location")
            let pName = stripAllAttributes(left)
            params.append(WgslParamDecl(name: pName, wgslType: ty, builtinName: builtin, location: loc))
        }

        var retType: String? = nil
        var retBuiltin: String? = nil
        var retLoc: UInt32? = nil
        if let arrow = afterParams.range(of: "->") {
            let retSpec = String(afterParams[arrow.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            retBuiltin = extractAttributeString(retSpec, name: "builtin")
            retLoc = extractAttributeUInt32(retSpec, name: "location")
            retType = stripAllAttributes(retSpec)
        }

        return WgslFunctionDecl(
            name: fnName,
            stage: stage,
            workgroupSize: wgSize,
            params: params,
            returnType: retType,
            returnBuiltin: retBuiltin,
            returnLocation: retLoc,
            body: body
        )
    }
}

private func findFunctionBodyBrace(_ s: String) -> String.Index? {
    var parenDepth = 0
    var i = s.startIndex
    while i < s.endIndex {
        let ch = s[i]
        if ch == "(" { parenDepth += 1 }
        else if ch == ")" { parenDepth = max(0, parenDepth - 1) }
        else if ch == "{" && parenDepth == 0 { return i }
        i = s.index(after: i)
    }
    return nil
}

private func findMatchingParen(_ s: String, from open: String.Index) -> String.Index? {
    var depth = 0
    var i = open
    while i < s.endIndex {
        let ch = s[i]
        if ch == "(" { depth += 1 }
        else if ch == ")" {
            depth -= 1
            if depth == 0 { return i }
        }
        i = s.index(after: i)
    }
    return nil
}

private func splitTopLevelCommaOrSemicolon(_ s: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var angle = 0
    var paren = 0
    for ch in s {
        if ch == "<" { angle += 1 }
        else if ch == ">" { angle = max(0, angle - 1) }
        else if ch == "(" { paren += 1 }
        else if ch == ")" { paren = max(0, paren - 1) }
        if (ch == "," || ch == ";") && angle == 0 && paren == 0 {
            out.append(cur)
            cur = ""
        } else {
            cur.append(ch)
        }
    }
    if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        out.append(cur)
    }
    return out
}

private func extractAttributeString(_ s: String, name: String) -> String? {
    let needle = "@\(name)("
    guard let range = s.range(of: needle) else { return nil }
    let after = s[range.upperBound...]
    guard let close = after.firstIndex(of: ")") else { return nil }
    return String(after[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stripAllAttributes(_ s: String) -> String {
    var result = ""
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "@" {
            i = s.index(after: i)
            while i < s.endIndex && (s[i].isLetter || s[i].isNumber || s[i] == "_") {
                i = s.index(after: i)
            }
            if i < s.endIndex && s[i] == "(" {
                var depth = 0
                while i < s.endIndex {
                    if s[i] == "(" { depth += 1 }
                    else if s[i] == ")" {
                        depth -= 1
                        if depth == 0 {
                            i = s.index(after: i)
                            break
                        }
                    }
                    i = s.index(after: i)
                }
            }
            while i < s.endIndex && s[i].isWhitespace {
                i = s.index(after: i)
            }
            continue
        }
        result.append(s[i])
        i = s.index(after: i)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - WGSL -> MSL 3.0 Translator

public struct MetalCompiledShaderStage: Sendable {
    public let mslSource: String
    public let entryName: String
    public let workgroupSize: [UInt32]
    public let sizedBufferSlots: [UInt8]
}

public enum MetalShaderCompileError: Error, Sendable, CustomStringConvertible {
    case missingEntryPoint(String)
    case metalCompileFailed(String)

    public var description: String {
        switch self {
        case .missingEntryPoint(let ep): return "Missing WGSL entry point: \(ep)"
        case .metalCompileFailed(let msg): return "Metal shader compilation failed: \(msg)"
        }
    }
}

/// Translates a single WGSL entry point (`vertex`, `fragment`, or `compute`) to Metal Shading Language 3.0.
public func translateWgslToMsl(
    module: MetalShaderModule,
    stage: MetalShaderStages,
    entryPoint: String?,
    layout: MetalPipelineLayout,
    constants: [String: Double] = [:]
) throws -> MetalCompiledShaderStage {
    guard let ep = module.entryPointFunction(stage: stage, name: entryPoint) else {
        throw MetalShaderCompileError.missingEntryPoint(entryPoint ?? "\(stage)")
    }

    let mslEntryName = ep.name == "main" ? "main_" : ep.name
    var msl = """
    #include <metal_stdlib>
    #include <simd/simd.h>
    using namespace metal;

    template<typename T>
    inline T _wgsl_mod(T a, T b) { return a % b; }
    inline float _wgsl_mod(float a, float b) { return fmod(a, b); }
    inline float2 _wgsl_mod(float2 a, float2 b) { return fmod(a, b); }
    inline float3 _wgsl_mod(float3 a, float3 b) { return fmod(a, b); }
    inline float4 _wgsl_mod(float4 a, float4 b) { return fmod(a, b); }

    template<typename T>
    inline T _wgsl_select(T f, T t, bool c) { return c ? t : f; }
    template<typename T>
    inline vec<T, 2> _wgsl_select(vec<T, 2> f, vec<T, 2> t, bool2 c) { return select(f, t, c); }
    template<typename T>
    inline vec<T, 3> _wgsl_select(vec<T, 3> f, vec<T, 3> t, bool3 c) { return select(f, t, c); }
    template<typename T>
    inline vec<T, 4> _wgsl_select(vec<T, 4> f, vec<T, 4> t, bool4 c) { return select(f, t, c); }

    inline float2 _wgsl_vec2(float a) { return float2(a); }
    inline int2 _wgsl_vec2(int a) { return int2(a); }
    inline uint2 _wgsl_vec2(uint a) { return uint2(a); }
    inline float2 _wgsl_vec2(float a, float b) { return float2(a, b); }
    inline int2 _wgsl_vec2(int a, int b) { return int2(a, b); }
    inline uint2 _wgsl_vec2(uint a, uint b) { return uint2(a, b); }

    inline float3 _wgsl_vec3(float a) { return float3(a); }
    inline int3 _wgsl_vec3(int a) { return int3(a); }
    inline uint3 _wgsl_vec3(uint a) { return uint3(a); }
    inline float3 _wgsl_vec3(float a, float b, float c) { return float3(a, b, c); }
    inline int3 _wgsl_vec3(int a, int b, int c) { return int3(a, b, c); }
    inline uint3 _wgsl_vec3(uint a, int b, uint c) { return uint3(a, uint(b), c); }
    inline uint3 _wgsl_vec3(uint a, uint b, uint c) { return uint3(a, b, c); }

    inline float4 _wgsl_vec4(float a) { return float4(a); }
    inline int4 _wgsl_vec4(int a) { return int4(a); }
    inline uint4 _wgsl_vec4(uint a) { return uint4(a); }
    inline float4 _wgsl_vec4(float a, float b, float c, float d) { return float4(a, b, c, d); }
    inline int4 _wgsl_vec4(int a, int b, int c, int d) { return int4(a, b, c, d); }
    inline uint4 _wgsl_vec4(uint a, uint b, uint c, uint d) { return uint4(a, b, c, d); }

    """

    let structNames = Set(module.structs.map(\.name))

    // 1. Constants & Overrides
    for c in module.consts {
        let valExpr: String
        if c.isOverride, let overrideVal = constants[c.name] {
            if let ty = c.wgslType, ty == "u32" {
                valExpr = "\(UInt32(max(0.0, overrideVal)))u"
            } else if let ty = c.wgslType, ty == "i32" {
                valExpr = "\(Int(overrideVal))"
            } else if let ty = c.wgslType, ty == "bool" {
                valExpr = overrideVal != 0.0 ? "true" : "false"
            } else {
                valExpr = String(format: "%.8f", overrideVal)
            }
        } else {
            let cleanExpr = sanitizeWgslKeywords(c.expr)
            valExpr = translateWgslExpr(
                cleanExpr,
                globalsMap: [:],
                arrayLenMap: [:],
                structNames: structNames
            )
            // Ensure u32 override defaults like `0` become `0u` if needed
        }
        let mslTy = c.wgslType.map(mapWgslTypeToMsl) ?? "auto"
        let cName = sanitizeWgslIdentifier(c.name)
        msl += "constant \(mslTy) \(cName) = \(valExpr);\n"
    }
    if !module.consts.isEmpty { msl += "\n" }

    // 2. Determine which structs are inter-stage vs fragment color output vs plain data
    let fragOutStructName: String? = (stage == .fragment && ep.returnLocation == nil) ? ep.returnType : nil
    var interStageStructNames: Set<String> = []
    if stage == .vertex, let rt = ep.returnType, ep.returnBuiltin == nil {
        interStageStructNames.insert(rt)
    }
    if stage == .fragment {
        for p in ep.params where p.builtinName == nil && p.location == nil {
            interStageStructNames.insert(p.wgslType)
        }
    }

    for st in module.structs {
        msl += "struct \(st.name) {\n"
        for f in st.fields {
            let fTy = mapWgslTypeToMsl(f.wgslType)
            let fName = sanitizeWgslIdentifier(f.name)
            var attr = ""
            if st.name == fragOutStructName || interStageStructNames.contains(st.name) {
                if let b = f.builtinName {
                    if b == "position" { attr = " [[position]]" }
                    else if b == "frag_depth" { attr = " [[depth(any)]]" }
                } else if let loc = f.location {
                    if st.name == fragOutStructName {
                        attr = " [[color(\(loc))]]"
                    } else if interStageStructNames.contains(st.name) {
                        attr = f.flat ? " [[user(locn_\(loc)), flat]]" : " [[user(locn_\(loc))]]"
                    }
                }
            }
            msl += "    \(fTy) \(fName)\(attr);\n"
        }
        msl += "};\n\n"
    }

    // 3. Collect bound globals used in reachable body
    let reachable = module.reachableBody(stage: stage, entryPoint: ep.name)
    struct BoundGlobalInfo {
        let decl: WgslGlobalBinding
        let slot: MetalAssignedSlot
        let argDecl: String
        let structFieldDecl: String
        let initExpr: String
        let refExpr: String
        let arrayLenExpr: String?
    }

    var boundInfos: [BoundGlobalInfo] = []
    var sizedSlots: [UInt8] = []
    var globalsRewrite: [String: String] = [:]
    var arrayLenRewrite: [String: String] = [:]

    for g in module.globals {
        guard identifierOccurs(g.name, in: reachable),
              let slot = layout.metalSlot(group: g.group, binding: g.binding)
        else { continue }

        switch slot {
        case .buffer(let bSlot, _, _, let mutable):
            if let elemWgsl = g.runtimeSizedArrayElement {
                let elemMsl = mapWgslTypeToMsl(elemWgsl)
                let qual = mutable ? "device" : "const device"
                sizedSlots.append(bSlot)
                let argName = "_b_\(g.name)"
                let argDecl = "\(qual) \(elemMsl)* \(argName) [[buffer(\(bSlot))]]"
                let fieldDecl = "\(qual) \(elemMsl)* \(g.name); uint \(g.name)_len;"
                let initExpr = "\(argName), uint(_buffer_sizes[\(bSlot)] / sizeof(\(elemMsl)))"
                boundInfos.append(
                    BoundGlobalInfo(
                        decl: g,
                        slot: slot,
                        argDecl: argDecl,
                        structFieldDecl: fieldDecl,
                        initExpr: initExpr,
                        refExpr: "_g.\(g.name)",
                        arrayLenExpr: "_g.\(g.name)_len"
                    )
                )
                globalsRewrite[g.name] = "_g.\(g.name)"
                arrayLenRewrite[g.name] = "_g.\(g.name)_len"
            } else {
                let valMsl = mapWgslTypeToMsl(g.valueType)
                let spaceQual: String
                if case .uniformBuffer = g.ty {
                    spaceQual = "constant"
                } else {
                    spaceQual = mutable ? "device" : "const device"
                }
                let argName = "_b_\(g.name)"
                let argDecl = "\(spaceQual) \(valMsl)* \(argName) [[buffer(\(bSlot))]]"
                let fieldDecl = "\(spaceQual) \(valMsl)* \(g.name);"
                boundInfos.append(
                    BoundGlobalInfo(
                        decl: g,
                        slot: slot,
                        argDecl: argDecl,
                        structFieldDecl: fieldDecl,
                        initExpr: argName,
                        refExpr: "(*_g.\(g.name))",
                        arrayLenExpr: nil
                    )
                )
                globalsRewrite[g.name] = "(*_g.\(g.name))"
            }

        case .texture(let tSlot, let mutable):
            let texMsl: String
            let gSafe = sanitizeWgslIdentifier(g.name)
            if case .storageTexture = g.ty {
                let acc = mutable ? "access::write" : "access::read"
                texMsl = "texture2d<float, \(acc)>"
            } else if g.valueType.contains("multisampled") {
                texMsl = "texture2d_ms<float, access::read>"
            } else {
                let sampled = reachable.contains("textureSample(\(g.name)")
                    || reachable.contains("textureSampleLevel(\(g.name)")
                    || reachable.contains("textureSample( \(g.name)")
                    || reachable.contains("textureSampleLevel( \(g.name)")
                texMsl = sampled ? "texture2d<float, access::sample>" : "texture2d<float, access::read>"
            }
            let argName = "_t_\(gSafe)"
            let argDecl = "\(texMsl) \(argName) [[texture(\(tSlot))]]"
            let fieldDecl = "\(texMsl) \(gSafe);"
            boundInfos.append(
                BoundGlobalInfo(
                    decl: g,
                    slot: slot,
                    argDecl: argDecl,
                    structFieldDecl: fieldDecl,
                    initExpr: argName,
                    refExpr: "_g.\(gSafe)",
                    arrayLenExpr: nil
                )
            )
            globalsRewrite[gSafe] = "_g.\(gSafe)"

        case .sampler(let sSlot):
            let gSafe = sanitizeWgslIdentifier(g.name)
            let argName = "_s_\(gSafe)"
            let argDecl = "sampler \(argName) [[sampler(\(sSlot))]]"
            let fieldDecl = "sampler \(gSafe);"
            boundInfos.append(
                BoundGlobalInfo(
                    decl: g,
                    slot: slot,
                    argDecl: argDecl,
                    structFieldDecl: fieldDecl,
                    initExpr: argName,
                    refExpr: "_g.\(gSafe)",
                    arrayLenExpr: nil
                )
            )
            globalsRewrite[gSafe] = "_g.\(gSafe)"
        }
    }

    var hasImmediate = false
    if let immName = module.immediateName,
       let immType = module.immediateType,
       let immSlot = layout.immediateSlot,
       identifierOccurs(immName, in: reachable) {
        hasImmediate = true
        let mslTy = mapWgslTypeToMsl(immType)
        let immSafe = sanitizeWgslIdentifier(immName)
        globalsRewrite[immSafe] = "(*_g.\(immSafe))"
        let dummy = WgslGlobalBinding(
            name: immName,
            group: 0,
            binding: UInt32.max,
            ty: .uniformBuffer(hasDynamicOffset: false),
            valueType: immType,
            runtimeSizedArrayElement: nil
        )
        boundInfos.append(
            BoundGlobalInfo(
                decl: dummy,
                slot: .buffer(index: immSlot, dynamicIndex: nil, sized: false, mutable: false),
                argDecl: "constant \(mslTy)* _imm_\(immSafe) [[buffer(\(immSlot))]]",
                structFieldDecl: "constant \(mslTy)* \(immSafe);",
                initExpr: "_imm_\(immSafe)",
                refExpr: "(*_g.\(immSafe))",
                arrayLenExpr: nil
            )
        )
        _ = hasImmediate
    }

    msl += "struct _RuneGlobals {\n"
    if boundInfos.isEmpty {
        msl += "    uint _unused;\n"
    } else {
        for info in boundInfos {
            msl += "    \(info.structFieldDecl)\n"
        }
    }
    msl += "};\n\n"

    // 4. Emit reachable helper functions (with forward declarations so WGSL declaration order is unrestricted)
    let helperFns = module.functions.filter { $0.stage == nil && identifierOccurs($0.name, in: reachable) }
    let helperNameMap: [String: String] = Dictionary(
        uniqueKeysWithValues: helperFns.map { ($0.name, sanitizeWgslIdentifier($0.name)) }
    )
    for fn in helperFns {
        let retMsl = fn.returnType.map(mapWgslTypeToMsl) ?? "void"
        let fnSafe = helperNameMap[fn.name] ?? fn.name
        var paramList = ["thread const _RuneGlobals& _g"]
        for p in fn.params {
            paramList.append("\(mapWgslTypeToMsl(p.wgslType)) \(sanitizeWgslIdentifier(p.name))")
        }
        msl += "static inline \(retMsl) \(fnSafe)(\(paramList.joined(separator: ", ")));\n"
    }
    if !helperFns.isEmpty { msl += "\n" }
    for fn in helperFns {
        let retMsl = fn.returnType.map(mapWgslTypeToMsl) ?? "void"
        let fnSafe = helperNameMap[fn.name] ?? fn.name
        var paramList = ["thread const _RuneGlobals& _g"]
        for p in fn.params {
            paramList.append("\(mapWgslTypeToMsl(p.wgslType)) \(sanitizeWgslIdentifier(p.name))")
        }
        msl += "static inline \(retMsl) \(fnSafe)(\(paramList.joined(separator: ", "))) {\n"
        msl += translateWgslBody(
            fn.body,
            paramNames: Set(fn.params.map { sanitizeWgslIdentifier($0.name) }),
            globalsMap: globalsRewrite,
            arrayLenMap: arrayLenRewrite,
            helperNames: Set(helperNameMap.values),
            structNames: structNames
        )
        msl += "\n}\n\n"
    }

    // 5. Emit Vertex Input / Simple Return wrapper structs if needed
    var stageInParams: [WgslParamDecl] = []
    struct VertexStructInputBinding {
        let paramName: String
        let structDecl: WgslStructDecl
        let stageInTypeName: String?
        let stageInArgName: String?
        let builtinArgs: [(fieldName: String, argName: String, argDecl: String)]
    }
    var vertexStructInputs: [VertexStructInputBinding] = []

    if stage == .vertex {
        stageInParams = ep.params.filter { $0.location != nil }
        if !stageInParams.isEmpty {
            msl += "struct _RuneStageIn {\n"
            for p in stageInParams {
                msl += "    \(mapWgslTypeToMsl(p.wgslType)) \(sanitizeWgslIdentifier(p.name)) [[attribute(\(p.location!))]];\n"
            }
            msl += "};\n\n"
        }

        var emittedStageInTypes: Set<String> = []
        for p in ep.params where p.builtinName == nil && p.location == nil {
            if let st = module.structs.first(where: { $0.name == p.wgslType }) {
                let pSafe = sanitizeWgslIdentifier(p.name)
                let locFields = st.fields.filter { $0.location != nil }
                var siType: String? = nil
                var siArg: String? = nil
                if !locFields.isEmpty {
                    let tName = "_RuneStageIn_\(st.name)"
                    siType = tName
                    siArg = "_si_\(pSafe)"
                    if emittedStageInTypes.insert(tName).inserted {
                        msl += "struct \(tName) {\n"
                        for f in locFields {
                            msl += "    \(mapWgslTypeToMsl(f.wgslType)) \(sanitizeWgslIdentifier(f.name)) [[attribute(\(f.location!))]];\n"
                        }
                        msl += "};\n\n"
                    }
                }
                var biArgs: [(fieldName: String, argName: String, argDecl: String)] = []
                for f in st.fields {
                    if let b = f.builtinName {
                        let fSafe = sanitizeWgslIdentifier(f.name)
                        let aName = "_bi_\(pSafe)_\(fSafe)"
                        let attr = mslBuiltinAttr(b)
                        biArgs.append((
                            fieldName: fSafe,
                            argName: aName,
                            argDecl: "\(mapWgslTypeToMsl(f.wgslType)) \(aName) \(attr)"
                        ))
                    }
                }
                vertexStructInputs.append(
                    VertexStructInputBinding(
                        paramName: pSafe,
                        structDecl: st,
                        stageInTypeName: siType,
                        stageInArgName: siArg,
                        builtinArgs: biArgs
                    )
                )
            }
        }
    }

    var wrappedReturnStruct: String? = nil
    if stage == .vertex, let rt = ep.returnType, ep.returnBuiltin == "position" {
        wrappedReturnStruct = "_RuneVertOut"
        msl += "struct _RuneVertOut { \(mapWgslTypeToMsl(rt)) _val [[position]]; };\n\n"
    } else if stage == .fragment, let rt = ep.returnType, let loc = ep.returnLocation {
        wrappedReturnStruct = "_RuneFragOut"
        msl += "struct _RuneFragOut { \(mapWgslTypeToMsl(rt)) _val [[color(\(loc))]]; };\n\n"
    }

    // 6. Entry point signature
    let stageQualifier: String
    switch stage {
    case .vertex: stageQualifier = "vertex"
    case .fragment: stageQualifier = "fragment"
    default: stageQualifier = "kernel"
    }
    let epReturnMsl = wrappedReturnStruct ?? ep.returnType.map(mapWgslTypeToMsl) ?? "void"

    var epArgs: [String] = []
    if !stageInParams.isEmpty {
        epArgs.append("_RuneStageIn _stage_in [[stage_in]]")
    }
    for vsi in vertexStructInputs {
        if let siType = vsi.stageInTypeName, let siArg = vsi.stageInArgName {
            epArgs.append("\(siType) \(siArg) [[stage_in]]")
        }
        for bi in vsi.builtinArgs {
            epArgs.append(bi.argDecl)
        }
    }
    for p in ep.params {
        let pSafe = sanitizeWgslIdentifier(p.name)
        if stage == .vertex && p.location != nil {
            continue
        }
        if stage == .vertex && p.builtinName == nil && p.location == nil && vertexStructInputs.contains(where: { $0.paramName == pSafe }) {
            continue
        }
        if let b = p.builtinName {
            let mslTy = mapWgslTypeToMsl(p.wgslType)
            let attr = mslBuiltinAttr(b)
            epArgs.append("\(mslTy) \(pSafe) \(attr)")
        } else if let loc = p.location {
            epArgs.append("\(mapWgslTypeToMsl(p.wgslType)) \(pSafe) [[user(locn_\(loc))]]")
        } else {
            epArgs.append("\(mapWgslTypeToMsl(p.wgslType)) \(pSafe) [[stage_in]]")
        }
    }
    for info in boundInfos {
        epArgs.append(info.argDecl)
    }
    if !sizedSlots.isEmpty {
        epArgs.append("constant uint* _buffer_sizes [[buffer(\(layout.sizesSlot))]]")
    }

    msl += "\(stageQualifier) \(epReturnMsl) \(mslEntryName)(\(epArgs.joined(separator: ", "))) {\n"
    if boundInfos.isEmpty {
        msl += "    const _RuneGlobals _g = { 0u };\n    (void)_g;\n"
    } else {
        let inits = boundInfos.map(\.initExpr).joined(separator: ", ")
        msl += "    const _RuneGlobals _g = { \(inits) };\n"
    }
    for p in stageInParams {
        let pSafe = sanitizeWgslIdentifier(p.name)
        msl += "    const auto \(pSafe) = _stage_in.\(pSafe);\n"
    }
    for vsi in vertexStructInputs {
        var fieldInits: [String] = []
        for f in vsi.structDecl.fields {
            let fSafe = sanitizeWgslIdentifier(f.name)
            if let bi = vsi.builtinArgs.first(where: { $0.fieldName == fSafe }) {
                fieldInits.append(bi.argName)
            } else if let siArg = vsi.stageInArgName, f.location != nil {
                fieldInits.append("\(siArg).\(fSafe)")
            } else {
                fieldInits.append("{}")
            }
        }
        msl += "    const \(vsi.structDecl.name) \(vsi.paramName) = { \(fieldInits.joined(separator: ", ")) };\n"
    }

    var epBody = translateWgslBody(
        ep.body,
        paramNames: Set(ep.params.map { sanitizeWgslIdentifier($0.name) }),
        globalsMap: globalsRewrite,
        arrayLenMap: arrayLenRewrite,
        helperNames: Set(helperNameMap.values),
        structNames: structNames,
        wrapReturnInStruct: wrappedReturnStruct
    )
    if epBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        epBody = ""
    }
    msl += epBody
    msl += "\n}\n"

    return MetalCompiledShaderStage(
        mslSource: msl,
        entryName: mslEntryName,
        workgroupSize: ep.workgroupSize,
        sizedBufferSlots: sizedSlots
    )
}

private func mslBuiltinAttr(_ builtinName: String) -> String {
    switch builtinName {
    case "vertex_index": return "[[vertex_id]]"
    case "instance_index": return "[[instance_id]]"
    case "position": return "[[position]]"
    case "front_facing": return "[[front_facing]]"
    case "sample_index": return "[[sample_id]]"
    case "global_invocation_id": return "[[thread_position_in_grid]]"
    case "local_invocation_id": return "[[thread_position_in_threadgroup]]"
    case "local_invocation_index": return "[[thread_index_in_threadgroup]]"
    case "workgroup_id": return "[[threadgroup_position_in_grid]]"
    case "num_workgroups": return "[[threadgroups_per_grid]]"
    default: return ""
    }
}

private let wgslMslReservedIdentifiers: Set<String> = [
    "half", "linear", "sample", "thread", "device", "constant", "threadgroup", "kernel", "vertex", "fragment",
]

private func sanitizeWgslIdentifier(_ id: String) -> String {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    if wgslMslReservedIdentifiers.contains(trimmed) {
        return "_wgsl_id_\(trimmed)"
    }
    return trimmed
}

private func sanitizeWgslKeywords(_ s: String) -> String {
    var out = s
    for kw in wgslMslReservedIdentifiers {
        out = rewriteAnyIdentifier(out, from: kw, to: "_wgsl_id_\(kw)")
    }
    return out
}

func mapWgslTypeToMsl(_ wgslType: String) -> String {
    let t = wgslType.trimmingCharacters(in: .whitespacesAndNewlines)
    switch t {
    case "f32": return "float"
    case "f16": return "half"
    case "i32": return "int"
    case "u32": return "uint"
    case "bool": return "bool"
    case "vec2f", "vec2<f32>": return "float2"
    case "vec3f", "vec3<f32>": return "float3"
    case "vec4f", "vec4<f32>": return "float4"
    case "vec2h", "vec2<f16>": return "half2"
    case "vec3h", "vec3<f16>": return "half3"
    case "vec4h", "vec4<f16>": return "half4"
    case "vec2i", "vec2<i32>": return "int2"
    case "vec3i", "vec3<i32>": return "int3"
    case "vec4i", "vec4<i32>": return "int4"
    case "vec2u", "vec2<u32>": return "uint2"
    case "vec3u", "vec3<u32>": return "uint3"
    case "vec4u", "vec4<u32>": return "uint4"
    case "vec2<bool>": return "bool2"
    case "vec3<bool>": return "bool3"
    case "vec4<bool>": return "bool4"
    case "mat2x2f", "mat2x2<f32>": return "float2x2"
    case "mat3x3f", "mat3x3<f32>": return "float3x3"
    case "mat4x4f", "mat4x4<f32>": return "float4x4"
    case "atomic<u32>": return "atomic_uint"
    case "atomic<i32>": return "atomic_int"
    default:
        if t.hasPrefix("array<") && t.hasSuffix(">") {
            let inner = String(t.dropFirst(6).dropLast())
            let parts = splitTopLevelCommaOrSemicolon(inner)
            if parts.count == 2 {
                return "metal::array<\(mapWgslTypeToMsl(parts[0])), \(parts[1].trimmingCharacters(in: .whitespaces))>"
            }
        }
        return t
    }
}

private func translateWgslBody(
    _ body: String,
    paramNames: Set<String> = [],
    globalsMap: [String: String],
    arrayLenMap: [String: String],
    helperNames: Set<String> = [],
    structNames: Set<String> = [],
    wrapReturnInStruct: String? = nil
) -> String {
    var s = sanitizeWgslKeywords(body)
    for (arrName, lenExpr) in arrayLenMap {
        s = s.replacingOccurrences(of: "arrayLength(&\(arrName))", with: lenExpr)
        s = s.replacingOccurrences(of: "arrayLength(& \(arrName))", with: lenExpr)
    }
    s = rewriteScopedGlobals(s, paramNames: paramNames, globalsMap: globalsMap)
    s = rewriteParenlessConditions(s, keyword: "if")
    s = rewriteParenlessConditions(s, keyword: "while")
    s = stripTrailingCommasBeforeCloseParen(s)
    s = translateWgslExpr(
        s,
        globalsMap: [:],
        arrayLenMap: [:],
        helperNames: helperNames,
        structNames: structNames
    )

    // Convert `let name: Type = expr` -> `const Type name = expr` and `let name = expr` -> `const auto name = expr`
    s = rewriteVarAndLetDeclarations(s)

    if let wrapper = wrapReturnInStruct {
        s = rewriteReturns(s, wrapperStruct: wrapper)
    }
    return s
}

private func rewriteScopedGlobals(
    _ s: String,
    paramNames: Set<String>,
    globalsMap: [String: String]
) -> String {
    guard !globalsMap.isEmpty else { return s }
    var out = ""
    var scopes: [Set<String>] = [paramNames]
    var expectingDeclName = false
    var i = s.startIndex

    while i < s.endIndex {
        let ch = s[i]
        if ch == "{" {
            scopes.append([])
            expectingDeclName = false
            out.append(ch)
            i = s.index(after: i)
        } else if ch == "}" {
            if scopes.count > 1 { _ = scopes.removeLast() }
            expectingDeclName = false
            out.append(ch)
            i = s.index(after: i)
        } else if ch.isNumber {
            expectingDeclName = false
            var end = s.index(after: i)
            while end < s.endIndex && (s[end].isLetter || s[end].isNumber || s[end] == "." || s[end] == "_") {
                if (s[end] == "e" || s[end] == "E"),
                   s.index(after: end) < s.endIndex,
                   (s[s.index(after: end)] == "+" || s[s.index(after: end)] == "-") {
                    end = s.index(end, offsetBy: 2)
                } else {
                    end = s.index(after: end)
                }
            }
            out += s[i..<end]
            i = end
        } else if ch.isLetter || ch == "_" {
            let prevIsDot: Bool = {
                guard i > s.startIndex else { return false }
                return s[s.index(before: i)] == "."
            }()
            var end = s.index(after: i)
            while end < s.endIndex && (s[end].isLetter || s[end].isNumber || s[end] == "_") {
                end = s.index(after: end)
            }
            let ident = String(s[i..<end])
            if !prevIsDot && (ident == "let" || ident == "var") {
                expectingDeclName = true
                out += ident
            } else if expectingDeclName {
                scopes[scopes.count - 1].insert(ident)
                expectingDeclName = false
                out += ident
            } else if !prevIsDot,
                      let repl = globalsMap[ident],
                      !scopes.contains(where: { $0.contains(ident) }) {
                out += repl
            } else {
                out += ident
            }
            i = end
        } else {
            if !ch.isWhitespace && ch != "<" && ch != ">" {
                expectingDeclName = false
            }
            out.append(ch)
            i = s.index(after: i)
        }
    }
    return out
}

private func stripTrailingCommasBeforeCloseParen(_ s: String) -> String {
    var out = ""
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "," {
            var j = s.index(after: i)
            while j < s.endIndex && s[j].isWhitespace {
                j = s.index(after: j)
            }
            if j < s.endIndex && s[j] == ")" {
                i = s.index(after: i)
                continue
            }
        }
        out.append(s[i])
        i = s.index(after: i)
    }
    return out
}

private func translateWgslExpr(
    _ input: String,
    globalsMap: [String: String],
    arrayLenMap: [String: String],
    helperNames: Set<String> = [],
    structNames: Set<String> = []
) -> String {
    var s = input

    // 1. `arrayLength(&name)`
    for (arrName, lenExpr) in arrayLenMap {
        s = s.replacingOccurrences(of: "arrayLength(&\(arrName))", with: lenExpr)
        s = s.replacingOccurrences(of: "arrayLength(& \(arrName))", with: lenExpr)
    }

    // 2. Vector/scalar type constructors & casts
    let typeReplacements: [(String, String)] = [
        ("vec2<f32>", "float2"), ("vec3<f32>", "float3"), ("vec4<f32>", "float4"),
        ("vec2<i32>", "int2"), ("vec3<i32>", "int3"), ("vec4<i32>", "int4"),
        ("vec2<u32>", "uint2"), ("vec3<u32>", "uint3"), ("vec4<u32>", "uint4"),
        ("vec2<bool>", "bool2"), ("vec3<bool>", "bool3"), ("vec4<bool>", "bool4"),
        ("mat2x2<f32>", "float2x2"), ("mat3x3<f32>", "float3x3"), ("mat4x4<f32>", "float4x4"),
        ("bitcast<f32>", "as_type<float>"), ("bitcast<u32>", "as_type<uint>"), ("bitcast<i32>", "as_type<int>"),
        ("vec2f", "float2"), ("vec3f", "float3"), ("vec4f", "float4"),
        ("vec2i", "int2"), ("vec3i", "int3"), ("vec4i", "int4"),
        ("vec2u", "uint2"), ("vec3u", "uint3"), ("vec4u", "uint4"),
    ]
    for (from, to) in typeReplacements {
        s = s.replacingOccurrences(of: from, with: to)
    }

    // Untyped WGSL vector constructors (`vec2(...)`, `vec3(...)`, `vec4(...)`)
    s = rewriteCall(s, name: "vec2") { args in "_wgsl_vec2(\(args.joined(separator: ", ")))" }
    s = rewriteCall(s, name: "vec3") { args in "_wgsl_vec3(\(args.joined(separator: ", ")))" }
    s = rewriteCall(s, name: "vec4") { args in "_wgsl_vec4(\(args.joined(separator: ", ")))" }

    // 3. Builtin function calls (`textureLoad`, `textureStore`, `textureSample`, `textureSampleLevel`, `textureDimensions`, `select`, `unpack*`, `atomic*`, `dpdx`, `dpdy`, `discard`)
    s = rewriteCall(s, name: "select") { args in
        guard args.count == 3 else { return "select(\(args.joined(separator: ", ")))" }
        return "_wgsl_select(\(args[0]), \(args[1]), \(args[2]))"
    }
    s = rewriteCall(s, name: "unpack2x16float") { args in
        guard let a = args.first else { return "float2(0.0)" }
        return "float2(as_type<half2>(uint(\(a))))"
    }
    s = rewriteCall(s, name: "unpack4x8unorm") { args in
        guard let a = args.first else { return "float4(0.0)" }
        return "unpack_unorm4x8_to_float(uint(\(a)))"
    }
    s = rewriteCall(s, name: "textureLoad") { args in
        guard args.count >= 3 else { return "textureLoad(\(args.joined(separator: ", ")))" }
        return "\(args[0]).read(uint2(\(args[1])), uint(\(args[2])))"
    }
    s = rewriteCall(s, name: "textureStore") { args in
        guard args.count >= 3 else { return "textureStore(\(args.joined(separator: ", ")))" }
        return "\(args[0]).write(float4(\(args[2])), uint2(\(args[1])))"
    }
    s = rewriteCall(s, name: "textureSampleLevel") { args in
        guard args.count >= 4 else { return "textureSampleLevel(\(args.joined(separator: ", ")))" }
        return "\(args[0]).sample(\(args[1]), \(args[2]), level(\(args[3])))"
    }
    s = rewriteCall(s, name: "textureSample") { args in
        guard args.count >= 3 else { return "textureSample(\(args.joined(separator: ", ")))" }
        return "\(args[0]).sample(\(args[1]), \(args[2]))"
    }
    s = rewriteCall(s, name: "textureDimensions") { args in
        guard let tex = args.first else { return "uint2(0)" }
        if args.count >= 2 {
            return "uint2(\(tex).get_width(uint(\(args[1]))), \(tex).get_height(uint(\(args[1]))))"
        }
        return "uint2(\(tex).get_width(), \(tex).get_height())"
    }
    s = rewriteCall(s, name: "atomicAdd") { args in
        guard args.count >= 2 else { return "atomicAdd(\(args.joined(separator: ", ")))" }
        return "atomic_fetch_add_explicit(\(args[0]), \(args[1]), memory_order_relaxed)"
    }
    s = rewriteCall(s, name: "atomicSub") { args in
        guard args.count >= 2 else { return "atomicSub(\(args.joined(separator: ", ")))" }
        return "atomic_fetch_sub_explicit(\(args[0]), \(args[1]), memory_order_relaxed)"
    }
    s = rewriteCall(s, name: "atomicMax") { args in
        guard args.count >= 2 else { return "atomicMax(\(args.joined(separator: ", ")))" }
        return "atomic_fetch_max_explicit(\(args[0]), \(args[1]), memory_order_relaxed)"
    }
    s = rewriteCall(s, name: "atomicMin") { args in
        guard args.count >= 2 else { return "atomicMin(\(args.joined(separator: ", ")))" }
        return "atomic_fetch_min_explicit(\(args[0]), \(args[1]), memory_order_relaxed)"
    }
    s = rewriteCall(s, name: "atomicLoad") { args in
        guard let ptr = args.first else { return "0u" }
        return "atomic_load_explicit(\(ptr), memory_order_relaxed)"
    }
    s = rewriteCall(s, name: "atomicStore") { args in
        guard args.count >= 2 else { return "" }
        return "atomic_store_explicit(\(args[0]), \(args[1]), memory_order_relaxed)"
    }
    s = rewriteWholeIdentifier(s, from: "dpdx", to: "dfdx")
    s = rewriteWholeIdentifier(s, from: "dpdy", to: "dfdy")
    s = rewriteWholeIdentifier(s, from: "inverseSqrt", to: "rsqrt")
    s = rewriteWholeIdentifier(s, from: "discard", to: "discard_fragment()")

    // Scalar casts `f32(x)`, `i32(x)`, `u32(x)`
    s = rewriteWholeIdentifier(s, from: "f32", to: "float")
    s = rewriteWholeIdentifier(s, from: "i32", to: "int")
    s = rewriteWholeIdentifier(s, from: "u32", to: "uint")

    // Struct value constructors `StructName(a, b)` -> `StructName{ a, b }`
    for stName in structNames {
        s = rewriteCall(s, name: stName) { args in
            "\(stName){ \(args.joined(separator: ", ")) }"
        }
    }

    // Helper function calls prepend `_g`
    for h in helperNames {
        s = rewriteCall(s, name: h) { args in
            if args.isEmpty || (args.count == 1 && args[0].isEmpty) {
                return "\(h)(_g)"
            }
            return "\(h)(_g, \(args.joined(separator: ", ")))"
        }
    }

    // Rewrite global variable identifiers (avoiding `.field` member accesses)
    for (gName, repl) in globalsMap {
        s = rewriteGlobalIdentifier(s, from: gName, to: repl)
    }

    return s
}

private func rewriteParenlessConditions(_ s: String, keyword: String) -> String {
    var out = ""
    var i = s.startIndex
    while let range = s.range(of: keyword, range: i..<s.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == s.startIndex { return true }
            let prev = s[s.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_" || prev == ".")
        }()
        let afterOk: Bool = {
            if range.upperBound == s.endIndex { return false }
            let next = s[range.upperBound]
            return next.isWhitespace || next == "("
        }()
        if beforeOk && afterOk, let braceIdx = findConditionBodyBrace(s, from: range.upperBound) {
            out += s[i..<range.upperBound]
            let rawCond = String(s[range.upperBound..<braceIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let alreadyWrapped: Bool = {
                guard rawCond.first == "(",
                      let close = findMatchingParen(rawCond, from: rawCond.startIndex)
                else { return false }
                return close == rawCond.index(before: rawCond.endIndex)
            }()
            if alreadyWrapped {
                out += " \(rawCond) "
            } else {
                out += " (\(rawCond)) "
            }
            i = braceIdx
        } else {
            out += s[i..<range.upperBound]
            i = range.upperBound
        }
    }
    out += s[i..<s.endIndex]
    return out
}

private func findConditionBodyBrace(_ s: String, from start: String.Index) -> String.Index? {
    var parenDepth = 0
    var i = start
    while i < s.endIndex {
        let ch = s[i]
        if ch == "(" { parenDepth += 1 }
        else if ch == ")" { parenDepth = max(0, parenDepth - 1) }
        else if ch == "{" && parenDepth == 0 { return i }
        else if ch == ";" && parenDepth == 0 { return nil }
        i = s.index(after: i)
    }
    return nil
}

private func rewriteAnyIdentifier(_ s: String, from: String, to: String) -> String {
    var out = ""
    var i = s.startIndex
    while let range = s.range(of: from, range: i..<s.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == s.startIndex { return true }
            let prev = s[s.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_")
        }()
        let afterOk: Bool = {
            if range.upperBound == s.endIndex { return true }
            let next = s[range.upperBound]
            return !(next.isLetter || next.isNumber || next == "_")
        }()
        if beforeOk && afterOk {
            out += s[i..<range.lowerBound]
            out += to
            i = range.upperBound
        } else {
            out += s[i..<range.upperBound]
            i = range.upperBound
        }
    }
    out += s[i..<s.endIndex]
    return out
}

private func rewriteCall(_ s: String, name: String, transform: ([String]) -> String) -> String {
    var out = ""
    var i = s.startIndex
    while let range = s.range(of: name, range: i..<s.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == s.startIndex { return true }
            let prev = s[s.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_" || prev == ".")
        }()
        var afterName = range.upperBound
        while afterName < s.endIndex && s[afterName].isWhitespace {
            afterName = s.index(after: afterName)
        }
        if beforeOk && afterName < s.endIndex && s[afterName] == "(",
           let close = findMatchingParen(s, from: afterName) {
            out += s[i..<range.lowerBound]
            let inner = String(s[s.index(after: afterName)..<close])
            let rawArgs = splitCallArgs(inner).map {
                rewriteCall($0.trimmingCharacters(in: .whitespacesAndNewlines), name: name, transform: transform)
            }
            out += transform(rawArgs)
            i = s.index(after: close)
        } else {
            out += s[i..<range.upperBound]
            i = range.upperBound
        }
    }
    out += s[i..<s.endIndex]
    return out
}

private func splitCallArgs(_ s: String) -> [String] {
    if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
    var out: [String] = []
    var cur = ""
    var depth = 0
    for ch in s {
        if ch == "(" || ch == "[" || ch == "{" { depth += 1 }
        else if ch == ")" || ch == "]" || ch == "}" { depth = max(0, depth - 1) }
        if ch == "," && depth == 0 {
            out.append(cur)
            cur = ""
        } else {
            cur.append(ch)
        }
    }
    out.append(cur)
    return out
}

private func rewriteWholeIdentifier(_ s: String, from: String, to: String) -> String {
    var out = ""
    var i = s.startIndex
    while let range = s.range(of: from, range: i..<s.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == s.startIndex { return true }
            let prev = s[s.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_" || prev == ".")
        }()
        let afterOk: Bool = {
            if range.upperBound == s.endIndex { return true }
            let next = s[range.upperBound]
            return !(next.isLetter || next.isNumber || next == "_")
        }()
        if beforeOk && afterOk {
            out += s[i..<range.lowerBound]
            out += to
            i = range.upperBound
        } else {
            out += s[i..<range.upperBound]
            i = range.upperBound
        }
    }
    out += s[i..<s.endIndex]
    return out
}

private func rewriteGlobalIdentifier(_ s: String, from: String, to: String) -> String {
    rewriteWholeIdentifier(s, from: from, to: to)
}

private func rewriteVarAndLetDeclarations(_ s: String) -> String {
    // Process statement-by-statement separated by `;`, `{`, `}` while preserving control structures.
    var result = ""
    var token = ""
    for ch in s {
        if ch == ";" || ch == "{" || ch == "}" {
            result += transformDeclClause(token)
            result.append(ch)
            token = ""
        } else {
            token.append(ch)
        }
    }
    result += transformDeclClause(token)
    return result
}

private func transformDeclClause(_ clause: String) -> String {
    let leadingCount = clause.prefix(while: { $0.isWhitespace }).count
    let leading = String(clause.prefix(leadingCount))
    let trimmed = String(clause.dropFirst(leadingCount))

    // Handle `for (var i = 0u` or `for (var i: u32 = 0u`
    if trimmed.hasPrefix("for") {
        if let paren = trimmed.firstIndex(of: "(") {
            let prefix = String(trimmed[...paren])
            let inside = String(trimmed[trimmed.index(after: paren)...])
            return leading + prefix + transformDeclClause(inside)
        }
    }

    if trimmed.hasPrefix("let ") {
        let rest = String(trimmed.dropFirst(4))
        if let eq = rest.firstIndex(of: "=") {
            let lhs = String(rest[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(rest[rest.index(after: eq)...])
            if let colon = lhs.firstIndex(of: ":") {
                let vName = String(lhs[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let vTy = mapWgslTypeToMsl(String(lhs[lhs.index(after: colon)...]))
                return "\(leading)const \(vTy) \(vName) =\(rhs)"
            }
            return "\(leading)const auto \(lhs) =\(rhs)"
        }
    } else if trimmed.hasPrefix("var ") {
        let rest = String(trimmed.dropFirst(4))
        if let eq = rest.firstIndex(of: "=") {
            let lhs = String(rest[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(rest[rest.index(after: eq)...])
            if let colon = lhs.firstIndex(of: ":") {
                let vName = String(lhs[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let vTy = mapWgslTypeToMsl(String(lhs[lhs.index(after: colon)...]))
                return "\(leading)\(vTy) \(vName) =\(rhs)"
            }
            return "\(leading)auto \(lhs) =\(rhs)"
        } else if let colon = rest.firstIndex(of: ":") {
            let vName = String(rest[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let vTy = mapWgslTypeToMsl(String(rest[rest.index(after: colon)...]))
            return "\(leading)\(vTy) \(vName) = {}"
        }
    }
    return clause
}

private func rewriteReturns(_ s: String, wrapperStruct: String) -> String {
    var out = ""
    var i = s.startIndex
    while let range = s.range(of: "return ", range: i..<s.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == s.startIndex { return true }
            let prev = s[s.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_")
        }()
        if beforeOk, let semi = s[range.upperBound...].firstIndex(of: ";") {
            out += s[i..<range.lowerBound]
            let expr = s[range.upperBound..<semi]
            out += "return \(wrapperStruct){ \(expr) }"
            i = semi
        } else {
            out += s[i..<range.upperBound]
            i = range.upperBound
        }
    }
    out += s[i..<s.endIndex]
    return out
}

#if canImport(Metal)
/// Compiles a WGSL stage (or resolves an entry point from a passthrough `.metallib`) to an `MTLFunction`.
public func compileMetalStageFunction(
    device: any MTLDevice,
    module: MetalShaderModule,
    stage: MetalShaderStages,
    entryPoint: String?,
    layout: MetalPipelineLayout,
    constants: [String: Double] = [:]
) throws -> (function: any MTLFunction, compiled: MetalCompiledShaderStage) {
    if let lib = module.passthroughLibrary {
        let epName = entryPoint ?? (stage == .vertex ? "vs" : (stage == .fragment ? "fs" : "main"))
        guard let fn = lib.makeFunction(name: epName) else {
            throw MetalShaderCompileError.missingEntryPoint(epName)
        }
        return (fn, MetalCompiledShaderStage(mslSource: "", entryName: epName, workgroupSize: [1, 1, 1], sizedBufferSlots: []))
    }

    let compiled = try translateWgslToMsl(
        module: module,
        stage: stage,
        entryPoint: entryPoint,
        layout: layout,
        constants: constants
    )
    let opts = MTLCompileOptions()
    opts.languageVersion = .version3_0
    if #available(macOS 11.0, iOS 14.0, *) {
        opts.preserveInvariance = true
    }
    do {
        let lib = try device.makeLibrary(source: compiled.mslSource, options: opts)
        guard let fn = lib.makeFunction(name: compiled.entryName) else {
            throw MetalShaderCompileError.missingEntryPoint(compiled.entryName)
        }
        return (fn, compiled)
    } catch {
        throw MetalShaderCompileError.metalCompileFailed("\(error)\n--- MSL ---\n\(compiled.mslSource)")
    }
}
#endif
