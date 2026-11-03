// Ported from: crates/rune/src/gpu/metal/derive.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Automatic `MetalPipelineLayout` derivation from WGSL shader stages when a pipeline is created
//! with `layout: nil`, mirroring `crates/rune/src/gpu/metal/derive.rs`.

import Foundation

/// Parsed `@group(g) @binding(b) var...` declaration in a WGSL module.
public struct WgslGlobalBinding: Sendable, Equatable {
    public var name: String
    public var group: UInt32
    public var binding: UInt32
    public var ty: MetalBindingType
    public var valueType: String
    public var runtimeSizedArrayElement: String?
}

/// Strips `//` line comments and `/* ... */` block comments while preserving line structure.
func stripWgslComments(_ source: String) -> String {
    var out = ""
    out.reserveCapacity(source.utf8.count)
    var i = source.startIndex
    var blockDepth = 0
    while i < source.endIndex {
        let ch = source[i]
        let nextIdx = source.index(after: i)
        let next: Character? = nextIdx < source.endIndex ? source[nextIdx] : nil
        if blockDepth > 0 {
            if ch == "/" && next == "*" {
                blockDepth += 1
                i = source.index(after: nextIdx)
                continue
            }
            if ch == "*" && next == "/" {
                blockDepth -= 1
                i = source.index(after: nextIdx)
                continue
            }
            if ch == "\n" { out.append("\n") }
            i = nextIdx
            continue
        }
        if ch == "/" && next == "/" {
            while i < source.endIndex && source[i] != "\n" {
                i = source.index(after: i)
            }
            continue
        }
        if ch == "/" && next == "*" {
            blockDepth = 1
            i = source.index(after: nextIdx)
            continue
        }
        out.append(ch)
        i = nextIdx
    }
    return out
}

/// Parses all `@group(g) @binding(b) var...` declarations and `var<immediate>` size from WGSL source.
public func parseWgslBindings(_ source: String) -> (bindings: [WgslGlobalBinding], immediateSize: UInt32) {
    let clean = stripWgslComments(source)
    var bindings: [WgslGlobalBinding] = []
    var immediateSize: UInt32 = 0

    let statements = splitTopLevelStatements(clean)
    for stmt in statements {
        let trimmed = stmt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if trimmed.contains("var<immediate>") {
            // Compute immediate byte size (vec4<f32> = 16, f32/u32/i32 = 4, etc.)
            if let colon = trimmed.lastIndex(of: ":") {
                let typeStr = trimmed[trimmed.index(after: colon)...]
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))
                immediateSize = max(immediateSize, wgslTypeByteSize(typeStr))
            }
            continue
        }
        guard trimmed.contains("@group("), trimmed.contains("@binding("), let varRange = trimmed.range(of: "var") else {
            continue
        }
        guard let group = extractAttributeUInt32(trimmed, name: "group"),
              let binding = extractAttributeUInt32(trimmed, name: "binding")
        else { continue }

        let afterVar = String(trimmed[varRange.upperBound...])
        var addressSpace = ""
        var rest = afterVar.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("<") {
            if let close = rest.firstIndex(of: ">") {
                addressSpace = String(rest[rest.index(after: rest.startIndex)..<close])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let colon = rest.firstIndex(of: ":") else { continue }
        let varName = String(rest[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let typePart = String(rest[rest.index(after: colon)...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";")))

        let ty: MetalBindingType
        var runtimeElem: String? = nil
        if addressSpace.hasPrefix("uniform") {
            ty = .uniformBuffer(hasDynamicOffset: false)
        } else if addressSpace.hasPrefix("storage") {
            let parts = addressSpace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let readWrite = parts.contains("read_write")
            ty = .storageBuffer(readOnly: !readWrite, hasDynamicOffset: false)
            if typePart.hasPrefix("array<") && typePart.hasSuffix(">") {
                let inner = String(typePart.dropFirst(6).dropLast())
                if !hasTopLevelComma(inner) {
                    runtimeElem = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } else if typePart.hasPrefix("sampler") {
            ty = .sampler
        } else if typePart.hasPrefix("texture_storage_2d<") {
            let inner = String(typePart.dropFirst("texture_storage_2d<".count).dropLast())
            let args = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let fmt = args.first ?? "rgba8unorm"
            let writeOnly = (args.count > 1 ? args[1] : "write") == "write"
            ty = .storageTexture(formatName: fmt, writeOnly: writeOnly)
        } else if typePart.hasPrefix("texture_multisampled") {
            ty = .texture(multisampled: true)
        } else {
            ty = .texture(multisampled: false)
        }

        bindings.append(
            WgslGlobalBinding(
                name: varName,
                group: group,
                binding: binding,
                ty: ty,
                valueType: typePart,
                runtimeSizedArrayElement: runtimeElem
            )
        )
    }

    return (bindings, immediateSize)
}

func splitTopLevelStatements(_ clean: String) -> [String] {
    var result: [String] = []
    var current = ""
    var braceDepth = 0
    for ch in clean {
        current.append(ch)
        if ch == "{" {
            braceDepth += 1
        } else if ch == "}" {
            braceDepth = max(0, braceDepth - 1)
            if braceDepth == 0 {
                result.append(current)
                current = ""
            }
        } else if ch == ";" && braceDepth == 0 {
            result.append(current)
            current = ""
        }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(current)
    }
    return result
}

func hasTopLevelComma(_ s: String) -> Bool {
    var depth = 0
    for ch in s {
        if ch == "<" { depth += 1 }
        else if ch == ">" { depth = max(0, depth - 1) }
        else if ch == "," && depth == 0 { return true }
    }
    return false
}

func extractAttributeUInt32(_ s: String, name: String) -> UInt32? {
    let needle = "@\(name)("
    guard let range = s.range(of: needle) else { return nil }
    let after = s[range.upperBound...]
    guard let close = after.firstIndex(of: ")") else { return nil }
    let digits = after[..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "u"))
    return UInt32(digits)
}

func wgslTypeByteSize(_ typeName: String) -> UInt32 {
    let t = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
    if t == "f32" || t == "i32" || t == "u32" || t.hasPrefix("atomic<") { return 4 }
    if t.hasPrefix("vec2<") { return 8 }
    if t.hasPrefix("vec3<") { return 12 }
    if t.hasPrefix("vec4<") { return 16 }
    if t.hasPrefix("mat4x4<") { return 64 }
    if t.hasPrefix("mat2x2<") { return 16 }
    return 16
}

/// Entry-point stage input for `deriveMetalLayout`.
public struct MetalStageSource {
    public var stage: MetalShaderStages
    public var module: MetalShaderModule
    public var entryPoint: String?

    public init(stage: MetalShaderStages, module: MetalShaderModule, entryPoint: String? = nil) {
        self.stage = stage
        self.module = module
        self.entryPoint = entryPoint
    }
}

/// Derives a `MetalPipelineLayout` from one or more shader stages (`vs` + `fs` or `compute`),
/// matching `wgpu`'s automatic layout derivation (`layout: None`).
public func deriveMetalLayout(_ stages: [MetalStageSource]) -> MetalPipelineLayout {
    struct Key: Hashable {
        let group: UInt32
        let binding: UInt32
    }
    var merged: [Key: MetalBindGroupLayoutEntry] = [:]
    var maxGroup: Int = -1
    var immediateSize: UInt32 = 0

    for item in stages {
        let epBody = item.module.reachableBody(stage: item.stage, entryPoint: item.entryPoint)
        immediateSize = max(immediateSize, item.module.immediateSize)
        for g in item.module.globals {
            guard identifierOccurs(g.name, in: epBody) else { continue }
            maxGroup = max(maxGroup, Int(g.group))
            let key = Key(group: g.group, binding: g.binding)
            if var existing = merged[key] {
                existing.visibility.formUnion(item.stage)
                merged[key] = existing
            } else {
                merged[key] = MetalBindGroupLayoutEntry(
                    binding: g.binding,
                    visibility: item.stage,
                    ty: g.ty
                )
            }
        }
    }

    if maxGroup < 0 {
        return MetalPipelineLayout(bindGroupLayouts: [], immediateSize: immediateSize)
    }

    var layouts: [MetalBindGroupLayout?] = []
    for g in 0...maxGroup {
        let groupEntries = merged
            .filter { $0.key.group == UInt32(g) }
            .map(\.value)
            .sorted { $0.binding < $1.binding }
        layouts.append(MetalBindGroupLayout(entries: groupEntries))
    }
    return MetalPipelineLayout(bindGroupLayouts: layouts, immediateSize: immediateSize)
}

func identifierOccurs(_ ident: String, in text: String) -> Bool {
    guard !ident.isEmpty else { return false }
    var searchStart = text.startIndex
    while let range = text.range(of: ident, range: searchStart..<text.endIndex) {
        let beforeOk: Bool = {
            if range.lowerBound == text.startIndex { return true }
            let prev = text[text.index(before: range.lowerBound)]
            return !(prev.isLetter || prev.isNumber || prev == "_")
        }()
        let afterOk: Bool = {
            if range.upperBound == text.endIndex { return true }
            let next = text[range.upperBound]
            return !(next.isLetter || next.isNumber || next == "_")
        }()
        if beforeOk && afterOk {
            return true
        }
        searchStart = range.upperBound
    }
    return false
}
