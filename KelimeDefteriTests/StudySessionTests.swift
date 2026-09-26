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
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(word.stability * 86_400)
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
                session.play(known: true)
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
        session.play(known: false)

        var seen: [Word?] = []
        while let current = session.current, seen.count < 10 {
            seen.append(current)
            session.play(known: true)
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

    @Test func correctAnswerIsDetectedAndKnownWordLeavesQueue() throws {
        let session = makeSession()
        let target = word("stale", dueIn: -1)
        target.turkish = "eskimiş, güncel olmayan"
        _ = try insert(target)
        session.start(with: [target], practiceAll: false)

        session.reveal(answer: "eskimis")
        #expect(session.phase == .revealed(.correct))

        session.play(known: true)
        #expect(target.stability > 1)
        #expect(target.correctAnswerCount == 1)
        #expect(target.logs?.count == 1)
        #expect(!target.isDue())
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
        session.play(known: true)
        #expect(session.current?.english == "added")
    }

    @Test func finishedRoundContinuesWithNewDueWord() throws {
        let first = word("first", dueIn: -1)
        let added = word("added", dueIn: -1)
        let later = word("later", dueIn: 3)
        let context = try insert(first, later)
        let session = makeSession()
        session.start(with: [first, later], practiceAll: false)
        session.play(known: true)
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

    @Test func unknownWordIsNotAskedAgainWhenFewWordsLeft() {
        let session = makeSession()
        let first = word("first", dueIn: -2)
        let second = word("second", dueIn: -1)
        session.start(with: [first, second], practiceAll: false)
        let missed = session.current

        session.reveal(answer: nil)
        #expect(session.phase == .revealed(.peeked))
        session.play(known: false)
        // Arada 2 kart kalmadığı için yeniden sorulmaz; kelime biten sayılır, sayaç erken dolmaz.
        #expect(session.finishedWordCount == 1)
        #expect(session.current !== missed)
        session.play(known: true)
        #expect(session.current == nil)
        #expect(session.finishedWordCount == 2)
        #expect(session.wordCount == 2)
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
            session.play(known: true)
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
        session.play(known: true, now: start.addingTimeInterval(8))

        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.mode == "quick")
        #expect(logs.first?.grade == AnswerGrade.good.rawValue)
        #expect(logs.first?.correct == true)
        #expect(logs.first?.responseTime == 6)
        #expect(logs.first?.word === target)
        #expect(target.lastReviewedAt == DayBoundary.start(of: start.addingTimeInterval(8)))
    }
}

struct StudyPlanTests {
    private func makeSession() -> StudySession {
        StudySession(seed: 3, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    private func studied(_ english: String, weak: Bool) -> Word {
        let word = Word(english: english, turkish: "anlam")
        word.reviewCount = 1
        word.stability = weak ? 1 : 30
        word.lastReviewedAt = Date.now.addingTimeInterval(weak ? -5 * 86_400 : 0)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(word.stability * 86_400)
        return word
    }

    private func drain(_ session: StudySession, known: Bool = true) -> [Word] {
        var asked: [Word] = []
        while let current = session.current, asked.count < 100 {
            asked.append(current)
            session.play(known: known)
        }
        return asked
    }

    @Test func dailyTakesAtMostTwentyAndFiveNew() {
        let words = (0..<18).map { studied("w\($0)", weak: true) }
            + (0..<10).map { Word(english: "n\($0)", turkish: "yeni") }
            + (0..<5).map { studied("s\($0)", weak: false) }
        #expect(StudySession.dailyCount(words) == (weak: 18, new: 2))
        let session = makeSession()
        session.start(with: words, plan: .daily)
        let asked = drain(session)
        #expect(asked.count == 20)
        #expect(asked.count { $0.english.hasPrefix("n") } <= 5)
        #expect(!asked.contains { $0.english.hasPrefix("s") })
    }

    @Test func quickTakesFiveFromWholeDeck() {
        let words = (0..<12).map { studied("s\($0)", weak: false) }
        let session = makeSession()
        session.start(with: words, plan: .quick)
        #expect(drain(session).count == 5)
    }

    @Test func roundEntriesKeepFirstAnswerAndDueBefore() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(for: SharedStore.schema, configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let first = studied("first", weak: true)
        let second = studied("second", weak: true)
        let fresh = Word(english: "fresh", turkish: "taze")
        for word in [first, second, fresh] { context.insert(word) }
        let dueBefore = Dictionary(uniqueKeysWithValues: [first, second].map { (ObjectIdentifier($0), $0.dueDate) })
        let session = makeSession()
        session.start(with: [first, second, fresh], plan: .daily)
        let opening = session.current!
        session.play(known: false)
        _ = drain(session)
        #expect(session.roundEntries.count == 3)
        let entry = session.roundEntries.first { $0.word === opening }!
        #expect(!entry.firstCorrect)
        // "Önce" cevaptan hemen önce okunur: yeni kelimede boş, ötekinde eski vade.
        #expect(entry.dueBefore == (opening === fresh ? nil : dueBefore[ObjectIdentifier(opening)]))
        #expect(!entry.lapsedBefore)
        #expect(session.roundEntries.first { $0.word === fresh }?.dueBefore == nil)
        // "Sonra" canlı okunur: yanlış bilinen kelime zayıf, vadesi yarın.
        #expect(opening.isLapsed)
        #expect(opening.dueDate == DayBoundary.nextStart(after: .now))
        #expect(session.roundEntries.filter(\.firstCorrect).count == 2)
    }
}

struct ReverseSessionTests {
    @Test func reverseChecksEnglishAndTypoIsHard() {
        let session = StudySession(seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let word = Word(english: "idempotent", turkish: "tekrarlanabilir")
        session.start(with: [word], plan: .reverse)
        session.reveal(answer: "idempotant")
        #expect(session.phase == .revealed(.almost))
        #expect(StudySession.Verdict.almost.gradeOptions.map(\.title) == ["Devam"])
        #expect(AnswerGrade.recall(verdict: .almost, known: true, responseTime: 2) == .hard)

        let other = StudySession(seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        other.start(with: [Word(english: "stale", turkish: "eskimiş")], plan: .reverse)
        other.reveal(answer: "eskimiş")
        #expect(other.phase == .revealed(.incorrect))
    }

    /// Defterde aynı anlamlı başka kelime yazılırsa "Doğru, ama aranan: X"; not zor.
    @Test func synonymFromTheNotebookIsRightButHard() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(for: SharedStore.schema, configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let stale = Word(english: "stale", turkish: "bayat, eskimiş")
        let outdated = Word(english: "outdated", turkish: "eskimiş")
        let quorum = Word(english: "quorum", turkish: "yeter sayı")
        for word in [stale, outdated, quorum] { context.insert(word) }
        let session = StudySession(seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        session.start(with: [stale, outdated, quorum], plan: .reverse)
        var checked = 0
        while let current = session.current {
            if current === quorum {
                session.reveal(answer: "stale")
                #expect(session.phase == .revealed(.incorrect))
                session.play(known: false)
                continue
            }
            let synonym = current === stale ? outdated : stale
            session.reveal(answer: synonym.english.uppercased())
            #expect(session.phase == .revealed(.synonymOf(synonym.english)))
            #expect(StudySession.Verdict.synonymOf(synonym.english).gradeOptions.map(\.title) == ["Devam"])
            session.play(known: true)
            #expect(current.logs?.last?.grade == AnswerGrade.hard.rawValue)
            #expect(current.logs?.last?.correct == true)
            checked += 1
        }
        #expect(checked == 2)
    }
}
