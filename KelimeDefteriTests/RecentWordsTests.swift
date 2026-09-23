import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Yeni Eklenenler turu: Günlük Tekrar'ın bugün almadığı yeni kelimeler.
struct RecentWordsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// `minutesAgo` dakika önce eklenmiş, hiç çalışılmamış kelime.
    private func newWord(_ english: String, minutesAgo: Double, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: "anlam \(english)", createdAt: now.addingTimeInterval(-minutesAgo * 60))
        context.insert(word)
        return word
    }

    /// Çalışılmış ve zayıflamış kelime.
    private func weakWord(_ english: String, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: "anlam \(english)")
        context.insert(word)
        word.reviewCount = 2
        word.correctCount = 2
        word.stability = 3
        word.difficulty = 5
        word.lastReviewedAt = now.addingTimeInterval(-10 * Memory.dayLength)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(3 * Memory.dayLength)
        return word
    }

    /// n0 en eski, n(count-1) en yeni eklenen.
    private func newWords(_ count: Int, in context: ModelContext) -> [Word] {
        (0..<count).map { newWord("n\($0)", minutesAgo: Double(count - $0), in: context) }
    }

    @Test func rowAppearsOnlyWhenDailyReviewLeavesNewWords() throws {
        let context = try makeContext()
        // 5 yeniyi Günlük Tekrar alır; bekleyen yok.
        let five = newWords(5, in: context)
        #expect(StudySession.recentWaitingCount(five, now: now) == 0)
        #expect(StudySession.recentWords(five, now: now).isEmpty)

        let twelve = newWords(12, in: context)
        #expect(StudySession.recentWaitingCount(twelve, now: now) == 7)

        // Günlük Tekrar 20 zayıfla doluysa hiç yeni almaz; bütün yeniler bekler.
        let weak = (0..<20).map { weakWord("w\($0)", in: context) }
        #expect(StudySession.recentWaitingCount(weak + five, now: now) == 5)
        // Yeni yoksa satır yok.
        #expect(StudySession.recentWaitingCount(weak, now: now) == 0)
        #expect(RoundText.recentWaiting(12) == "12 yeni kelime sırada")
    }

    @Test func takesAtMostTenNewestFirstWithoutDailyOverlap() throws {
        let context = try makeContext()
        let words = newWords(20, in: context)
        let recent = StudySession.recentWords(words, now: now)
        #expect(recent.map(\.english) == (10..<20).reversed().map { "n\($0)" })

        let daily = StudySession.dailyNewWords(words, now: now)
        #expect(daily.map(\.english) == (0..<5).map { "n\($0)" })
        #expect(Set(recent.map(ObjectIdentifier.init)).isDisjoint(with: daily.map(ObjectIdentifier.init)))
    }

    @Test func dailyAndRecentRoundsNeverAskTheSameWord() throws {
        for seed in 0..<10 as Range<UInt64> {
            let context = try makeContext()
            let words = newWords(12, in: context) + (0..<3).map { weakWord("w\($0)", in: context) }
            // İkisi de aynı anda açılır: sıraları baştan bellidir.
            let daily = StudySession(seed: seed, defaults: defaults())
            daily.start(with: words, plan: .daily, now: now)
            let recent = StudySession(seed: seed, defaults: defaults())
            recent.start(with: words, plan: .recent, now: now)
            var dailyAsked: Set<ObjectIdentifier> = []
            var recentAsked: Set<ObjectIdentifier> = []
            while let current = recent.current {
                recentAsked.insert(ObjectIdentifier(current))
                recent.grade(known: true, now: now)
            }
            while let current = daily.current {
                dailyAsked.insert(ObjectIdentifier(current))
                daily.grade(known: true, now: now)
            }
            #expect(recentAsked.count == 7)
            #expect(dailyAsked.count == 8)
            #expect(recentAsked.isDisjoint(with: dailyAsked))
        }
    }

    @Test func answersStartMemory() throws {
        let context = try makeContext()
        let words = newWords(8, in: context)
        let session = StudySession(seed: 3, defaults: defaults())
        session.mode = .dailyReview
        session.start(with: words, plan: .recent, now: now)
        #expect(session.wordCount == 3)
        let first = try #require(session.current)
        #expect(first.memory(at: now) == nil)
        session.reveal(answer: first.turkish, now: now)
        session.grade(known: true, now: now)
        #expect(!first.isNew)
        #expect(first.memory(at: now) != nil)
        #expect(first.reviewCount == 1)
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.mode == GameMode.dailyReview.rawValue)
        // Tanışılan kelime artık bekleyenlerden sayılmaz.
        #expect(StudySession.recentWaitingCount(words, now: now) == 2)
    }
}
