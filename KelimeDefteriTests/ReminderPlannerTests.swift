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
            studiedDueDates: [date(hour: 9)], newCount: 0, introducedToday: 0, newAllowance: 10, hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(hour: 20))
        #expect(plan.first?.dueCount == 1)
    }

    @Test func firstReminderIsTomorrowWhenTimeHasPassed() {
        let plan = ReminderPlanner.plan(
            studiedDueDates: [date(hour: 9)], newCount: 0, introducedToday: 0, newAllowance: 10, hour: 20, minute: 0, now: date(hour: 21), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(day: 23, hour: 20))
    }

    @Test func countsGrowAsWordsBecomeDue() {
        let plan = ReminderPlanner.plan(
            studiedDueDates: [date(hour: 8), date(day: 24, hour: 0), date(day: 24, hour: 0)],
            newCount: 0, introducedToday: 0, newAllowance: 10, hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.map(\.dueCount).prefix(3) == [1, 1, 3])
    }

    @Test func skipsDaysWithNothingDue() {
        let plan = ReminderPlanner.plan(
            studiedDueDates: [date(day: 25, hour: 0)], newCount: 0, introducedToday: 0, newAllowance: 10, hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(day: 25, hour: 20))
        #expect(plan.count == 4) // 7 günlük pencere 22–28 Eylül; kelime 25'inden itibaren sırada.
    }

    /// Isınıp üretimi yarıda kalan kelime vadesi gelmemiş olsa da bugünün bildiriminde sayılır; ertesi gün vadesiyle.
    @Test func pendingProductionCountsToday() {
        let plan = ReminderPlanner.plan(
            studiedDueDates: [], pendingDueDates: [date(day: 24, hour: 4)], newCount: 0, introducedToday: 1, newAllowance: 10,
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(hour: 20))
        #expect(plan.first?.dueCount == 1)
        #expect(plan.dropFirst().first?.fireDate == date(day: 24, hour: 20))
    }

    @Test func emptyDeckHasNoReminders() {
        #expect(ReminderPlanner.plan(studiedDueDates: [], newCount: 0, introducedToday: 0, newAllowance: 10, hour: 20, minute: 0, now: date(hour: 10), calendar: calendar).isEmpty)
    }

    /// Bildirim Günlük Tekrar'ın bugünkü toplamını söyler: vadesi gelenlerin hepsi (tavan 100) + yeni hakkı;
    /// tekrarlar 100'ü aşınca o gün yeni yok.
    @Test func countsFollowTheDailyReviewLimits() {
        let onlyNew = ReminderPlanner.plan(
            studiedDueDates: [date(day: 30, hour: 0)], newCount: 12, introducedToday: 0, newAllowance: 10,
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(onlyNew.first?.dueCount == 10)
        #expect(onlyNew.count == 7)

        let many = ReminderPlanner.plan(
            studiedDueDates: Array(repeating: date(hour: 8), count: 34), newCount: 12, introducedToday: 0, newAllowance: 10,
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(many.first?.dueCount == 44)
        let piledUp = Array(repeating: date(hour: 8), count: 120)
        #expect(ReminderPlanner.dailyCount(studiedDueDates: piledUp, newCount: 3, introducedToday: 0, newAllowance: 10,
                                           at: date(hour: 20), offset: 0) == 100)
    }

    /// Hak parametresi: ileri günlerde yeni tahmini `min(hak, newCount)`.
    @Test func newAllowanceSetsTheNewEstimate() {
        func counts(_ allowance: Int, newCount: Int) -> [Int] {
            ReminderPlanner.plan(
                studiedDueDates: [], newCount: newCount, introducedToday: 0, newAllowance: allowance,
                hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
            ).map(\.dueCount)
        }
        #expect(counts(5, newCount: 12) == Array(repeating: 5, count: 7))
        #expect(counts(15, newCount: 12) == Array(repeating: 12, count: 7))
        #expect(counts(20, newCount: 30) == Array(repeating: 20, count: 7))
    }

    /// Bugün tanıtılan yeni kelimeler yalnızca bugünün bildirimini kısar; ileri günler yeni hakkına kadar
    /// yeni kelime bekler (çalışılmış kelimesi hep güçlü defterde bildirim susmaz).
    @Test func introducedTodayLimitsOnlyToday() {
        let plan = ReminderPlanner.plan(
            studiedDueDates: [date(day: 30, hour: 0)], newCount: 12, introducedToday: 10, newAllowance: 10,
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(plan.first?.fireDate == date(day: 23, hour: 20))
        #expect(plan.first?.dueCount == 10)
        #expect(plan.count == 6)

        let partly = ReminderPlanner.plan(
            studiedDueDates: [], newCount: 12, introducedToday: 3, newAllowance: 5,
            hour: 20, minute: 0, now: date(hour: 10), calendar: calendar
        )
        #expect(partly.map(\.dueCount) == [2, 5, 5, 5, 5, 5, 5])
    }

    /// Bugün tekrar olarak cevaplananlar yalnız bugünün "yük 100'ü aştı, yeni yok" kuralına sayılır.
    @Test func reviewedTodayCountsOnlyForToday() {
        let due = Array(repeating: date(hour: 8), count: 90)
        #expect(ReminderPlanner.dailyCount(studiedDueDates: due, newCount: 5, introducedToday: 0, newAllowance: 10,
                                           reviewedToday: 20, at: date(hour: 20), offset: 0) == 90)
        #expect(ReminderPlanner.dailyCount(studiedDueDates: due, newCount: 5, introducedToday: 0, newAllowance: 10,
                                           reviewedToday: 20, at: date(day: 23, hour: 20), offset: 1) == 95)
    }
}
