import Foundation
import Testing
@testable import KelimeDefteri

/// Öğrenilme tarihi (`Word.learnedAt`) "Bu Hafta" sayfasında haftalık sayılır. Tarihin kendisini
/// hafıza motoru yazar (bkz. `MotorReplayTests`).
struct LearnedDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 21 Eylül 2026 + gün, verilen saat (İstanbul).
    private func day(_ offset: Int, _ hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func weeklySummaryCountsLearnedThisWeek() {
        let now = day(0, 12)
        let summary = WeeklySummary<Int>(
            answers: [],
            learnedDates: [day(0), day(-6, 0), day(-7, 23), day(-30), nil, day(1)],
            now: now,
            calendar: calendar
        )
        #expect(summary.learnedCount == 6)
        // Bugün ve 6 gün önce (gün başı dahil) sayılır; 7 gün önce, bilinmeyen ve yarın sayılmaz.
        #expect(summary.learnedThisWeek == 2)

        let empty = WeeklySummary<Int>(answers: [], now: now, calendar: calendar)
        #expect(empty.learnedCount == 0)
        #expect(empty.learnedThisWeek == 0)
    }
}
