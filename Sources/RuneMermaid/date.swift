// Ported from: crates/rune-mermaid/src/date.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Calendar arithmetic for gantt charts, with no time zones: times are milliseconds from
//! 1970-01-01 00:00. Dates read with a dayjs-style `dateFormat` and print with a d3-style
//! `axisFormat`.

enum date {
    static let SEC: Double = 1000.0
    static let MIN: Double = 60.0 * SEC
    static let HOUR: Double = 60.0 * MIN
    static let DAY: Double = 24.0 * HOUR

    @inline(__always)
    private static func divEuclid(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        let r = a % b
        return r < 0 ? q - 1 : q
    }

    @inline(__always)
    private static func remEuclid(_ a: Int64, _ b: Int64) -> Int64 {
        let r = a % b
        return r < 0 ? r + b : r
    }

    /// Days from 1970-01-01 to `y-m-d` (proleptic Gregorian).
    static func daysFromCivil(_ yIn: Int64, _ m: UInt32, _ d: UInt32) -> Int64 {
        let y = m <= 2 ? yIn - 1 : yIn
        let era = divEuclid(y, 400)
        let yoe = y - era * 400
        let mp = (Int64(m) + 9) % 12
        let doy = (153 * mp + 2) / 5 + Int64(d) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// `(year, month, day)` of a day number from `daysFromCivil`.
    static func civilFromDays(_ zIn: Int64) -> (Int64, UInt32, UInt32) {
        let z = zIn + 719_468
        let era = divEuclid(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = UInt32(doy - (153 * mp + 2) / 5 + 1)
        let m = UInt32(mp < 10 ? mp + 3 : mp - 9)
        let year = m <= 2 ? yoe + era * 400 + 1 : yoe + era * 400
        return (year, m, d)
    }

    private static func daysInMonth(_ y: Int64, _ m: UInt32) -> UInt32 {
        switch m {
        case 2 where (y % 4 == 0 && y % 100 != 0) || y % 400 == 0:
            return 29
        case 2:
            return 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    /// A time's calendar fields.
    struct Fields: Equatable {
        var y: Int64
        var mo: UInt32
        var d: UInt32
        var h: UInt32
        var mi: UInt32
        var s: UInt32
        var ms: UInt32
        /// 0 is Sunday.
        var wd: UInt32
    }

    static func fields(_ t: Double) -> Fields {
        let day = (t / DAY).rounded(.down)
        let (y, mo, d) = civilFromDays(Int64(day))
        let rest = UInt64(max(t - day * DAY, 0.0))
        return Fields(
            y: y,
            mo: mo,
            d: d,
            h: UInt32(rest / UInt64(HOUR)),
            mi: UInt32((rest / UInt64(MIN)) % 60),
            s: UInt32((rest / UInt64(SEC)) % 60),
            ms: UInt32(rest % 1000),
            wd: UInt32(remEuclid(Int64(day) + 4, 7))
        )
    }

    private static func at(
        _ y: Int64,
        _ mo: UInt32,
        _ d: UInt32,
        _ h: UInt32,
        _ mi: UInt32,
        _ s: UInt32,
        _ ms: UInt32
    ) -> Double? {
        let ok = (1...12).contains(mo)
            && d >= 1
            && d <= daysInMonth(y, mo)
            && h < 24
            && mi < 60
            && s < 60
            && (-9999...9999).contains(y)
        guard ok else { return nil }
        return Double(daysFromCivil(y, mo, d)) * DAY
            + Double(h) * HOUR
            + Double(mi) * MIN
            + Double(s) * SEC
            + Double(ms)
    }

    /// `t` moved by `n` calendar months, keeping its day where the month has it.
    private static func addMonths(_ t: Double, _ n: Int64) -> Double {
        let f = fields(t)
        let m0 = f.y * 12 + Int64(f.mo) - 1 + n
        let y = divEuclid(m0, 12)
        let mo = UInt32(remEuclid(m0, 12)) + 1
        let d = min(f.d, daysInMonth(y, mo))
        return at(y, mo, d, f.h, f.mi, f.s, f.ms) ?? t
    }

    private static let MONTHS: [String] = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    private static let DAYS: [String] = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    /// `s` read with a dayjs format (`YYYY-MM-DD`, `DD/MM/YYYY HH:mm`, `X`, …), or, failing that,
    /// as an ISO date and time.
    static func parse(_ s: String, _ format: String) -> Double? {
        let trimmed = String(s.trimmed())
        if let v = withFormat(trimmed, format) {
            return v
        }
        for fallback in [
            "YYYY-MM-DDTHH:mm:ss",
            "YYYY-MM-DD HH:mm:ss",
            "YYYY-MM-DDTHH:mm",
            "YYYY-MM-DD HH:mm",
            "YYYY-MM-DD",
        ] {
            if let v = withFormat(trimmed, fallback) {
                return v
            }
        }
        return nil
    }

    private static let TOKENS: [String] = [
        "YYYY", "MMMM", "MMM", "SSS", "YY", "MM", "DD", "HH", "hh", "mm", "ss",
        "Do", "M", "D", "H", "h", "m", "s", "A", "a",
    ]

    private static func withFormat(_ s: String, _ format: String) -> Double? {
        var y: Int64 = 1970
        var mo: UInt32 = 1
        var d: UInt32 = 1
        var h: UInt32 = 0
        var mi: UInt32 = 0
        var sec: UInt32 = 0
        var ms: UInt32 = 0
        var pm: Bool? = nil
        var fmtRest: Substring = format[...]
        var rest: Substring = s[...]

        func number(_ maxLen: Int) -> Int64? {
            var count = 0
            var endIdx = rest.startIndex
            while count < maxLen && endIdx < rest.endIndex {
                let ch = rest[endIdx]
                guard ch.isASCII && ch >= "0" && ch <= "9" else { break }
                count += 1
                endIdx = rest.index(after: endIdx)
            }
            guard count > 0, let v = Int64(rest[..<endIdx]) else { return nil }
            rest = rest[endIdx...]
            return v
        }

        while let firstFmt = fmtRest.first {
            if firstFmt == "[" {
                let afterOpen = fmtRest.dropFirst()
                let literal: Substring
                if let closeIdx = afterOpen.firstIndex(of: "]") {
                    literal = afterOpen[..<closeIdx]
                    fmtRest = afterOpen[afterOpen.index(after: closeIdx)...]
                } else {
                    literal = afterOpen
                    fmtRest = afterOpen[afterOpen.endIndex...]
                }
                guard let stripped = rest.stripPrefix(String(literal)) else { return nil }
                rest = stripped
                continue
            }
            if firstFmt == "X" || firstFmt == "x" {
                let neg = rest.first == "-"
                let digits = rest.drop { $0 == "-" }
                let numPart = digits.prefix { ($0.isASCII && $0 >= "0" && $0 <= "9") || $0 == "." }
                guard !numPart.isEmpty, let v0 = Double(numPart) else { return nil }
                let v = (neg ? -v0 : v0) * (firstFmt == "X" ? SEC : 1.0)
                let tail = digits.dropFirst(numPart.count)
                return (tail.trimmed().isEmpty && abs(v) < 2.5e14) ? v : nil
            }
            guard let tok = TOKENS.first(where: { fmtRest.hasPrefix($0) }) else {
                guard rest.first == firstFmt else { return nil }
                rest = rest.dropFirst()
                fmtRest = fmtRest.dropFirst()
                continue
            }
            switch tok {
            case "YYYY":
                guard let v = number(4) else { return nil }
                y = v
            case "YY":
                guard let v = number(2) else { return nil }
                y = 2000 + v
            case "MMMM", "MMM":
                let lower = rest.asciiLower()
                var matched: (Int, Int)? = nil
                for (k, name) in MONTHS.enumerated() {
                    let lname = name.asciiLower()
                    if lower.hasPrefix(lname) {
                        matched = (k, lname.count)
                        break
                    } else if lower.hasPrefix(String(lname.prefix(3))) {
                        matched = (k, 3)
                        break
                    }
                }
                guard let (mIdx, len) = matched else { return nil }
                mo = UInt32(mIdx + 1)
                rest = rest.dropFirst(len)
            case "MM", "M":
                guard let v = number(2) else { return nil }
                mo = UInt32(v)
            case "DD", "D":
                guard let v = number(2) else { return nil }
                d = UInt32(v)
            case "Do":
                guard let v = number(2) else { return nil }
                d = UInt32(v)
                let pfx = rest.prefix(2)
                guard pfx.count == 2,
                      let firstAlpha = pfx.first,
                      firstAlpha.isASCII && ((firstAlpha >= "a" && firstAlpha <= "z") || (firstAlpha >= "A" && firstAlpha <= "Z")),
                      pfx.utf8.count == 2
                else { return nil }
                rest = rest.dropFirst(2)
            case "HH", "H", "hh", "h":
                guard let v = number(2) else { return nil }
                h = UInt32(v)
            case "mm", "m":
                guard let v = number(2) else { return nil }
                mi = UInt32(v)
            case "ss", "s":
                guard let v = number(2) else { return nil }
                sec = UInt32(v)
            case "SSS":
                guard let v = number(3) else { return nil }
                ms = UInt32(v)
            default:
                let pfx = rest.prefix(2)
                guard pfx.count == 2, pfx.utf8.count == 2 else { return nil }
                switch pfx.asciiLower() {
                case "am": pm = false
                case "pm": pm = true
                default: return nil
                }
                rest = rest.dropFirst(2)
            }
            fmtRest = fmtRest.dropFirst(tok.count)
        }
        if !rest.trimmed().isEmpty {
            return nil
        }
        if let isPm = pm {
            h = (h % 12) + (isPm ? 12 : 0)
        }
        return at(y, mo, d, h, mi, sec, ms)
    }

    /// A length of time: fixed milliseconds, or calendar months.
    enum Span: Equatable {
        case ms(Double)
        case months(Double)

        func after(_ t: Double) -> Double {
            switch self {
            case .ms(let ms):
                return t + ms
            case .months(let n):
                let whole = n.rounded(.towardZero)
                return addMonths(t, Int64(whole)) + (n - whole) * 30.0 * DAY
            }
        }
    }

    /// `3d`, `1.5h`, `2w`, `30m`, `250ms`, `1M` (a month), `1y`.
    static func span(_ s: String) -> Span? {
        let trimmed = s.trimmed()
        let numPart = trimmed.prefix { ($0.isASCII && $0 >= "0" && $0 <= "9") || $0 == "." }
        guard !numPart.isEmpty, let v = Double(numPart), v.isFinite, v <= 1e6 else {
            return nil
        }
        let unit = trimmed.dropFirst(numPart.count).trimmed()
        switch unit {
        case "ms": return .ms(v)
        case "s": return .ms(v * SEC)
        case "m": return .ms(v * MIN)
        case "h": return .ms(v * HOUR)
        case "d": return .ms(v * DAY)
        case "w": return .ms(v * 7.0 * DAY)
        case "M": return .months(v)
        case "y": return .months(v * 12.0)
        default: return nil
        }
    }

    /// `t` printed with a d3 time format: `%Y %y %m %d %e %H %I %M %S %L %p %b %B %a %A %j %%`, with
    /// `-`, `_` or `0` after `%` for no, space or zero padding.
    static func format(_ t: Double, _ fmt: String) -> String {
        let f = fields(t)
        var out = ""
        var idx = fmt.startIndex
        func nextChar() -> Character? {
            guard idx < fmt.endIndex else { return nil }
            let c = fmt[idx]
            idx = fmt.index(after: idx)
            return c
        }
        while let c = nextChar() {
            if c != "%" {
                out.append(c)
                continue
            }
            var code = nextChar() ?? "%"
            let pad: Character?
            if code == "-" || code == "_" || code == "0" {
                pad = code
                code = nextChar() ?? "%"
            } else {
                pad = nil
            }
            func num(_ v: Int64, _ width: Int, _ defaultPad: Character) {
                switch pad ?? defaultPad {
                case "-":
                    out += "\(v)"
                case "_":
                    let s = "\(v)"
                    if s.count >= width {
                        out += s
                    } else {
                        out += String(repeating: " ", count: width - s.count) + s
                    }
                default:
                    if v < 0 {
                        let digits = "\(-v)"
                        if digits.count + 1 >= width {
                            out += "\(v)"
                        } else {
                            out += "-" + String(repeating: "0", count: width - 1 - digits.count) + digits
                        }
                    } else {
                        let s = "\(v)"
                        if s.count >= width {
                            out += s
                        } else {
                            out += String(repeating: "0", count: width - s.count) + s
                        }
                    }
                }
            }
            let doy = daysFromCivil(f.y, f.mo, f.d) - daysFromCivil(f.y, 1, 1) + 1
            switch code {
            case "Y": num(f.y, 4, "0")
            case "y": num(remEuclid(f.y, 100), 2, "0")
            case "m": num(Int64(f.mo), 2, "0")
            case "d": num(Int64(f.d), 2, "0")
            case "e": num(Int64(f.d), 2, "_")
            case "H": num(Int64(f.h), 2, "0")
            case "I": num(Int64((f.h + 11) % 12 + 1), 2, "0")
            case "M": num(Int64(f.mi), 2, "0")
            case "S": num(Int64(f.s), 2, "0")
            case "L": num(Int64(f.ms), 3, "0")
            case "j": num(doy, 3, "0")
            case "p": out += f.h < 12 ? "AM" : "PM"
            case "b": out += String(MONTHS[Int(f.mo) - 1].prefix(3))
            case "B": out += MONTHS[Int(f.mo) - 1]
            case "a": out += String(DAYS[Int(f.wd)].prefix(3))
            case "A": out += DAYS[Int(f.wd)]
            default: out.append(code)
            }
        }
        return out
    }

    /// A step between axis ticks, aligned to the calendar.
    enum Step: Equatable {
        case ms(Double)
        case days(UInt32)
        case weeks(UInt32)
        case months(UInt32)

        /// The step's rough length, for spacing ticks.
        func len() -> Double {
            switch self {
            case .ms(let ms): return ms
            case .days(let n): return Double(n) * DAY
            case .weeks(let n): return Double(n) * 7.0 * DAY
            case .months(let n): return Double(n) * 30.44 * DAY
            }
        }

        /// `1day`, `2week`, `6hour`, `1month` (Mermaid's `tickInterval`).
        static func parse(_ s: String) -> Step? {
            let trimmed = s.trimmed()
            let numPart = trimmed.prefix { $0.isASCII && $0 >= "0" && $0 <= "9" }
            guard !numPart.isEmpty, let v = UInt32(numPart), (1...1000).contains(v) else {
                return nil
            }
            let unit = trimmed.dropFirst(numPart.count).trimmed()
            switch unit {
            case "millisecond": return .ms(Double(v))
            case "second": return .ms(Double(v) * SEC)
            case "minute": return .ms(Double(v) * MIN)
            case "hour": return .ms(Double(v) * HOUR)
            case "day": return .days(v)
            case "week": return .weeks(v)
            case "month": return .months(v)
            default: return nil
            }
        }

        /// The steps an axis picks from, finest first.
        static let LADDER: [Step] = [
            .ms(SEC),
            .ms(5.0 * SEC),
            .ms(15.0 * SEC),
            .ms(30.0 * SEC),
            .ms(MIN),
            .ms(5.0 * MIN),
            .ms(15.0 * MIN),
            .ms(30.0 * MIN),
            .ms(HOUR),
            .ms(3.0 * HOUR),
            .ms(6.0 * HOUR),
            .ms(12.0 * HOUR),
            .days(1),
            .days(2),
            .weeks(1),
            .weeks(2),
            .months(1),
            .months(3),
            .months(6),
            .months(12),
            .months(60),
        ]

        /// Ticks from `lo` to `hi` inclusive, at most `maxCount` of them: midnights for days, Sundays for
        /// weeks, the first of the month for months.
        func ticks(_ lo: Double, _ hi: Double, _ maxCount: Int) -> [Double] {
            var t: Double
            switch self {
            case .ms(let ms):
                t = (lo / ms).rounded(.up) * ms
            case .days(let n):
                var day = Int64((lo / DAY).rounded(.up))
                while (civilFromDays(day).2 - 1) % n != 0 {
                    day += 1
                }
                t = Double(day) * DAY
            case .weeks:
                let day = Int64((lo / DAY).rounded(.up))
                t = Double(day + (7 - remEuclid(day + 4, 7)) % 7) * DAY
            case .months(let n):
                let f = fields(lo)
                var m0 = f.y * 12 + Int64(f.mo) - 1
                if let first = at(f.y, f.mo, 1, 0, 0, 0, 0), first < lo {
                    m0 += 1
                }
                while remEuclid(m0, Int64(n)) != 0 {
                    m0 += 1
                }
                t = at(divEuclid(m0, 12), UInt32(remEuclid(m0, 12)) + 1, 1, 0, 0, 0, 0) ?? lo
            }
            var out: [Double] = []
            while t <= hi + 1e-6 && out.count < maxCount {
                out.append(t)
                switch self {
                case .ms(let ms):
                    t += ms
                case .weeks(let n):
                    t += Double(n) * 7.0 * DAY
                case .days(let n):
                    // Back to the 1st at month ends, as d3 does.
                    let next = t + Double(n) * DAY
                    let f = fields(t)
                    let g = fields(next)
                    if g.mo != f.mo && g.d > 1 {
                        t = at(g.y, g.mo, 1, 0, 0, 0, 0) ?? next
                    } else {
                        t = next
                    }
                case .months(let n):
                    t = addMonths(t, Int64(n))
                }
            }
            return out
        }
    }
}
