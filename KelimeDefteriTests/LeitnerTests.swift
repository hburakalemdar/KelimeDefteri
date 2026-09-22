import Foundation
import Testing
@testable import KelimeDefteri

struct LeitnerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func knownWordMovesUpOneBox() {
        let result = Leitner.review(box: 0, known: true, now: now, calendar: calendar)
        #expect(result.box == 1)
        #expect(result.due > now)
    }

    @Test func unknownWordResetsAndIsDueImmediately() {
        let result = Leitner.review(box: 4, known: false, now: now, calendar: calendar)
        #expect(result.box == 0)
        #expect(result.due == now)
    }

    @Test func boxIsCappedAtMax() {
        let result = Leitner.review(box: Leitner.maxBox, known: true, now: now, calendar: calendar)
        #expect(result.box == Leitner.maxBox)
    }

    @Test(arguments: 1...5)
    func dueDateIsStartOfDayAfterInterval(box: Int) {
        let result = Leitner.review(box: box - 1, known: true, now: now, calendar: calendar)
        let expected = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: Leitner.intervalsInDays[box], to: now)!
        )
        #expect(result.due == expected)
    }
}

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
        let result = Leitner.review(box: 0, known: true, now: now, calendar: calendar)
        #expect(Leitner.dueDescription(for: result.due, now: now, calendar: calendar) == "Yarın")
        let later = Leitner.review(box: 1, known: true, now: now, calendar: calendar)
        #expect(Leitner.dueDescription(for: later.due, now: now, calendar: calendar) == "3 gün sonra")
    }

    @Test func boxNames() {
        #expect(Leitner.boxDescription(0) == "Yeni")
        #expect(Leitner.boxDescription(2) == "3 günde bir")
        #expect(Leitner.boxDescription(Leitner.maxBox) == "Öğrenildi")
    }
}
