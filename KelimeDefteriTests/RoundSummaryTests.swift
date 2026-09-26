import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// SPEC-MOTOR2 §7.2 C: tur özeti, "aynı deste" notu, "Bir Tur Daha"nın akışı, zayıf kelime etiketi,
/// Mac'te turun kendiliğinden yeniden başlamaması.
struct RoundSummaryTests {
    /// Yerel saatle öğlen; gün sınırı (04:00) testlerini saat diliminden bağımsız tutar.
    private let now: Date = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000)
    )!

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func words(_ count: Int, in context: ModelContext) -> [Word] {
        (0..<count).map { index in
            let word = Word(english: "w\(index)", turkish: "anlam \(index)")
            word.createdAt = now.addingTimeInterval(-Double(100 - index))
            context.insert(word)
            return word
        }
    }

    // MARK: - İkon turdaki ilk cevaba bakar

    @Test func summaryIconFollowsFirstAnswerInRound() throws {
        let context = try makeContext()
        let deck = words(4, in: context)
        let round = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        round.start(with: deck, count: 4, now: now)
        let word = round.current!
        round.record(word, grade: .recognition(correct: false), now: now.addingTimeInterval(10))
        round.record(word, grade: .recognition(correct: true), now: now.addingTimeInterval(20))
        let entry = RoundSummaryView.Entry(round.entries[0])
        #expect(!entry.correct)
        #expect(entry.dueBefore == nil)
        // Yanlıştan sonra "önce → sonra": "Yeni → Yarın", zayıf (turuncu); kırmızı "Şimdi" yok.
        #expect(word.isLapsed)
        #expect(Leitner.dueDescription(for: word.dueDate, now: now) == "Yarın")
    }

    // MARK: - "Aynı deste" notu

    @Test func sameDayNoteOnlyForEarlierRoundToday() throws {
        let context = try makeContext()
        let deck = words(4, in: context)
        let first = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        first.start(with: deck, count: 4, now: now)
        let word = first.current!
        first.record(word, grade: .recognition(correct: true), now: now.addingTimeInterval(5))
        // Turun kendi cevapları (aynı kelime ikinci kez dahil) notu açmaz.
        first.record(word, grade: .recognition(correct: true), now: now.addingTimeInterval(9))
        #expect(!RoundSummaryView.showsSameDayNote(words: [word], roundStartedAt: first.beganAt, now: now.addingTimeInterval(10)))

        // Bugün daha sonra başlayan başka turda aynı kelime: not çıkar.
        let second = GameRound(mode: .multipleChoice, seed: 2, defaults: defaults())
        second.start(with: deck, count: 4, now: now.addingTimeInterval(3_600))
        #expect(RoundSummaryView.showsSameDayNote(words: [word], roundStartedAt: second.beganAt, now: now.addingTimeInterval(3_700)))
        // Bugün görülmemiş kelimeler: not yok.
        let others = deck.filter { $0 !== word }
        #expect(!RoundSummaryView.showsSameDayNote(words: others, roundStartedAt: second.beganAt, now: now.addingTimeInterval(3_700)))
        // Ertesi gün: dünkü cevap sayılmaz.
        let tomorrow = now.addingTimeInterval(Memory.dayLength)
        #expect(!RoundSummaryView.showsSameDayNote(words: [word], roundStartedAt: tomorrow, now: tomorrow.addingTimeInterval(60)))
    }

    /// Notun ölçtüğü başlangıç duraklatmayla kaymaz (süre için kullanılan `startedAt` kayar).
    @Test func roundStartDoesNotShiftWithPause() throws {
        let context = try makeContext()
        let deck = words(3, in: context)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: deck, plan: .quick, now: now)
        session.pauseClock(now: now.addingTimeInterval(10))
        session.resumeClock(now: now.addingTimeInterval(1_000))
        #expect(session.startedAt == now.addingTimeInterval(990))
        #expect(session.roundBeganAt == now)

        let round = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        round.start(with: deck, count: 3, now: now)
        round.pauseClock(now: now.addingTimeInterval(10))
        round.resumeClock(now: now.addingTimeInterval(1_000))
        #expect(round.startedAt == now.addingTimeInterval(990))
        #expect(round.beganAt == now)
    }

    // MARK: - "Bir Tur Daha" akışı ve düğme metni

    @Test func againPlanNamesTheNextFlow() throws {
        let context = try makeContext()
        // 12 yeni kelime, hak 10: Günlük Tekrar 10'unu, Yeni Eklenenler kalan 2'yi alır.
        let deck = words(12, in: context)
        #expect(StudySession.againPlan(after: .recent, words: deck, now: now, newAllowance: 10) == .recent)
        #expect(StudySession.againPlan(after: .daily, words: deck, now: now, newAllowance: 10) == .daily)
        // Günlük Tekrar'da günün kalanı varsa düğme "Devam Et".
        #expect(StudySession.againTitle(after: .daily, next: .daily) == "Devam Et")
        #expect(StudySession.againPlan(after: .quick, words: deck, now: now) == .quick)
        #expect(StudySession.againPlan(after: .reverse, words: deck, now: now) == .reverse)

        // Hepsi bugün tanıtıldı (doğru bilindi): bekleyen yeni kelime ve vadesi gelen yok.
        for word in deck {
            ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        }
        #expect(StudySession.againPlan(after: .recent, words: deck, now: now, newAllowance: 10) == .extraPractice)
        #expect(StudySession.againPlan(after: .daily, words: deck, now: now, newAllowance: 10) == .extraPractice)
        #expect(StudySession.againTitle(after: .daily, next: .extraPractice) == "Yine de Çalış")
        #expect(StudySession.againTitle(after: .recent, next: .daily) == "Günlük Tekrar'a Geç")
        #expect(StudySession.againTitle(after: .extraPractice, next: .extraPractice) == "Bir Tur Daha")
    }

    // MARK: - Mac: tur bitince kendiliğinden yeniden başlamaz

    @Test func finishedDailyRoundStaysFinished() throws {
        let context = try makeContext()
        let deck = words(3, in: context)
        let session = StudySession(seed: 1, defaults: defaults())
        #expect(!session.hasRound)
        session.start(with: deck, plan: .daily, now: now)
        #expect(session.hasRound)
        var time = now
        while session.current != nil {
            time += 5
            session.reveal(answer: session.current!.turkish, now: time)
            session.play(known: true, now: time)
        }
        // Özet ekranı: tur bitti ama başlamıştı; yeni gelen kelime ya da eşitleme turu yeniden açmaz.
        #expect(session.hasRound)
        context.insert(Word(english: "fresh", turkish: "taze"))
        session.sync(with: deck + [Word(english: "other", turkish: "başka")], now: time + 60)
        #expect(session.current == nil)
        #expect(session.roundEntries.count == 3)

        // Soracak kelime yoksa tur "başlamamış" sayılır (Mac'te "Hepsi Güçlü" ekranı, özet değil).
        let empty = StudySession(seed: 1, defaults: defaults())
        empty.start(with: [], plan: .daily, now: now)
        #expect(!empty.hasRound)
    }

    // MARK: - Listede/ayrıntıda "Tekrar edilecek"

    @Test func lapsedWordShowsRepeatLabelWithWhen() throws {
        let context = try makeContext()
        let word = words(1, in: context)[0]
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        #expect(word.isLapsed)
        #expect(!word.isDue(at: now))
        #expect(LapsedLabel.text(for: word, now: now) == "Tekrar edilecek · Yarın")
    }

    /// Vadesi gelmemiş zayıf kelime "N zayıf"a girmez ama "güçlü" de sayılmaz; metinler "hepsi güçlü" demez.
    @Test func repeatingWordsAreNotCalledStrong() throws {
        let context = try makeContext()
        let deck = words(3, in: context)
        ReviewRecorder.record(deck[0], grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        ReviewRecorder.record(deck[1], grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        ReviewRecorder.record(deck[2], grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        #expect(DeckSummary.group(of: deck[0], now: now) == .repeating)
        #expect(DeckSummary.text(for: deck, now: now) == "3 kelime · 1 tekrar edilecek · 2 güçlü")
        #expect(StudySession.dailyCount(deck, now: now).weak == 0)
        #expect(DeckSummary.allDoneText(for: deck, now: now) == "Bugünlük tekrar bitti · 1 kelime tekrar edilecek · sıradaki tekrar yarın")
        #expect(GlanceQuiz.summary(deck, now: now).detailText == "1 kelime tekrar edilecek")
        // Ertesi gün vadesi gelir: artık "zayıf" (Günlük Tekrar sorar).
        let tomorrow = now.addingTimeInterval(Memory.dayLength)
        #expect(DeckSummary.group(of: deck[0], now: tomorrow) == .weak)
    }
}
