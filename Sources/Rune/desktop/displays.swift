// Ported from: crates/rune/src/desktop/displays.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Virtual multi-monitor layout & `--displays` parser (`crates/rune/src/desktop/displays.rs`).

struct DesktopStringError: Error, Sendable, Equatable, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

enum VirtualDisplayParseError: Error, Sendable, Equatable, CustomStringConvertible {
    case empty
    case invalidEntry(String)
    case duplicateName(String)
    case multiplePrimary

    var description: String {
        switch self {
        case .empty:
            return "displays specification cannot be empty"
        case .invalidEntry(let raw):
            return "invalid display specification '\(raw)'"
        case .duplicateName(let name):
            return "duplicate display name '\(name)'"
        case .multiplePrimary:
            return "at most one display may be marked primary"
        }
    }
}

struct VirtualDisplay: Sendable, Equatable {
    var id: DisplayId
    var numericId: UInt32
    var name: String
    /// Point-space `[x, y, width, height]` (`crates/rune/src/desktop/displays.rs`).
    var frame: [Double]
    var position: (Int32, Int32)
    var size: (UInt32, UInt32)
    var scale: Double
    var primary: Bool

    init(
        id: DisplayId,
        numericId: UInt32 = 1,
        name: String,
        frame: [Double]? = nil,
        position: (Int32, Int32),
        size: (UInt32, UInt32),
        scale: Double,
        primary: Bool
    ) {
        self.id = id
        self.numericId = numericId
        self.name = name
        self.position = position
        self.size = size
        self.scale = scale
        self.primary = primary
        if let frame, frame.count == 4 {
            self.frame = frame
        } else {
            let s = max(scale, 1e-6)
            self.frame = [
                Double(position.0) / s,
                Double(position.1) / s,
                Double(size.0) / s,
                Double(size.1) / s,
            ]
        }
    }

    init(numericId: UInt32, frame: [Double], scale: Double, primary: Bool) {
        let px = Int32((frame[0] * scale).rounded())
        let py = Int32((frame[1] * scale).rounded())
        let pw = UInt32(max((frame[2] * scale).rounded(), 1.0))
        let ph = UInt32(max((frame[3] * scale).rounded(), 1.0))
        self.id = DisplayId(monitorToken: UInt64(numericId), native: nil)
        self.numericId = numericId
        self.name = "headless"
        self.frame = frame
        self.position = (px, py)
        self.size = (pw, ph)
        self.scale = scale
        self.primary = primary
    }

    func toDisplay() -> Display {
        Display(
            id: name == "headless" ? nil : id,
            name: name,
            position: position,
            size: size,
            scale: scale,
            primary: primary
        )
    }

    static func == (lhs: VirtualDisplay, rhs: VirtualDisplay) -> Bool {
        lhs.id == rhs.id
            && lhs.numericId == rhs.numericId
            && lhs.name == rhs.name
            && lhs.frame == rhs.frame
            && lhs.position.0 == rhs.position.0
            && lhs.position.1 == rhs.position.1
            && lhs.size.0 == rhs.size.0
            && lhs.size.1 == rhs.size.1
            && lhs.scale == rhs.scale
            && lhs.primary == rhs.primary
    }
}

/// Deterministic virtual desktop spanning one or more `VirtualDisplay` monitors (`crates/rune/src/desktop/displays.rs`).
struct VirtualDesktop: Sendable, Equatable {
    var displays: [VirtualDisplay]
    var pointer: (Double, Double)?
    var bounds: (x: Int32, y: Int32, width: UInt32, height: UInt32)

    init(displays: [VirtualDisplay]? = nil, pointer: (Double, Double)? = nil) {
        let list: [VirtualDisplay]
        if let displays, !displays.isEmpty {
            list = displays
        } else {
            list = [
                VirtualDisplay(
                    id: DisplayId(monitorToken: 1, native: nil),
                    numericId: 1,
                    name: "primary",
                    frame: [0.0, 0.0, 1920.0, 1080.0],
                    position: (0, 0),
                    size: (1920, 1080),
                    scale: 1.0,
                    primary: true
                )
            ]
        }
        self.displays = list
        self.pointer = pointer
        self.bounds = Self.computeBounds(list)
    }

    /// Upstream `VirtualDesktop::single(scale)` (`1920x1080` device pixels at `scale`).
    static func single(_ scale: Double) -> VirtualDesktop {
        let frame = [0.0, 0.0, 1920.0 / scale, 1080.0 / scale]
        return VirtualDesktop(
            displays: [VirtualDisplay(numericId: 1, frame: frame, scale: scale, primary: true)],
            pointer: nil
        )
    }

    /// Upstream `VirtualDesktop::from_script(script, scale)`.
    static func fromScript(_ script: [String: Any]?, _ scale: Double) -> Result<VirtualDesktop, DesktopStringError> {
        fromScriptSized(script, scale, nil)
    }

    static func fromScriptJson(
        _ script: ToolingJson?,
        scale: Double,
        defaultSize: (Double, Double)? = nil
    ) throws -> VirtualDesktop {
        var dict: [String: Any]? = nil
        if let script, case .object = script {
            dict = script.toAny() as? [String: Any]
        }
        return try fromScriptSized(dict, scale, defaultSize).get()
    }

    /// Upstream `VirtualDesktop::from_script_sized(script, scale, size)`.
    static func fromScriptSized(
        _ script: [String: Any]?,
        _ scale: Double,
        _ size: (Double, Double)?
    ) -> Result<VirtualDesktop, DesktopStringError> {
        var desktop = VirtualDesktop.single(scale)
        if let (w, h) = size {
            desktop.displays[0] = VirtualDisplay(
                numericId: 1,
                frame: [0.0, 0.0, w, h],
                scale: scale,
                primary: true
            )
            desktop.bounds = computeBounds(desktop.displays)
        }
        guard let script else { return .success(desktop) }

        if let rawDisplays = script["displays"] {
            guard let list = rawDisplays as? [Any] else {
                return .failure(DesktopStringError("script: \"displays\" must be an array"))
            }
            var parsed: [VirtualDisplay] = []
            for (i, rawItem) in list.enumerated() {
                guard let dict = rawItem as? [String: Any],
                    let frameRaw = dict["frame"] as? [Any],
                    frameRaw.count == 4,
                    let fx = asDouble(frameRaw[0]),
                    let fy = asDouble(frameRaw[1]),
                    let fw = asDouble(frameRaw[2]),
                    let fh = asDouble(frameRaw[3]),
                    fw > 0.0 && fh > 0.0
                else {
                    return .failure(DesktopStringError("script: display \(i) needs \"frame\": [x, y, width, height]"))
                }
                let itemScale: Double
                if let rawScale = dict["scale"], !(rawScale is NSNullTypeMarker) {
                    guard let s = asDouble(rawScale), s.isFinite && s > 0.0 else {
                        return .failure(DesktopStringError("script: display \(i) \"scale\" must be a number above 0"))
                    }
                    itemScale = s
                } else {
                    itemScale = scale
                }
                let numId: UInt32
                if let rawId = dict["id"], let uid = asUInt64(rawId) {
                    numId = UInt32(truncatingIfNeeded: uid)
                } else {
                    numId = UInt32(i + 1)
                }
                let isPrim = (dict["primary"] as? Bool) ?? false
                parsed.append(
                    VirtualDisplay(
                        numericId: numId,
                        frame: [fx, fy, fw, fh],
                        scale: itemScale,
                        primary: isPrim
                    )
                )
            }
            if parsed.isEmpty {
                return .failure(DesktopStringError("script: \"displays\" is empty"))
            }
            desktop.displays = parsed
            desktop.bounds = computeBounds(parsed)
        }

        if let rawPointer = script["pointer"] {
            guard let arr = rawPointer as? [Any],
                arr.count == 2,
                let px = asDouble(arr[0]),
                let py = asDouble(arr[1])
            else {
                return .failure(DesktopStringError("script: \"pointer\" must be [x, y]"))
            }
            desktop.pointer = (px, py)
        }
        return .success(desktop)
    }

    private struct NSNullTypeMarker {}

    private static func asDouble(_ v: Any) -> Double? {
        if let d = v as? Double { return d }
        if let f = v as? Float { return Double(f) }
        if let i = v as? Int { return Double(i) }
        if let i = v as? Int64 { return Double(i) }
        if let u = v as? UInt64 { return Double(u) }
        if let b = v as? Bool { return b ? nil : nil }
        return nil
    }

    private static func asUInt64(_ v: Any) -> UInt64? {
        if let u = v as? UInt64 { return u }
        if let u = v as? UInt32 { return UInt64(u) }
        if let i = v as? Int, i >= 0 { return UInt64(i) }
        if let i = v as? Int64, i >= 0 { return UInt64(i) }
        return nil
    }

    func primaryVirtualDisplay() -> VirtualDisplay {
        displays.first(where: \.primary) ?? displays[0]
    }

    /// Upstream `VirtualDesktop::display_at`: resolves mixed-scale overlapping pixel boxes by point-frame containment.
    func virtualDisplayAt(_ at: (Int32, Int32)?) -> VirtualDisplay {
        guard let (ix, iy) = at else { return primaryVirtualDisplay() }
        let x = Double(ix)
        let y = Double(iy)
        func inside(_ rect: [Double]) -> Bool {
            x >= rect[0] && y >= rect[1] && x < rect[0] + rect[2] && y < rect[1] + rect[3]
        }
        let owners = displays.filter { d in inside(d.frame.map { $0 * d.scale }) }
        if let pointMatch = owners.first(where: { inside($0.frame) }) {
            return pointMatch
        }
        return owners.first ?? primaryVirtualDisplay()
    }

    /// Upstream `VirtualDesktop::to_points((x, y))`.
    func toPoints(_ pixelPos: (Int32, Int32)) -> (Float, Float) {
        let d = virtualDisplayAt(pixelPos)
        let x = Double(pixelPos.0)
        let y = Double(pixelPos.1)
        let gx = d.frame[0] + (x - d.frame[0] * d.scale) / d.scale
        let gy = d.frame[1] + (y - d.frame[1] * d.scale) / d.scale
        return (Float(gx), Float(gy))
    }

    /// Upstream `VirtualDesktop::open_at(position, size)`.
    func openAt(_ position: (Int32, Int32)?, _ size: (Float, Float)) -> [Float] {
        if let p = position {
            let (x, y) = toPoints(p)
            return [x, y, size.0, size.1]
        }
        let d = virtualDisplayAt(nil).frame.map { Float($0) }
        return [
            d[0] + ((d[2] - size.0) / 2.0).rounded(),
            d[1] + ((d[3] - size.1) / 2.0).rounded(),
            size.0,
            size.1,
        ]
    }

    /// Upstream `VirtualDesktop::place(request, size)`.
    func place(_ request: PlaceRequest, _ size: (Float, Float)) -> (UInt32, [Float]) {
        let nativeOpt: NativeDisplayId?
        switch request.requested {
        case .id(let id): nativeOpt = id.nativeId()
        case .native(let nid): nativeOpt = nid
        case .primary, .underPointer: nativeOpt = nil
        }
        let wantedId: Int64? = nativeOpt.map { nid in
            switch nid {
            case .macOS(let n), .x11Crtc(let n), .x11Output(let n), .wayland(let n):
                return Int64(n)
            case .windows(let n):
                return Int64(bitPattern: UInt64(truncatingIfNeeded: n))
            }
        }
        let boundsList: [[Double]] = displays.map { d in
            [d.frame[0], d.frame[1], d.frame[0] + d.frame[2], d.frame[1] + d.frame[3]]
        }
        let primaryIdx = displays.firstIndex(where: \.primary)
        let requestedIdx = wantedId.flatMap { wid in
            displays.firstIndex { Int64($0.numericId) == wid }
        }
        let pointerOpt = (request.requested == .underPointer) ? pointer : nil
        let chosenIdx = overlayChooseDisplay(
            boundsList,
            primaryIdx,
            requestedIdx,
            pointerOpt
        ) ?? 0
        let d = displays[chosenIdx]
        let local = overlayLocalRect(
            PlaceRequest.at(size),
            request.placement,
            (Float(d.frame[2]), Float(d.frame[3]))
        )
        return (
            d.numericId,
            [Float(d.frame[0]) + local[0], Float(d.frame[1]) + local[1], local[2], local[3]]
        )
    }

    /// Parses `--displays` strings such as:
    /// - `"1920x1080"`
    /// - `"2560x1440@2"`
    /// - `"main:1440x900@2+0+0,ext:1920x1080@1+1440+0"`
    /// - `"left:1920x1080-1920+0,main*:1920x1080+0+0"`
    static func parse(_ spec: String) throws(VirtualDisplayParseError) -> VirtualDesktop {
        let parts = spec.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !parts.isEmpty && !parts.allSatisfy(\.isEmpty) else {
            throw .empty
        }

        var parsed: [VirtualDisplay] = []
        var names = Set<String>()
        var explicitPrimaryIndex: Int? = nil
        var autoCursorX: Int32 = 0

        for (index, part) in parts.enumerated() {
            if part.isEmpty {
                throw .invalidEntry(part)
            }
            var body = part
            var name = "display-\(index)"
            var isStarPrimary = false

            if let colonIdx = body.firstIndex(of: ":") {
                var rawName = String(body[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                if rawName.hasSuffix("*") {
                    isStarPrimary = true
                    rawName.removeLast()
                }
                guard !rawName.isEmpty else {
                    throw .invalidEntry(part)
                }
                name = rawName
                body = String(body[body.index(after: colonIdx)...])
            } else if body.hasSuffix("*") {
                isStarPrimary = true
                body.removeLast()
            }

            if !names.insert(name).inserted {
                throw .duplicateName(name)
            }
            if isStarPrimary {
                if explicitPrimaryIndex != nil {
                    throw .multiplePrimary
                }
                explicitPrimaryIndex = index
            }

            let (w, h, scale, posOpt) = try parseGeometry(body, rawEntry: part)
            let pos = posOpt ?? (autoCursorX, 0)
            autoCursorX = pos.0 + Int32(clamping: w)

            parsed.append(
                VirtualDisplay(
                    id: DisplayId(monitorToken: UInt64(index + 1), native: nil),
                    name: name,
                    position: pos,
                    size: (w, h),
                    scale: scale,
                    primary: false
                )
            )
        }

        let pIdx = explicitPrimaryIndex ?? 0
        parsed[pIdx].primary = true
        return VirtualDesktop(displays: parsed)
    }

    private static func parseGeometry(
        _ geom: String,
        rawEntry: String
    ) throws(VirtualDisplayParseError) -> (UInt32, UInt32, Double, (Int32, Int32)?) {
        // Split `<W>x<H>[@<scale>][(+|-)<X>(+|-)Y]`
        guard let xPos = geom.firstIndex(where: { $0 == "x" || $0 == "X" }) else {
            throw .invalidEntry(rawEntry)
        }
        let wStr = String(geom[..<xPos])
        guard let w = UInt32(wStr), w > 0 else {
            throw .invalidEntry(rawEntry)
        }

        let afterW = String(geom[geom.index(after: xPos)...])
        // Find `@`, `+`, or `-` after height
        let hEnd = afterW.firstIndex(where: { $0 == "@" || $0 == "+" || $0 == "-" }) ?? afterW.endIndex
        let hStr = String(afterW[..<hEnd])
        guard let h = UInt32(hStr), h > 0 else {
            throw .invalidEntry(rawEntry)
        }

        var remainder = String(afterW[hEnd...])
        var scale: Double = 1.0
        if remainder.hasPrefix("@") {
            remainder.removeFirst()
            let scaleEnd = remainder.firstIndex(where: { $0 == "+" || $0 == "-" }) ?? remainder.endIndex
            let sStr = String(remainder[..<scaleEnd])
            guard let s = Double(sStr), s > 0.0 && s.isFinite else {
                throw .invalidEntry(rawEntry)
            }
            scale = s
            remainder = String(remainder[scaleEnd...])
        }

        if remainder.isEmpty {
            return (w, h, scale, nil)
        }

        guard remainder.first == "+" || remainder.first == "-" else {
            throw .invalidEntry(rawEntry)
        }
        let afterFirstSign = remainder.index(after: remainder.startIndex)
        guard let secondSignIdx = remainder[afterFirstSign...].firstIndex(where: { $0 == "+" || $0 == "-" }) else {
            throw .invalidEntry(rawEntry)
        }
        let xCoordStr = String(remainder[..<secondSignIdx])
        let yCoordStr = String(remainder[secondSignIdx...])
        guard let ox = Int32(xCoordStr), let oy = Int32(yCoordStr) else {
            throw .invalidEntry(rawEntry)
        }
        return (w, h, scale, (ox, oy))
    }

    private static func computeBounds(_ list: [VirtualDisplay]) -> (Int32, Int32, UInt32, UInt32) {
        guard let first = list.first else {
            return (0, 0, 1920, 1080)
        }
        var minX = Int64(first.position.0)
        var minY = Int64(first.position.1)
        var maxX = Int64(first.position.0) + Int64(first.size.0)
        var maxY = Int64(first.position.1) + Int64(first.size.1)
        for d in list.dropFirst() {
            minX = min(minX, Int64(d.position.0))
            minY = min(minY, Int64(d.position.1))
            maxX = max(maxX, Int64(d.position.0) + Int64(d.size.0))
            maxY = max(maxY, Int64(d.position.1) + Int64(d.size.1))
        }
        return (
            Int32(clamping: minX),
            Int32(clamping: minY),
            UInt32(clamping: max(maxX - minX, 1)),
            UInt32(clamping: max(maxY - minY, 1))
        )
    }

    func publicDisplays() -> [Display] {
        displays.map { $0.toDisplay() }
    }

    func primaryDisplay() -> Display {
        (displays.first(where: \.primary) ?? displays[0]).toDisplay()
    }

    func displayAt(px: Int32, py: Int32) -> Display {
        for d in displays {
            let x0 = d.position.0
            let y0 = d.position.1
            let x1 = x0 &+ Int32(clamping: d.size.0)
            let y1 = y0 &+ Int32(clamping: d.size.1)
            if px >= x0 && px < x1 && py >= y0 && py < y1 {
                return d.toDisplay()
            }
        }
        return primaryDisplay()
    }

    static func == (lhs: VirtualDesktop, rhs: VirtualDesktop) -> Bool {
        let samePtr: Bool
        switch (lhs.pointer, rhs.pointer) {
        case (nil, nil): samePtr = true
        case (let a?, let b?): samePtr = a.0 == b.0 && a.1 == b.1
        default: samePtr = false
        }
        return lhs.displays == rhs.displays
            && samePtr
            && lhs.bounds.x == rhs.bounds.x
            && lhs.bounds.y == rhs.bounds.y
            && lhs.bounds.width == rhs.bounds.width
            && lhs.bounds.height == rhs.bounds.height
    }
}
