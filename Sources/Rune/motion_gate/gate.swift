// Ported from: crates/rune/src/motion_gate/gate.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Running an app's cells and reporting their findings against its allowlist.

#if !os(WASI)
import Foundation
#endif

/// `(kind, element contains, cell contains, why)` — matched as substrings (`""` for any).
public typealias MotionGateAllow = (String, String, String, String)

/// Builds and records one cell.
public typealias MotionGateJob = @Sendable () -> MotionGateRecording

/// One cell's findings.
public struct MotionGateCell: Sendable, Equatable {
    public var name: String
    public var findings: [MotionGateFinding]
    public var frames: Int
    public var skipped: Bool

    public init(name: String, findings: [MotionGateFinding], frames: Int, skipped: Bool) {
        self.name = name
        self.findings = findings
        self.frames = frames
        self.skipped = skipped
    }
}

public func motionGateAllowed(_ allow: [MotionGateAllow], _ f: MotionGateFinding, _ cell: String) -> String? {
    for a in allow {
        if f.kind == a.0
            && (a.1.isEmpty || f.element.contains(a.1))
            && (a.2.isEmpty || cell.contains(a.2))
        {
            return a.3
        }
    }
    return nil
}

public func motionGateRun(_ cells: [(String, MotionGateJob)], _ filter: String) -> [MotionGateCell] {
    var result: [MotionGateCell] = []
    for (name, job) in cells where filter.isEmpty || name.contains(filter) {
        let rec = job()
        motionGateEvidence(name, rec)
        result.append(MotionGateCell(
            name: name,
            findings: motionGateCheck(rec),
            frames: rec.frames,
            skipped: rec.frames < 10
        ))
    }
    return result
}

private func motionGateEvidence(_ cell: String, _ rec: MotionGateRecording) {
    #if !os(WASI)
    let env = ProcessInfo.processInfo.environment
    let out = env["MOTION_GATE_OUT"]
    if let spec = env["MOTION_GATE_DUMP"] {
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2 && parts[0] == cell {
            let path = parts[1]
            let from = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
            let to = parts.count > 3 ? (Int(parts[3]) ?? Int.max) : Int.max
            let text = motionGateDump(rec, path, from, to)
            if let out {
                try? text.write(toFile: "\(out).dump", atomically: true, encoding: .utf8)
            } else {
                FileHandle.standardError.write(Data(text.utf8))
            }
        }
    }
    if let spec = env["MOTION_GATE_SHEET"] {
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2, parts[0] == cell, let at = Int(parts[1]) {
            let focus = parts.count > 2 ? parts[2] : ""
            let base = out ?? (NSTemporaryDirectory() + "motion-gate")
            try? motionGateSheet(rec, at, focus).save("\(base).sheet.png")
        }
    }
    #else
    _ = (cell, rec)
    #endif
}

public struct MotionGateReport: Sendable, Equatable {
    public var text: String
    public var summary: String
    public var failing: Int
    public var allowed: Int

    public init(text: String, summary: String, failing: Int, allowed: Int) {
        self.text = text
        self.summary = summary
        self.failing = failing
        self.allowed = allowed
    }
}

public func motionGateReport(
    _ cells: [MotionGateCell],
    _ allow: [MotionGateAllow],
    _ listAllowed: Bool,
    _ secs: Float
) -> MotionGateReport {
    var text = ""
    var failing = 0
    var allowedN = 0
    for c in cells {
        if c.skipped {
            failing += 1
            text += "SKIP \(c.name) (its setup didn't apply)\n"
        }
        for f in c.findings {
            if let why = motionGateAllowed(allow, f, c.name) {
                allowedN += 1
                if listAllowed {
                    text += "allowed  \(f)  in \(c.name)  (\(why))\n"
                }
            } else {
                failing += 1
                text += "\(f)  in \(c.name)\n"
            }
        }
    }
    let frames = cells.reduce(0) { $0 + $1.frames }
    let summary = "motion gate: \(cells.count) cells, \(frames) frames, \(failing) findings (\(allowedN) allowed) in \(mgFmt(secs, 1)) s\n"
    var kindsSet = Set<String>()
    for c in cells {
        for f in c.findings where motionGateAllowed(allow, f, c.name) == nil {
            kindsSet.insert(f.kind)
        }
    }
    for r in MOTION_GATE_RULES where kindsSet.contains(r.kind) {
        text += "  \(r.kind): \(r.means) (\(r.threshold))\n"
    }
    return MotionGateReport(text: summary + text, summary: summary, failing: failing, allowed: allowedN)
}

public func motionGateGate(_ cells: [(String, MotionGateJob)], _ allow: [MotionGateAllow]) {
    let started = RuneInstant.now()
    #if !os(WASI)
    let env = ProcessInfo.processInfo.environment
    let filter = env["MOTION_GATE"] ?? ""
    let listAllowed = env["MOTION_GATE_ALLOWED"] != nil
    let outPath = env["MOTION_GATE_OUT"]
    #else
    let filter = ""
    let listAllowed = false
    let outPath: String? = nil
    #endif
    let ran = motionGateRun(cells, filter)
    let elapsed = Float(started.elapsedSeconds())
    let r = motionGateReport(ran, allow, listAllowed, elapsed)
    #if !os(WASI)
    if let outPath {
        try? r.text.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
    #else
    _ = outPath
    #endif
    precondition(r.failing == 0, r.text)
    #if !os(WASI)
    FileHandle.standardError.write(Data(r.summary.utf8))
    #endif
}
