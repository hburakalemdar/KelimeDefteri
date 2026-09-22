import Foundation
import Testing
@testable import KelimeDefteri

struct ReminderPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// 22 Eylül 2026, belirtilen saat (İstanbul).
    private func date(day: Int = 22, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func firstReminderIsTodayWhenTimeHasNotPassed() {
        let plan = ReminderPlanner.plan(
            dueDates: [date(hour: 9)], hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(hour: 20))
        #expect(plan.first?.dueCount == 1)
    }

    @Test func firstReminderIsTomorrowWhenTimeHasPassed() {
        let plan = ReminderPlanner.plan(
            dueDates: [date(hour: 9)], hour: 20, minute: 0, now: date(hour: 21), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(day: 23, hour: 20))
    }

    @Test func countsGrowAsWordsBecomeDue() {
        let plan = ReminderPlanner.plan(
            dueDates: [date(hour: 8), date(day: 24, hour: 0), date(day: 24, hour: 0)],
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.map(\.dueCount).prefix(3) == [1, 1, 3])
    }

    @Test func skipsDaysWithNothingDue() {
        let plan = ReminderPlanner.plan(
            dueDates: [date(day: 25, hour: 0)], hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(day: 25, hour: 20))
        #expect(plan.count == 4) // 7 günlük pencere 22–28 Eylül; kelime 25'inden itibaren sırada.
    }

    @Test func emptyDeckHasNoReminders() {
        #expect(ReminderPlanner.plan(dueDates: [], hour: 20, minute: 0, now: date(hour: 10), calendar: calendar).isEmpty)
    }
}
