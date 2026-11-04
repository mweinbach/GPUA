// Tests ported from: crates/rune-mermaid/src/date_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMermaid

@Suite struct DateTests {
    @Test func civilDaysRoundTrip() {
        #expect(date.daysFromCivil(1970, 1, 1) == 0)
        #expect(date.daysFromCivil(2000, 3, 1) == 11_017)
        for z: Int64 in [-800_000, -1, 0, 59, 11_016, 19_723, 2_000_000] {
            let (y, m, d) = date.civilFromDays(z)
            #expect(date.daysFromCivil(y, m, d) == z)
        }
        #expect(date.fields(Double(date.daysFromCivil(2024, 1, 7)) * date.DAY).wd == 0)
    }

    @Test func readsDayjsFormatsAndIso() {
        let jan5 = Double(date.daysFromCivil(2024, 1, 5)) * date.DAY
        #expect(date.parse("2024-01-05", "YYYY-MM-DD") == jan5)
        #expect(date.parse("05/01/2024", "DD/MM/YYYY") == jan5)
        #expect(date.parse("2024-01-05 13:30", "YYYY-MM-DD HH:mm") == jan5 + 13.5 * date.HOUR)
        #expect(date.parse("Jan 5 2024 1:30 pm", "MMM D YYYY h:mm a") == jan5 + 13.5 * date.HOUR)
        #expect(date.parse("2024-01-05", "DD.MM.YY") == jan5)
        #expect(date.parse("1704412800", "X") == jan5)
        #expect(date.parse("2024-02-30", "YYYY-MM-DD") == nil)
        #expect(date.parse("soon", "YYYY-MM-DD") == nil)
        #expect(date.parse("99999999999999999999", "X") == nil)
    }

    @Test func spansAndMonths() {
        let jan31 = Double(date.daysFromCivil(2024, 1, 31)) * date.DAY
        #expect(date.span("3d") == .ms(3.0 * date.DAY))
        #expect(date.span("1.5h") == .ms(1.5 * date.HOUR))
        #expect(date.span("2w") == .ms(14.0 * date.DAY))
        #expect(date.span("3x") == nil)
        #expect(date.Span.months(1.0).after(jan31) == Double(date.daysFromCivil(2024, 2, 29)) * date.DAY)
    }

    @Test func printsD3Formats() {
        let t = Double(date.daysFromCivil(2024, 3, 7)) * date.DAY + 15.0 * date.HOUR + 4.0 * date.MIN
        #expect(date.format(t, "%Y-%m-%d") == "2024-03-07")
        #expect(date.format(t, "%b %-d") == "Mar 7")
        #expect(date.format(t, "%a %e %I:%M %p") == "Thu  7 03:04 PM")
        #expect(date.format(t, "%B %j %%") == "March 067 %")
    }

    @Test func ticksLandOnTheCalendar() {
        let lo = Double(date.daysFromCivil(2024, 1, 3)) * date.DAY + date.HOUR
        let hi = Double(date.daysFromCivil(2024, 4, 20)) * date.DAY
        let day: (Double) -> [Int64] = { t in
            let (y, m, d) = date.civilFromDays(Int64(t / date.DAY))
            return [y, Int64(m), Int64(d)]
        }
        let weeks = date.Step.weeks(1).ticks(lo, hi, 100)
        #expect(day(weeks[0]) == [2024, 1, 7])
        #expect(weeks.allSatisfy { date.fields($0).wd == 0 })
        let months = date.Step.months(1).ticks(lo, hi, 100)
        #expect(months.map(day) == [[2024, 2, 1], [2024, 3, 1], [2024, 4, 1]])
        #expect(date.Step.days(1).ticks(lo, hi, 5).count == 5)
        #expect(date.Step.parse("2week") == .weeks(2))
        #expect(date.Step.parse("6hour") == .ms(6.0 * date.HOUR))
    }
}
