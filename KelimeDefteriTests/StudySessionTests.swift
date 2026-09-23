import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

struct StudySessionTests {
    /// Her test kendi ayar deposunu kullanır; önceki turun ilk kelimesi testler arasında taşınmasın.
    private func makeSession(seed: UInt64 = 1, defaults: UserDefaults? = nil) -> StudySession {
        StudySession(seed: seed, defaults: defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    /// `days > 0`: hafızası güçlü kelime (zayıflamasına o kadar gün var gibi düşünülebilir);
    /// `days ≤ 0`: çalışılmış ama zayıflamış kelime, sayı küçüldükçe daha zayıf.
    private func word(_ english: String, dueIn days: Double) -> Word {
        let word = Word(english: english, turkish: "anlam")
        word.reviewCount = 1
        if days > 0 {
            word.stability = 10
            word.lastReviewedAt = .now
        } else {
            word.stability = 1
            word.lastReviewedAt = Date.now.addingTimeInterval((days - 2) * 86_400)
        }
        return word
    }

    @Test func dueModeAsksOnlyWeakWords() {
        let session = makeSession()
        let later = word("later", dueIn: 2)
        let older = word("older", dueIn: -3)
        let recent = word("recent", dueIn: -1)

        session.start(with: [later, recent, older], practiceAll: false)

        #expect(["older", "recent"].contains(session.current?.english))
        #expect(session.remaining == 1)
    }

    @Test func sameSeedGivesSameOrder() {
        // Cevaplar kelimelerin hafızasını değiştirdiği için her çalıştırma taze kelimelerle başlar.
        func order(seed: UInt64) -> [String] {
            let words = (0..<8).map { word("w\($0)", dueIn: -Double($0)) }
            let session = makeSession(seed: seed)
            session.start(with: words, practiceAll: true)
            var result: [String] = []
            while let current = session.current {
                result.append(current.english)
                session.grade(known: true)
            }
            return result
        }
        #expect(order(seed: 42) == order(seed: 42))
        #expect(Set(order(seed: 42)) == Set((0..<8).map { "w\($0)" }))
    }

    @Test func newRoundDoesNotStartWithPreviousFirstWord() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let words = (0..<5).map { word("w\($0)", dueIn: -1) }
        var previous: String?
        for seed in 0..<30 as Range<UInt64> {
            let session = makeSession(seed: seed, defaults: defaults)
            session.start(with: words, practiceAll: true)
            #expect(session.current?.english != previous)
            previous = session.current?.english
        }
    }

    @Test func unknownWordComesBackAfterTwoOthers() {
        let session = makeSession()
        let words = (0..<5).map { word("w\($0)", dueIn: -1) }
        session.start(with: words, practiceAll: false)
        let missed = session.current
        session.grade(known: false)

        var seen: [Word?] = []
        while let current = session.current, seen.count < 10 {
            seen.append(current)
            session.grade(known: true)
        }
        #expect(seen.firstIndex { $0 === missed } == 2)
        #expect(seen.count == 5)
    }

    @Test func practiceAllIncludesNotYetDueWords() {
        let session = makeSession()
        session.start(with: [word("a", dueIn: 5), word("b", dueIn: 9)], practiceAll: true)
        #expect(session.current != nil)
        #expect(session.remaining == 1)
    }

    @Test func correctAnswerIsDetectedAndKnownWordLeavesQueue() {
        let session = makeSession()
        let target = word("stale", dueIn: -1)
        target.turkish = "eskimiş, güncel olmayan"
        session.start(with: [target], practiceAll: false)

        session.reveal(answer: "eskimis")
        #expect(session.phase == .revealed(.correct))

        session.grade(known: true)
        #expect(target.stability > 1)
        #expect(target.correctCount == 1)
        #expect(target.reviewCount == 2)
        #expect(!target.isWeak)
        #expect(session.current == nil)
    }

    /// `sync` kelimeleri kimlikleriyle eşlediği için gerçek bir depoya eklenmeleri gerekir.
    /// Bellek içi depo iOS 27 simülatöründe kaydederken ara ara çöktüğü için geçici dosya kullanılır.
    private func insert(_ words: Word...) throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(for: SharedStore.schema, configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        words.forEach(context.insert)
        try context.save()
        return context
    }

    @Test func wordAddedDuringRoundJoinsTheQueue() throws {
        let first = word("first", dueIn: -1)
        let added = word("added", dueIn: -1)
        let context = try insert(first)
        let session = makeSession()
        session.start(with: [first], practiceAll: false)

        context.insert(added)
        try context.save()
        session.sync(with: [first, added])

        #expect(session.current?.english == "first")
        #expect(session.remaining == 1)
        session.grade(known: true)
        #expect(session.current?.english == "added")
    }

    @Test func finishedRoundContinuesWithNewDueWord() throws {
        let first = word("first", dueIn: -1)
        let added = word("added", dueIn: -1)
        let later = word("later", dueIn: 3)
        let context = try insert(first, later)
        let session = makeSession()
        session.start(with: [first, later], practiceAll: false)
        session.grade(known: true)
        #expect(session.current == nil)

        context.insert(added)
        try context.save()
        session.sync(with: [first, later, added])

        // "first" bilindiği için hafızası güçlendi; "later" zaten güçlü.
        #expect(session.current?.english == "added")
        #expect(session.remaining == 0)
    }

    @Test func syncDropsDeletedWords() throws {
        let first = word("first", dueIn: -2)
        let second = word("second", dueIn: -1)
        let context = try insert(first, second)
        let session = makeSession()
        session.start(with: [first, second], practiceAll: false)

        context.delete(first)
        try context.save()
        session.sync(with: [second])

        #expect(session.current?.english == "second")
        #expect(session.remaining == 0)
    }

    @Test func unknownWordGoesToEndWhenFewWordsLeft() {
        let session = makeSession()
        let first = word("first", dueIn: -2)
        let second = word("second", dueIn: -1)
        session.start(with: [first, second], practiceAll: false)
        let missed = session.current

        session.reveal(answer: nil)
        #expect(session.phase == .revealed(.peeked))
        session.grade(known: false)

        #expect(session.current !== missed)
        session.grade(known: true)
        #expect(session.current === missed)
    }

    @Test func newWordCountsAsWeak() {
        let session = makeSession()
        session.start(with: [Word(english: "fresh", turkish: "taze"), word("strong", dueIn: 3)], practiceAll: false)
        #expect(session.current?.english == "fresh")
        #expect(session.remaining == 0)
    }

    @Test func practiceAllTakesTheWeakestTen() {
        let session = makeSession()
        let strong = (0..<12).map { word("s\($0)", dueIn: Double($0 + 1)) }
        let weak = word("weak", dueIn: -5)
        session.start(with: strong + [weak], practiceAll: true)
        var asked: [String] = []
        while let current = session.current {
            asked.append(current.english)
            session.grade(known: true)
        }
        #expect(asked.count == 10)
        #expect(asked.contains("weak"))
    }

    @Test func answerIsRecordedWithGradeModeAndTime() throws {
        let target = word("stale", dueIn: -1)
        target.turkish = "eskimiş"
        let context = try insert(target)
        let session = makeSession()
        session.mode = .quickRound
        let start = Date.now
        session.start(with: [target], practiceAll: false, now: start)
        session.reveal(answer: "eskimis", now: start.addingTimeInterval(6))
        session.grade(known: true, now: start.addingTimeInterval(8))

        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.mode == "quick")
        #expect(logs.first?.grade == AnswerGrade.good.rawValue)
        #expect(logs.first?.correct == true)
        #expect(logs.first?.responseTime == 6)
        #expect(logs.first?.word === target)
        #expect(target.lastReviewedAt == start.addingTimeInterval(8))
    }
}
