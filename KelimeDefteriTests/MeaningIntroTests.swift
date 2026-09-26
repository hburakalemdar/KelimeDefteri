import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Yeni anlam tanıtımı (docs/SPEC-ANLAM.md): anlam tabanı, bekleyen anlam, tanıtım cevabı ve Günlük Tekrar bütçesi.
struct MeaningIntroTests {
    private static let meanings = ["elma", "armut", "kiraz", "erik", "incir", "ayva", "nar", "dut", "üzüm", "kavun",
                                   "karpuz", "limon", "portakal", "mandalina", "muz", "çilek"]

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func makeSession(seed: UInt64 = 1, newAllowance: Int = 10) -> StudySession {
        StudySession(seed: seed, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!, newAllowance: newAllowance)
    }

    /// Güçlü, vadesi gelmemiş, anlam tabanı alınmış kelime.
    private func strongWord(_ english: String, _ turkish: String, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: turkish)
        word.createdAt = Date.now.addingTimeInterval(-40 * 86_400)
        context.insert(word)
        word.reviewCount = 1
        word.stability = 30
        word.lastReviewedAt = Date.now.addingTimeInterval(-3 * 86_400)
        word.dueDate = Date.now.addingTimeInterval(27 * 86_400)
        word.fillMeaningBaselineIfNeeded()
        return word
    }

    /// Çalışılmış, vadesi gelmiş, zayıf olmayan kelime.
    private func dueWord(_ english: String, _ turkish: String, in context: ModelContext) -> Word {
        let word = strongWord(english, turkish, in: context)
        word.stability = 1
        word.lastReviewedAt = Date.now.addingTimeInterval(-5 * 86_400)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(86_400)
        return word
    }

    private func newWords(_ count: Int, from start: Int, in context: ModelContext) -> [Word] {
        (start..<start + count).map { index in
            let word = Word(english: "n\(index)", turkish: Self.meanings[index])
            word.createdAt = Date.now.addingTimeInterval(Double(index - 100))
            context.insert(word)
            return word
        }
    }

    /// Anlam eklenir (formdaki gibi: önce taban).
    private func addMeaning(_ word: Word, _ meaning: String) {
        word.fillMeaningBaselineIfNeeded()
        word.turkish = WordMatcher.mergedMeanings(existing: word.turkish, adding: meaning)
    }

    // MARK: Taban

    @Test func baselineIsTakenOnFirstAnswerAndNeverChanges() throws {
        let context = try makeContext()
        let word = Word(english: "fresh", turkish: "taze")
        context.insert(word)
        word.fillMeaningBaselineIfNeeded()
        #expect(word.meaningBaseline == nil)  // yeni kelimeye dokunmaz
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3)
        #expect(word.meaningBaseline == "taze")
        addMeaning(word, "yeni")
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, meaning: "taze")
        #expect(word.meaningBaseline == "taze")
        #expect(word.pendingMeanings == ["yeni"])
    }

    @Test func maintenanceFillsOldStudiedWordsOnly() throws {
        let context = try makeContext()
        let old = strongWord("old", "eski", in: context)
        old.meaningBaseline = nil
        let fresh = Word(english: "fresh", turkish: "taze")
        context.insert(fresh)
        let summary = StoreMaintenance.run(in: context, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        #expect(summary.meaningBaselines == 1)
        #expect(old.meaningBaseline == "eski")
        #expect(fresh.meaningBaseline == nil)
    }

    @Test func absorbAndFormFillTheBaselineBeforeAdding() throws {
        let context = try makeContext()
        let absorbed = strongWord("stale", "bayat", in: context)
        absorbed.meaningBaseline = nil
        absorbed.absorb(turkish: "eskimiş", sentences: [])
        #expect(absorbed.meaningBaseline == "bayat")
        #expect(absorbed.pendingMeanings == ["eskimiş"])

        let edited = strongWord("edit", "düzenle", in: context)
        edited.meaningBaseline = nil
        addMeaning(edited, "değiştir")
        #expect(edited.pendingMeanings == ["değiştir"])
    }

    // MARK: Bekleyen anlam

    @Test func onlyACorrectAnswerWithThatMeaningClosesIt() throws {
        let context = try makeContext()
        let word = strongWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmak")
        ReviewRecorder.record(word, grade: .good, mode: .multipleChoice, responseTime: 2, meaning: "koşmak")
        #expect(word.pendingMeanings == ["çalıştırmak"])
        ReviewRecorder.record(word, grade: .again, mode: .multipleChoice, responseTime: 2, meaning: "çalıştırmak")
        #expect(word.pendingMeanings == ["çalıştırmak"])
        ReviewRecorder.record(word, grade: .good, mode: .multipleChoice, responseTime: 2, meaning: "Çalıştırmak")
        #expect(word.pendingMeanings.isEmpty)
    }

    @Test func deletedMeaningDropsAndCorrectedSpellingIsPendingAgain() throws {
        let context = try makeContext()
        let word = strongWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmk")
        #expect(word.pendingMeanings == ["çalıştırmk"])
        word.turkish = "koşmak"
        #expect(word.pendingMeanings.isEmpty)
        // Tabandaki anlamın yazımı düzeltilirse yeni yazılış bekleyen olur (fazla sormak yönünde).
        word.turkish = "koşmaak"
        #expect(word.pendingMeanings == ["koşmaak"])
        // Bekleyen anlam askedMeaning'in önüne geçer; üretim bilinen anlamla sorulur (hepsi bekleyense hepsinden).
        word.turkish = "koşmak, çalıştırmak"
        #expect(word.askedMeaning == "çalıştırmak")
        #expect(word.productionMeaning == "koşmak")
    }

    // MARK: Tanıtım cevabı

    @Test func introIsRecognitionOfAPendingMeaning() throws {
        let context = try makeContext()
        let word = strongWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmak")
        let known = ReviewRecorder.record(word, grade: .good, mode: .multipleChoice, responseTime: 2, meaning: "koşmak")
        #expect(known?.isIntro == false)
        let production = ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 2, meaning: "çalıştırmak")
        #expect(production?.isIntro == false)
        #expect(production?.meaning == "çalıştırmak")
        #expect(word.pendingMeanings.isEmpty)

        addMeaning(word, "işletmek")
        let intro = ReviewRecorder.record(word, grade: .again, mode: .fillBlank, responseTime: 2, meaning: "işletmek")
        #expect(intro?.isIntro == true)
    }

    @Test func wrongIntroLeavesAStrongWordsMemoryAlone() throws {
        let context = try makeContext()
        let word = strongWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmak")
        MemoryCache.refresh(word)
        let before = (word.stability, word.dueDate, word.lapsedAt, word.difficulty)
        let log = ReviewRecorder.record(word, grade: .again, mode: .multipleChoice, responseTime: 2, meaning: "çalıştırmak")
        #expect(log?.isIntro == true)
        #expect(word.stability == before.0 && word.dueDate == before.1 && word.lapsedAt == before.2 && word.difficulty == before.3)
        #expect(!word.isLapsed)
        // Kayıt sayısı tanıtımı sayar.
        #expect(word.answerCount == 1)
    }

    @Test func typedAnswerRecordsTheMeaningItMatched() throws {
        let context = try makeContext()
        let word = dueWord("run", "koşmak, çalıştırmak", in: context)
        let session = makeSession()
        session.start(with: [word], plan: .weak)
        let asked = session.questionMeaning
        let other = asked == "koşmak" ? "çalıştırmak" : "koşmak"
        session.reveal(answer: other)
        session.grade(known: true)
        #expect(word.logs?.first?.meaning == other)

        // Yanlışta ve "Doğru Say"da sorulan anlam yazılır.
        let second = makeSession()
        second.start(with: [word], plan: .quick)
        let secondAsked = second.questionMeaning
        #expect(!secondAsked.isEmpty)
        second.reveal(answer: "zzz")
        second.grade(known: true)
        #expect(word.logs?.max(by: { $0.date < $1.date })?.meaning == secondAsked)
    }

    // MARK: Günlük Tekrar

    /// Günlük Tekrar'ın bütün adımlarını doğru cevaplar; sorulan adımların türleri ve kelimeleri.
    private func drain(_ session: StudySession, correct: Bool = true, introCorrect: Bool? = nil) -> [String] {
        var asked: [String] = []
        var now = Date.now
        while asked.count < 100, let step = session.currentStep {
            now += 1
            switch step.kind {
            case .recall:
                asked.append("recall " + step.word.english)
                session.reveal(answer: correct ? step.word.turkish : "zzz", now: now)
                session.grade(known: correct, now: now)
            case .choice:
                asked.append((step.isIntro ? "intro " : "choice ") + step.word.english)
                session.answer(.recognition(correct: step.isIntro ? introCorrect ?? correct : correct), step: step.id, now: now)
                session.next(from: step.id, now: now)
            case .letters:
                asked.append("letters " + step.word.english)
                session.answer(correct ? .good : .again, step: step.id, now: now)
                session.next(from: step.id, now: now)
            }
        }
        return asked
    }

    /// Tanıtım şıkları için yeterli çeldirici: güçlü, bekleyen anlamı olmayan kelimeler.
    private func distractors(in context: ModelContext) -> [Word] {
        (0..<4).map { strongWord("d\($0)", Self.meanings[10 + $0], in: context) }
    }

    @Test func strongWordEntersOnlyForTheIntroAndLeaves() throws {
        let context = try makeContext()
        let word = strongWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmak")
        let deck = [word] + distractors(in: context)
        #expect(StudySession.dailyCount(deck) == (0, 1))
        #expect(StudySession.dailyMeaningCount(deck, count: StudySession.dailyCount(deck)) == 1)

        let session = makeSession()
        session.start(with: deck, plan: .daily)
        #expect(session.wordCount == 1)
        #expect(session.currentStep?.isIntro == true)
        if case .choice(let options, let index) = session.currentStep?.kind {
            #expect(options[index] == "çalıştırmak")
        }
        #expect(drain(session, correct: false) == ["intro run"])
        #expect(session.finishedWordCount == 1)
        #expect(session.roundEntries.count == 1)
        #expect(word.logs?.first?.isIntro == true)
        #expect(!word.isLapsed)
        // Yanlış tanıtım aynı gün tekrarlanmaz; bütçeden de düşer.
        #expect(!word.needsMeaningIntro())
        #expect(StudySession.dailyCount(deck) == (0, 0))
        #expect(StudySession.introducedToday(deck) == 1)
    }

    @Test func dueWordGetsTheIntroThenTyping() throws {
        let context = try makeContext()
        let word = dueWord("run", "koşmak", in: context)
        addMeaning(word, "çalıştırmak")
        let deck = [word] + distractors(in: context)
        // Vadesi gelmiş kelimenin tanıtımı zayıflar arasında: bütçeden yer almaz.
        #expect(StudySession.dailyCount(deck) == (1, 0))
        let session = makeSession()
        session.start(with: deck, plan: .daily)
        #expect(drain(session) == ["intro run", "recall run"])
        #expect(word.pendingMeanings.isEmpty)
        #expect(session.roundEntries.count == 1)
        // Yazarak cevap bilinen anlamla soruldu.
        let recall = word.logs?.max(by: { $0.date < $1.date })
        #expect(recall?.isIntro == false)
        #expect(StudySession.introducedToday(deck) == 1)
    }

    @Test func introNeedsFourMeaningsElseDueWordIsAskedNormally() throws {
        let context = try makeContext()
        let due = dueWord("run", "koşmak", in: context)
        addMeaning(due, "çalıştırmak")
        let strong = strongWord("walk", "yürümek", in: context)
        addMeaning(strong, "gezmek")
        let deck = [due, strong]
        // Şık kurulamaz: yalnız tanıtım kelimesi bütçeye girmez, vadesi gelen normal sorulur.
        #expect(StudySession.dailyCount(deck) == (1, 0))
        let session = makeSession()
        session.start(with: deck, plan: .daily)
        #expect(drain(session) == ["recall run"])
    }

    @Test func budgetTakesMeaningsFirstThenNewWords() throws {
        let context = try makeContext()
        let fresh = newWords(5, from: 0, in: context)
        let intros = (0..<2).map { index in
            let word = strongWord("s\(index)", Self.meanings[6 + index], in: context)
            addMeaning(word, "ek\(index)")
            return word
        }
        let deck = fresh + intros + distractors(in: context)
        // Yeni hakkı 5: yeni anlamlar da bu haktan yer alır.
        let count = StudySession.dailyCount(deck, newAllowance: 5)
        #expect(count == (0, 5))
        #expect(StudySession.dailyMeaningCount(deck, count: count) == 2)
        let taken = StudySession.dailyNewWords(deck, newAllowance: 5)
        #expect(taken.map(\.english) == ["s0", "s1", "n0", "n1", "n2"])
        #expect(StudySession.recentWaitingCount(deck, newAllowance: 5) == 2)
        #expect(StudySession.recentWords(deck, newAllowance: 5).map(\.english) == ["n4", "n3"])
        #expect(RoundText.daily(weak: 0, new: 5, meanings: 2, seconds: 60) == "3 yeni kelime · 2 yeni anlam · yaklaşık 1 dk")

        let session = makeSession(newAllowance: 5)
        session.start(with: deck, plan: .daily)
        #expect(session.wordCount == 5)
        let asked = drain(session)
        #expect(asked.filter { $0.hasPrefix("intro") }.count == 2)
        #expect(StudySession.introducedToday(deck) == 5)
        // Bütçe doldu: kalan yeniler Tanış'ta.
        #expect(StudySession.dailyCount(deck, newAllowance: 5).new == 0)
        #expect(StudySession.recentWaitingCount(deck, newAllowance: 5) == 2)
        // Hak 10 olsaydı kalan 2 yeni de bugün Günlük Tekrar'a girerdi.
        #expect(StudySession.dailyCount(deck, newAllowance: 10).new == 2)
    }

    /// Yanlış tanıtım yeniden sorulmaz: yalnız tanıtım için gelen kelime çıkar, vadesi gelmiş kelimeye yalnız takip adımı eklenir.
    /// Kuyrukta başka kelimeler var (yeniden ekleme yeri bulunur).
    @Test func wrongIntroIsNotRetried() throws {
        let context = try makeContext()
        let strong = strongWord("run", "koşmak", in: context)
        addMeaning(strong, "çalıştırmak")
        let due = dueWord("walk", "yürümek", in: context)
        addMeaning(due, "gezmek")
        let fresh = newWords(3, from: 0, in: context)
        let deck = [strong, due] + fresh + distractors(in: context)
        let session = makeSession()
        session.start(with: deck, plan: .daily)
        #expect(session.wordCount == 5)
        // Yalnız tanıtımlar yanlış; yanlış üretimler de yeniden sorulur ama sonunda biter.
        let asked = drain(session, introCorrect: false)
        #expect(asked.filter { $0.hasSuffix(" run") } == ["intro run"], "\(asked)")
        let walk = asked.filter { $0.hasSuffix(" walk") }
        #expect(walk.first == "intro walk")
        #expect(walk.filter { $0 == "intro walk" }.count == 1)
        #expect(Array(walk) == ["intro walk", "recall walk"])
        #expect(!strong.isLapsed)
        let allIntro = (strong.logs ?? []).allSatisfy { $0.isIntro }
        #expect(allIntro)
        #expect(session.finishedWordCount == session.wordCount)
    }

    @Test func glanceSummarySeparatesMeanings() {
        #expect(GlanceSummary(average: 0.9, weak: 0, new: 3, total: 9, meanings: 1).detailText == "2 yeni kelime · 1 yeni anlam")
        #expect(GlanceSummary(average: 0.9, weak: 0, new: 1, total: 9, meanings: 1).detailText == "1 yeni anlam")
    }

    /// Bildirim planında tanıtım kelimesi vadesi gelince zayıflar arasında bir kez sayılır.
    @Test func reminderCountsIntroWordOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        func date(day: Int, hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let due = date(day: 24, hour: 0)
        let plan = ReminderPlanner.plan(
            studiedDueDates: [due], newCount: 0, introDueDates: [due], introducedToday: 0, newAllowance: 10,
            hour: 20, minute: 0, now: date(day: 22, hour: 10), calendar: calendar
        )
        #expect(plan.prefix(3).map(\.dueCount) == [1, 1, 1])
    }

    // MARK: Birleştirme

    @Test func mergedCopiesUnionTheirBaselines() throws {
        let context = try makeContext()
        let first = strongWord("run", "koşmak", in: context)
        first.createdAt = Date.now.addingTimeInterval(-50 * 86_400)
        let second = strongWord("run", "çalıştırmak", in: context)
        second.meaningBaseline = nil
        let copy = Word(english: "run", turkish: "işletmek")
        context.insert(copy)
        try context.save()
        StoreMaintenance.run(in: context, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        #expect(first.meaningBaseline == "koşmak, çalıştırmak")
        #expect(first.turkish == "koşmak, çalıştırmak, işletmek")
        #expect(first.pendingMeanings == ["işletmek"])
    }
}
