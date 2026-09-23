import Foundation
import Testing
@testable import KelimeDefteri

struct WordStatsTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ minute: Int, _ mode: GameMode, correct: Bool = true, time: Double = 0) -> WordStats.Entry {
        WordStats.Entry(date: start.addingTimeInterval(Double(minute) * 60), mode: mode.rawValue, correct: correct, responseTime: time)
    }

    @Test func recentIsOldestFirstAndLimited() {
        let entries = (0..<40).reversed().map { entry($0, .dailyReview, correct: $0.isMultiple(of: 2)) }
        let stats = WordStats(entries: entries)
        #expect(stats.recent.count == 30)
        #expect(stats.recent.first?.date == start.addingTimeInterval(10 * 60))
        #expect(stats.recent.last?.date == start.addingTimeInterval(39 * 60))
    }

    @Test func countsByModeMostFirst() {
        let stats = WordStats(entries: [
            entry(0, .match), entry(1, .dailyReview), entry(2, .dailyReview), entry(3, .match), entry(4, .dailyReview),
        ])
        #expect(stats.countsText == "Günlük Tekrar 3 · Eşleştir 2")
    }

    @Test func averageIgnoresUntimedAnswers() {
        let stats = WordStats(entries: [entry(0, .dailyReview, time: 3), entry(1, .match), entry(2, .dailyReview, time: 5)])
        #expect(stats.averageResponseTime == 4)
        #expect(WordStats(entries: [entry(0, .match)]).averageResponseTime == nil)
        #expect(WordStats(entries: []).countsText.isEmpty)
    }
}
