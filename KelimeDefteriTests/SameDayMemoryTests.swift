import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// "Yine de Çalış"ın zorlanılan kelimeleri önce getirmesi. (Aynı gün kuralı artık günün notunda, `MotorReplayTests`.)
struct SameDayMemoryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 21 Eylül 2026, verilen saat ve dakika (İstanbul).
    private func day(_ offset: Int = 0, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    // MARK: - Yine de Çalış

    /// Güçlü kelime; `age` gün önce tekrar edilmiş (büyüdükçe hafızası düşer).
    private func practiced(_ english: String, age: Double, in context: ModelContext, now: Date) -> Word {
        let word = Word(english: english, turkish: "anlam")
        context.insert(word)
        word.stability = 30
        word.reviewCount = 1
        word.correctCount = 1
        word.lastReviewedAt = now.addingTimeInterval(-age * Memory.dayLength)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(30 * Memory.dayLength)
        return word
    }

    /// Verilen cevapları (eskiden yeniye, `daysAgo` önce) kelimeye kayıt olarak ekler.
    private func addLogs(_ answers: [(daysAgo: Double, correct: Bool)], to word: Word, in context: ModelContext, now: Date) {
        for answer in answers {
            let log = ReviewLog(
                date: now.addingTimeInterval(-answer.daysAgo * Memory.dayLength), mode: GameMode.dailyReview.rawValue,
                correct: answer.correct, grade: answer.correct ? 3 : 1, responseTime: 3
            )
            context.insert(log)
            log.word = word
        }
    }

    /// Turun sorduğu kelimeler, soruldukları sırayla (hepsi bilinir).
    private func askedWords(_ session: StudySession, now: Date) -> [String] {
        var asked: [String] = []
        while let word = session.current {
            asked.append(word.english)
            session.play(known: true, now: now)
        }
        return asked
    }

    @Test func strugglingRule() throws {
        let context = try makeContext()
        let now = day(0, 12)
        let half = practiced("half", age: 1, in: context, now: now)
        addLogs([(3, false), (2, true)], to: half, in: context, now: now)
        let lastWrong = practiced("lastWrong", age: 1, in: context, now: now)
        addLogs([(1, false)], to: lastWrong, in: context, now: now)
        let third = practiced("third", age: 1, in: context, now: now)
        addLogs([(4, false), (3, true), (2, true)], to: third, in: context, now: now)
        let old = practiced("old", age: 1, in: context, now: now)
        addLogs([(20, false), (19, false), (1, true)], to: old, in: context, now: now)
        let forty = practiced("forty", age: 1, in: context, now: now)
        addLogs([(5, false), (4, true), (3, false), (2, true), (1, true)], to: forty, in: context, now: now)
        try context.save()

        #expect(StudySession.isStruggling(half, now: now))
        #expect(StudySession.isStruggling(lastWrong, now: now))
        #expect(!StudySession.isStruggling(third, now: now))
        #expect(!StudySession.isStruggling(old, now: now))
        #expect(StudySession.isStruggling(forty, now: now))
    }

    @Test func extraPracticeBringsStrugglingWordsFirstAndFillsTen() throws {
        let context = try makeContext()
        let now = day(0, 12)
        // Zorlanılanların hafızası yüksek: yalnızca hafızaya bakılsa seçilmezlerdi.
        var struggling: [Word] = []
        for index in 0..<3 {
            let word = practiced("hard\(index)", age: 0.5, in: context, now: now)
            addLogs([(2, false), (1, true)], to: word, in: context, now: now)
            struggling.append(word)
        }
        // Zorlanılmayanlar: yaşları büyüdükçe hafızaları düşer; en zayıf 7'si (w8…w14) seçilmeli.
        var others: [Word] = []
        for index in 0..<15 {
            let word = practiced("w\(index)", age: Double(index + 1), in: context, now: now)
            addLogs([(3, true)], to: word, in: context, now: now)
            others.append(word)
        }
        try context.save()

        let session = StudySession(seed: 7, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        session.start(with: others + struggling, plan: .extraPractice, now: now)
        let asked = askedWords(session, now: now)
        #expect(asked.count == StudySession.extraPracticeCount)
        #expect(Set(asked.prefix(3)) == Set(struggling.map(\.english)))
        #expect(Set(asked.dropFirst(3)) == Set((8..<15).map { "w\($0)" }))
    }

    @Test func extraPracticeTakesAtMostTenStrugglingWords() throws {
        let context = try makeContext()
        let now = day(0, 12)
        var words: [Word] = []
        for index in 0..<12 {
            let word = practiced("hard\(index)", age: 1, in: context, now: now)
            addLogs([(1, false)], to: word, in: context, now: now)
            words.append(word)
        }
        words.append(practiced("weakest", age: 60, in: context, now: now))
        try context.save()

        let session = StudySession(seed: 3, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        session.start(with: words, plan: .extraPractice, now: now)
        let asked = askedWords(session, now: now)
        #expect(asked.count == StudySession.extraPracticeCount)
        #expect(asked.allSatisfy { $0.hasPrefix("hard") })
    }
}
