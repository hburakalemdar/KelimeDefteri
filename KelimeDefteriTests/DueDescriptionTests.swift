import Foundation
import Testing
@testable import KelimeDefteri

struct DueDescriptionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func pastIsNow() {
        #expect(Leitner.dueDescription(for: now.addingTimeInterval(-60), now: now, calendar: calendar) == "Şimdi")
    }

    @Test func countsCalendarDaysNotHours() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        #expect(Leitner.dueDescription(for: tomorrow, now: now, calendar: calendar) == "Yarın")
        let later = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        #expect(Leitner.dueDescription(for: later.addingTimeInterval(3600), now: now, calendar: calendar) == "3 gün sonra")
        #expect(Leitner.dueDescription(for: now.addingTimeInterval(60), now: now, calendar: calendar) == "Bugün")
    }
}
