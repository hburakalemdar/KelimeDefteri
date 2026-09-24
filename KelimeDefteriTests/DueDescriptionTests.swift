import Foundation
import Testing
@testable import KelimeDefteri

/// Vade metni: kırmızı "Şimdi" yok; gün 04:00'te döner (SPEC-MOTOR2 §4.2).
struct DueDescriptionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// 21 Eylül 2026, 17:13 (İstanbul).
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Bugünden `offset` gün sonraki günün başı (04:00).
    private func dayStart(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: DayBoundary.start(of: now, calendar: calendar))!
    }

    @Test func pastIsTodayOrOverdueNeverNow() {
        #expect(Leitner.dueDescription(for: now.addingTimeInterval(-60), now: now, calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: dayStart(0), now: now, calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: dayStart(-1).addingTimeInterval(3600), now: now, calendar: calendar) == "1 gün gecikti")
        #expect(Leitner.dueDescription(for: dayStart(-3), now: now, calendar: calendar) == "3 gün gecikti")
    }

    @Test func countsDaysNotHours() {
        #expect(Leitner.dueDescription(for: dayStart(1), now: now, calendar: calendar) == "Yarın")
        // Gece yarısından sonra ama 04:00'ten önce: hâlâ bugün.
        #expect(Leitner.dueDescription(for: dayStart(1).addingTimeInterval(-3600), now: now, calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: dayStart(3).addingTimeInterval(3600), now: now, calendar: calendar) == "3 gün sonra")
        #expect(Leitner.dueDescription(for: now.addingTimeInterval(60), now: now, calendar: calendar) == "Bugün")
    }

    @Test func newWordHasNoDue() {
        #expect(Leitner.dueDescription(for: .distantPast, now: now, calendar: calendar) == "Yeni")
    }
}
