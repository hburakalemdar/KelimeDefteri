import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Günlük Tekrar karışımının saf kuralları (`DailyMix`).
struct DailyMixTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 21 Eylül 2026 + gün, verilen saat ve dakika (İstanbul).
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    @Test func warmupOnlyForNewOrWeakWithEnoughMeanings() {
        #expect(DailyMix.needsWarmup(isNew: true, isLapsed: false, pendingProduction: false, deckMeanings: 4))
        #expect(DailyMix.needsWarmup(isNew: false, isLapsed: true, pendingProduction: false, deckMeanings: 9))
        #expect(!DailyMix.needsWarmup(isNew: false, isLapsed: false, pendingProduction: false, deckMeanings: 9))
        #expect(!DailyMix.needsWarmup(isNew: true, isLapsed: false, pendingProduction: false, deckMeanings: 3))
        #expect(!DailyMix.needsWarmup(isNew: false, isLapsed: true, pendingProduction: true, deckMeanings: 9))
    }

    @Test func lettersOnlyForShortWords() {
        #expect(DailyMix.productionUsesLetters(english: "stale"))
        #expect(DailyMix.productionUsesLetters(english: "race condition"))
        #expect(!DailyMix.productionUsesLetters(english: "internationalization"))
    }

    @Test func warmupsStayOutOfTheLastTwoPlaces() {
        let order = DailyMix.order(warmups: [false, false, false, true, true])
        #expect(order.count == 5)
        #expect(Set(order) == Set(0..<5))
        let warmups = [false, false, false, true, true]
        #expect(!warmups[order[3]] && !warmups[order[4]])
        // İlk sıra değişmez; hepsi ısınmalıysa yapılacak bir şey yok.
        #expect(DailyMix.order(warmups: [true, false, true])[0] == 0)
        #expect(DailyMix.order(warmups: [true, true, true]) == [0, 1, 2])
        #expect(DailyMix.order(warmups: [true]) == [0])
        #expect(DailyMix.order(warmups: []) == [])
    }

    @Test func pendingProductionFollowsTheFourOClockBoundary() {
        let choice = GameMode.multipleChoice.rawValue
        // Yeni kelime 04:10'da ısındı: ertesi sabah 03:50'ye kadar aynı gün, üretimi bekliyor.
        let warm = [(date: at(0, 4, 10), mode: choice)]
        #expect(DailyMix.isPendingProduction(logs: warm, isLapsed: false, anchoredToday: true, now: at(1, 3, 50), calendar: calendar))
        #expect(!DailyMix.isPendingProduction(logs: warm, isLapsed: false, anchoredToday: false, now: at(1, 4, 10), calendar: calendar))
        // 03:30'daki ısınma önceki güne ait; 04:30'da yeni gün başladı.
        let late = [(date: at(1, 3, 30), mode: choice)]
        #expect(!DailyMix.isPendingProduction(logs: late, isLapsed: false, anchoredToday: false, now: at(1, 4, 30), calendar: calendar))
        // Üretim cevabı varsa bekleyen yok.
        let done = warm + [(date: at(0, 4, 20), mode: GameMode.letters.rawValue)]
        #expect(!DailyMix.isPendingProduction(logs: done, isLapsed: false, anchoredToday: true, now: at(0, 9), calendar: calendar))
        // Eskiden çalışılmış, zayıf olmayan kelime Çoktan Seçmeli oyununda sorulduysa bekleyen sayılmaz.
        let old = [(date: at(-5, 9), mode: GameMode.dailyReview.rawValue), (date: at(0, 9), mode: choice)]
        #expect(!DailyMix.isPendingProduction(logs: old, isLapsed: false, anchoredToday: false, now: at(0, 10), calendar: calendar))
        #expect(DailyMix.isPendingProduction(logs: old, isLapsed: true, anchoredToday: false, now: at(0, 10), calendar: calendar))
        // Göç etmiş (tabanı olan, kaydı olmayan) eski kelimenin bugünkü ilk kaydı onu yeni yapmaz: çıpası eski.
        let migrated = [(date: at(0, 9), mode: choice)]
        #expect(!DailyMix.isPendingProduction(logs: migrated, isLapsed: false, anchoredToday: false, now: at(0, 10), calendar: calendar))
    }

    @Test func estimateCountsQuestionTypes() {
        #expect(DailyMix.seconds(warmup: true, pendingProduction: false, letters: true) == 26)
        #expect(DailyMix.seconds(warmup: true, pendingProduction: false, letters: false) == 33)
        #expect(DailyMix.seconds(warmup: false, pendingProduction: true, letters: true) == 18)
        #expect(DailyMix.seconds(warmup: false, pendingProduction: false, letters: true) == 25)
        #expect(RoundText.estimate(seconds: 508) == "yaklaşık 9 dk")
        #expect(RoundText.daily(weak: 3, new: 2, seconds: 100) == "3 kelime zayıfladı · 2 yeni · yaklaşık 2 dk")
        #expect(RoundText.daily(weak: 3, new: 2, pending: 1, seconds: 100)
                == "2 kelime zayıfladı · 1 kelime tekrar bekliyor · 2 yeni · yaklaşık 2 dk")
        #expect(RoundText.daily(weak: 1, new: 0, pending: 1, seconds: 18) == "1 kelime tekrar bekliyor · yaklaşık 1 dk")
    }

    // MARK: Motorla uyum (SPEC-MOTOR2 §2.4)

    private func replay(_ answers: [Memory.Answer]) -> Memory.State {
        Memory.replay(base: .empty, answers: answers, now: answers.map(\.date).max()!, calendar: calendar)
    }

    @Test func warmupThenLettersGradesFromLetters() {
        let both = replay([
            Memory.Answer(date: at(0, 9), mode: .multipleChoice, correct: true, grade: .good),
            Memory.Answer(date: at(0, 9, 2), mode: .letters, correct: true, grade: .good),
        ])
        let lettersOnly = replay([Memory.Answer(date: at(0, 9, 2), mode: .letters, correct: true, grade: .good)])
        #expect(both.stability == lettersOnly.stability)
        #expect(both.lapsedAt == nil)
    }

    @Test func wrongWarmupThenLettersFiveMinutesLaterIsAgain() {
        let state = replay([
            Memory.Answer(date: at(0, 9), mode: .multipleChoice, correct: false, grade: .again),
            Memory.Answer(date: at(0, 9, 5), mode: .letters, correct: true, grade: .good),
        ])
        #expect(state.lapsedAt != nil)
    }
}

/// Günlük Tekrar turunun adımları (`StudySession` karışık turu).
struct DailyMixSessionTests {
    private static let meanings = ["bayat", "yeter sayı", "defter", "kiracı", "parça", "mandal", "kuyruk", "önbellek",
                                   "şema", "yama", "düğüm", "akış", "kilit", "bağ", "yük", "iz", "kök", "dal", "ağ",
                                   "uç", "kapı", "yol", "su", "taş", "gök", "ay", "gün", "yıl", "el", "göz"]

    private func makeSession(seed: UInt64 = 1) -> StudySession {
        StudySession(seed: seed, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Farklı anlamlı yeni kelimeler: "wa", "wb", … (kısa, Harfleri Diz'e sığar).
    private func newWords(_ count: Int, from start: Int = 0, in context: ModelContext) -> [Word] {
        (start..<start + count).map { index in
            let word = Word(english: "w" + String(UnicodeScalar(97 + index)!), turkish: Self.meanings[index])
            word.createdAt = Date.now.addingTimeInterval(Double(index - 100))
            context.insert(word)
            return word
        }
    }

    /// Çalışılmış, vadesi gelmiş, zayıf olmayan kelime.
    private func dueWord(_ english: String, meaning: String, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: meaning)
        context.insert(word)
        word.reviewCount = 1
        word.stability = 1
        word.lastReviewedAt = Date.now.addingTimeInterval(-5 * 86_400)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(86_400)
        return word
    }

    private enum Asked: Equatable {
        case choice(String), letters(String), recall(String)
        var word: String {
            switch self { case .choice(let w), .letters(let w), .recall(let w): w }
        }
    }

    /// Sıradaki adımı cevaplar; `correct` adımın türüne ve kelimesine göre karar verir.
    @discardableResult
    private func answer(_ session: StudySession, now: Date = .now, correct: (Asked) -> Bool = { _ in true }) -> Asked? {
        guard let step = session.currentStep else { return nil }
        let asked: Asked
        switch step.kind {
        case .recall:
            asked = .recall(step.word.english)
            let right = correct(asked)
            session.reveal(answer: right ? step.word.turkish : "zzz", now: now)
            session.grade(known: right, now: now)
        case .choice:
            asked = .choice(step.word.english)
            session.answer(.recognition(correct: correct(asked)), step: step.id, now: now)
            session.next(from: step.id, now: now)
        case .letters:
            asked = .letters(step.word.english)
            session.answer(correct(asked) ? .good : .again, step: step.id, now: now)
            session.next(from: step.id, now: now)
        }
        return asked
    }

    private func drain(_ session: StudySession, now: Date = .now, correct: (Asked) -> Bool = { _ in true }) -> [Asked] {
        var asked: [Asked] = []
        // Her cevap bir saniye sonra: kayıtların sırası tarihten okunabilsin.
        while asked.count < 200, let step = answer(session, now: now.addingTimeInterval(Double(asked.count)), correct: correct) {
            asked.append(step)
        }
        return asked
    }

    private func modes(_ word: Word) -> [String] {
        (word.logs ?? []).sorted { $0.date < $1.date }.map(\.mode)
    }

    @Test func newWordsWarmUpThenFinishWithLetters() throws {
        let context = try makeContext()
        let fresh = newWords(5, in: context)
        let session = makeSession()
        session.start(with: fresh, plan: .daily)
        #expect(session.wordCount == 5)
        let asked = drain(session)
        #expect(asked.count == 10)
        for word in fresh {
            #expect(modes(word) == ["choice", "letters"])
        }
        #expect(session.finishedWordCount == 5)
        #expect(session.roundEntries.count == 5)
    }

    @Test func productionComesAfterTwoOtherWords() throws {
        for seed in 0..<20 as Range<UInt64> {
            let context = try makeContext()
            let words = newWords(2, in: context)
                + (0..<6).map { dueWord("d\($0)", meaning: Self.meanings[10 + $0], in: context) }
            let session = makeSession(seed: seed)
            session.start(with: words, plan: .daily)
            let asked = drain(session)
            for word in words.prefix(2) {
                let warm = try #require(asked.firstIndex(of: .choice(word.english)))
                let production = try #require(asked.firstIndex(of: .letters(word.english)))
                let between = Set(asked[(warm + 1)..<production].map(\.word))
                #expect(between.count >= 2 && !between.contains(word.english))
            }
            // Vadesi gelen zayıf olmayan kelimeler bugünkü gibi yalnız yazarak.
            for word in words.dropFirst(2) { #expect(modes(word) == ["daily"]) }
        }
    }

    @Test func everyWordEndsWithProductionEvenWhenWrong() throws {
        let context = try makeContext()
        let words = newWords(4, in: context) + [dueWord("d0", meaning: "yol", in: context)]
        let session = makeSession()
        session.start(with: words, plan: .daily)
        // Isınmalar ve ilk Harfleri Diz yanlış; yeniden sorulan doğru.
        var wrongLetters: Set<String> = []
        _ = drain(session) { asked in
            switch asked {
            case .choice: false
            case .letters(let word): !wrongLetters.insert(word).inserted
            case .recall: true
            }
        }
        for word in words {
            let last = try #require((word.logs ?? []).max { $0.date < $1.date })
            #expect(GameMode(rawValue: last.mode)?.isProduction == true)
        }
        let entries = session.roundEntries
        #expect(entries.count == 5)
        // Isınma yanlışsa üretim doğru olsa da özet "doğru" saymaz; yeni kelimenin önceki durumu "Yeni".
        for entry in entries where entry.word.english.hasPrefix("w") {
            #expect(!entry.firstCorrect)
            #expect(entry.dueBefore == nil)
        }
        #expect(session.finishedWordCount == session.wordCount)
    }

    @Test func dailyStillTakesTwentyAndFiveNew() throws {
        let context = try makeContext()
        let weak = (0..<18).map { dueWord("d\($0)", meaning: Self.meanings[$0], in: context) }
        let fresh = (0..<10).map { index in
            let word = Word(english: "n\(index)", turkish: "yeni\(index)")
            context.insert(word)
            return word
        }
        let session = makeSession()
        session.start(with: weak + fresh, plan: .daily)
        let asked = drain(session)
        let words = Set(asked.map(\.word))
        #expect(words.count == 20)
        #expect(words.count { $0.hasPrefix("n") } == 2)
        #expect(session.wordCount == 20)
        #expect(session.finishedWordCount == 20)
        #expect(asked.count == 22)
    }

    @Test func longPhraseAndSmallDeckFallBackToTyping() throws {
        let context = try makeContext()
        let long = Word(english: "internationalization", turkish: "uluslararasılaştırma")
        context.insert(long)
        let others = newWords(4, in: context)
        let session = makeSession()
        session.start(with: [long] + others, plan: .daily)
        _ = drain(session)
        #expect(modes(long) == ["choice", "daily"])

        // 3 farklı anlamlı defterde ısınma yok: bugünkü gibi yazarak.
        let small = try makeContext()
        let few = newWords(3, in: small)
        let other = makeSession()
        other.start(with: few, plan: .daily)
        #expect(drain(other).allSatisfy { if case .recall = $0 { true } else { false } })
        for word in few { #expect(modes(word) == ["daily"]) }
    }

    @Test func quickAndReverseStayTyping() throws {
        let context = try makeContext()
        let words = newWords(6, in: context)
        for plan in [StudySession.Plan.quick, .reverse] {
            let session = makeSession()
            session.start(with: words, plan: plan)
            #expect(session.currentStep?.isRecall == true)
            #expect(!session.usesMix)
        }
    }

    @Test func recentUsesTheSameMix() throws {
        let context = try makeContext()
        let words = newWords(8, in: context)
        let session = makeSession()
        session.start(with: words, plan: .recent)
        #expect(session.wordCount == 3)
        let asked = drain(session)
        #expect(asked.count { if case .choice = $0 { true } else { false } } == 3)
        #expect(asked.count { if case .letters = $0 { true } else { false } } == 3)
    }

    @Test func deletedWordLeavesAllStepsAndCounter() throws {
        let context = try makeContext()
        let words = newWords(5, in: context)
        try context.save()
        let session = makeSession()
        session.start(with: words, plan: .daily)
        let first = try #require(session.current)
        let english = first.english
        answer(session)
        #expect(session.wordCount == 5)
        context.delete(first)
        try context.save()
        session.sync(with: words.filter { $0 !== first })
        #expect(session.wordCount == 4)
        let asked = drain(session)
        #expect(!asked.contains { $0.word == english })
        #expect(session.finishedWordCount == 4)
    }

    @Test func lateCallbacksCannotAnswerOrAdvanceTwice() throws {
        let context = try makeContext()
        let words = newWords(5, in: context)
        let session = makeSession()
        session.start(with: words, plan: .daily)
        let step = try #require(session.currentStep)
        #expect(step.isWarmup)
        // Cevap vermeden ilerlenemez.
        session.next(from: step.id)
        #expect(session.currentStep?.id == step.id)
        session.answer(.good, step: step.id)
        session.answer(.again, step: step.id)
        #expect(step.word.logs?.count == 1)
        // Pencere kapanıp açıldı: cevaplanmış adım atlanır; gecikmiş 0,8 sn geçişi ise bir şey yapmaz.
        session.skipAnsweredStep()
        let second = try #require(session.currentStep)
        #expect(second.id != step.id)
        session.next(from: step.id)
        session.answer(.good, step: step.id)
        #expect(session.currentStep?.id == second.id)
        #expect(step.word.logs?.count == 1)
        #expect(second.word.logs?.count ?? 0 == 0)
    }

    /// Günün ortası (12:00): 04:00 sınırına yakın saatte koşunca bozulmasın.
    private var noon: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)! }

    @Test func abandonedWarmupIsProducedInTheNextRound() throws {
        let context = try makeContext()
        let words = newWords(5, in: context)
        let start = noon
        let session = makeSession()
        session.start(with: words, plan: .daily, now: start)
        let warmed = try #require(session.current)
        answer(session, now: start)
        // Tur burada bırakıldı. Kelime artık yeni değil ve vadesi gelmedi ama üretimi bekliyor.
        #expect(!warmed.isNew)
        #expect(!warmed.isDue(at: start))
        #expect(warmed.isPendingProduction(now: start.addingTimeInterval(60)))
        let later = start.addingTimeInterval(60)
        #expect(StudySession.dailyCount(words, now: later) == (weak: 1, new: 4))

        let next = makeSession(seed: 7)
        next.start(with: words, plan: .daily, now: later)
        let asked = drain(next, now: later)
        #expect(asked.filter { $0.word == warmed.english } == [.letters(warmed.english)])
        #expect(modes(warmed) == ["choice", "letters"])
        #expect(!warmed.isPendingProduction(now: later))
    }

    /// Güçlü, vadesi gelmemiş kelimeler: çeldirici olurlar ama tura girmezler.
    private func strongWords(_ count: Int, from start: Int, in context: ModelContext) -> [Word] {
        (start..<start + count).map { index in
            let word = Word(english: "s\(index)", turkish: Self.meanings[index])
            context.insert(word)
            word.reviewCount = 1
            word.stability = 30
            word.lastReviewedAt = Date.now.addingTimeInterval(-3 * 86_400)
            word.dueDate = Date.now.addingTimeInterval(27 * 86_400)
            return word
        }
    }

    @Test func singleWordRoundProducesRightAfterWarmup() throws {
        let context = try makeContext()
        let fresh = newWords(1, in: context)
        let session = makeSession()
        session.start(with: fresh + strongWords(3, from: 10, in: context), plan: .daily)
        #expect(drain(session) == [.choice("wa"), .letters("wa")])
        #expect(session.finishedWordCount == 1 && session.wordCount == 1)
    }

    @Test func longPhraseWarmupThenTypingWithCommittedAnswerUndone() throws {
        let context = try makeContext()
        let long = Word(english: "internationalization", turkish: "uluslararasılaştırma")
        context.insert(long)
        let session = makeSession()
        session.start(with: [long] + strongWords(3, from: 10, in: context), plan: .daily)
        let warmup = try #require(session.currentStep)
        session.answer(.good, step: warmup.id)
        session.next(from: warmup.id)
        #expect(session.currentStep?.isRecall == true)
        session.reveal(answer: long.turkish)
        // Arka plana geçerken doğru cevap kaydedilir; kullanıcı dönüp "Bilemedim" derse kayıt değişir.
        session.commitPendingAnswer()
        #expect(session.roundEntries.first?.firstCorrect == true)
        session.grade(known: false)
        #expect(modes(long) == ["choice", "daily"])
        #expect(long.logs?.first { $0.mode == "daily" }?.correct == false)
        #expect(session.roundEntries.count == 1)
        #expect(session.roundEntries.first?.firstCorrect == false)
        #expect(session.roundEntries.first?.dueBefore == nil)
    }

    @Test func pendingBeyondTwentyStaysWithinTheLimit() throws {
        let context = try makeContext()
        let words = newWords(22, in: context)
        let at = noon
        // Çoktan Seçmeli oyunu (ya da yarıda kalan tur) 22 yeni kelimeyi bugün tanıttı.
        for word in words {
            ReviewRecorder.record(word, grade: .good, mode: .multipleChoice, responseTime: 2, now: at)
        }
        let later = at.addingTimeInterval(600)
        #expect(words.allSatisfy { $0.isPendingProduction(now: later) })
        #expect(StudySession.dailyCount(words, now: later) == (weak: 20, new: 0))
        #expect(StudySession.pendingProductionCount(words, now: later) == 22)
        let session = makeSession()
        session.start(with: words, plan: .daily, now: later)
        let asked = drain(session, now: later)
        #expect(asked.count == 20)
        #expect(asked.allSatisfy { if case .letters = $0 { true } else { false } })
    }

    /// Kayıtları olan eski güçlü kelime Çoktan Seçmeli oyununda bugün cevaplanınca bekleyen sayılmaz.
    @Test func oldStrongWordWithLogsIsNotPending() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "bayat")
        context.insert(word)
        let at = noon
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: at.addingTimeInterval(-20 * 86_400))
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: at.addingTimeInterval(-10 * 86_400))
        ReviewRecorder.record(word, grade: .good, mode: .multipleChoice, responseTime: 2, now: at)
        #expect(!word.isLapsed)
        #expect(!word.isPendingProduction(now: at.addingTimeInterval(60)))
    }

    /// Mac: seçmeli soru yanlış cevaplanıp pencere kapandı, 2 saat sonra açılınca soru atlandı; kapalı kalınan
    /// süre tur süresine sayılmaz.
    @Test func closedWindowTimeIsNotCountedWhenAnsweredStepIsSkipped() throws {
        let context = try makeContext()
        let words = newWords(5, in: context)
        let start = noon
        let session = makeSession()
        session.start(with: words, plan: .daily, now: start)
        let step = try #require(session.currentStep)
        session.answer(.again, step: step.id, now: start.addingTimeInterval(5))
        session.pauseClock(now: start.addingTimeInterval(6))
        let reopened = start.addingTimeInterval(6 + 7200)
        session.skipAnsweredStep(now: reopened)
        session.resumeClock(now: reopened)
        _ = drain(session, now: reopened.addingTimeInterval(1))
        let duration = session.finishedAt.timeIntervalSince(session.startedAt)
        #expect(duration > 0 && duration < 60)
    }

    @Test func strongWordFromChoiceGameIsNotPending() throws {
        let context = try makeContext()
        let strong = strongWords(1, from: 10, in: context)[0]
        let at = noon
        ReviewRecorder.record(strong, grade: .good, mode: .multipleChoice, responseTime: 2, now: at)
        #expect(!strong.isPendingProduction(now: at.addingTimeInterval(60)))
        // Widget'ta yanlış bilinen (zayıflayan) kelime ise üretim için Günlük Tekrar'a gelir.
        ReviewRecorder.record(strong, grade: .again, mode: .multipleChoice, responseTime: 2, now: at.addingTimeInterval(30))
        #expect(strong.isLapsed)
        #expect(strong.isPendingProduction(now: at.addingTimeInterval(60)))
    }
}

extension StudySession {
    /// Testlerde sıradaki adımı türüne bakmadan cevaplar: yazarak cevapta `grade`, seçmeli/harf sorusunda
    /// bilindiyse doğru, bilinmediyse yanlış cevap ve sonrakine geçiş.
    func play(known: Bool, now: Date = .now) {
        guard let step = currentStep else { return }
        switch step.kind {
        case .recall:
            grade(known: known, now: now)
        case .choice:
            answer(.recognition(correct: known), step: step.id, now: now)
            next(from: step.id, now: now)
        case .letters:
            answer(known ? .good : .again, step: step.id, now: now)
            next(from: step.id, now: now)
        }
    }
}
