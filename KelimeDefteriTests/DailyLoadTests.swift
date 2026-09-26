import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Günlük yük: tekrarlarda tavan yok (güvenlik tavanı 100), yeni hakkı ayrı, tur başına 20 kelime
/// (docs/GELECEK.md "Şimdi: günlük yük ve yeni hakkı").
struct DailyLoadTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(seed: UInt64 = 1, newAllowance: Int = 10) -> StudySession {
        StudySession(seed: seed, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!, newAllowance: newAllowance)
    }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Vadesi gelmiş çalışılmış kelime: ilk cevabı `daysAgo` gün önce (bugün tanışılmış sayılmasın); cevap ne kadar
    /// eskiyse hafızası o kadar düşük (daha zayıf).
    private func due(_ english: String, daysAgo: Double = 40, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: "anlam", createdAt: now.addingTimeInterval(-(daysAgo + 1) * Memory.dayLength))
        context.insert(word)
        ReviewRecorder.record(
            word, grade: .good, mode: .dailyReview, responseTime: 3, now: now.addingTimeInterval(-daysAgo * Memory.dayLength)
        )
        return word
    }

    private func fresh(_ count: Int, in context: ModelContext) -> [Word] {
        (0..<count).map {
            let word = Word(english: "n\($0)", turkish: "yeni", createdAt: now.addingTimeInterval(Double($0 - count) * 60))
            context.insert(word)
            return word
        }
    }

    private func drain(_ session: StudySession) -> [Word] {
        var asked: [Word] = []
        while let current = session.current, asked.count < 300 {
            asked.append(current)
            session.play(known: true, now: now)
        }
        return asked
    }

    @Test func reviewsHaveNoCapBelowTheSafetyLimit() throws {
        let context = try makeContext()
        #expect(StudySession.dailyCount(weak: 34, new: 30, introducedToday: 0, newAllowance: 10) == (34, 10))
        let words = (0..<34).map { due("d\($0)", in: context) } + fresh(30, in: context)
        #expect(StudySession.dailyCount(words, now: now, newAllowance: 10) == (weak: 34, new: 10))
    }

    @Test func pastTheSafetyLimitNoNewAndWeakestFirst() throws {
        #expect(StudySession.dailyCount(weak: 100, new: 30, introducedToday: 0, newAllowance: 10) == (100, 10))
        #expect(StudySession.dailyCount(weak: 120, new: 30, introducedToday: 0, newAllowance: 10) == (100, 0))
        // 120 vadesi gelen: cevabı en eski olan en zayıf; tur en zayıf 20'yi alır.
        let context = try makeContext()
        let words = (0..<120).map { due("d\($0)", daysAgo: 200 - Double($0), in: context) } + fresh(5, in: context)
        #expect(StudySession.dailyCount(words, now: now, newAllowance: 10) == (weak: 100, new: 0))
        let round = session()
        round.start(with: words, plan: .daily, now: now)
        let asked = Set(drain(round).map(\.english))
        #expect(asked == Set((0..<20).map { "d\($0)" }))
    }

    @Test func allowanceOptionsAndIntroducedToday() {
        #expect(StudySession.dailyCount(weak: 3, new: 30, introducedToday: 0, newAllowance: 5) == (3, 5))
        #expect(StudySession.dailyCount(weak: 3, new: 30, introducedToday: 0, newAllowance: 15) == (3, 15))
        #expect(StudySession.dailyCount(weak: 3, new: 8, introducedToday: 0, newAllowance: 15) == (3, 8))
        // Bugün tanışılanlar haktan düşülür.
        #expect(StudySession.dailyCount(weak: 0, new: 30, introducedToday: 4, newAllowance: 10) == (0, 6))
        #expect(StudySession.dailyCount(weak: 0, new: 30, introducedToday: 12, newAllowance: 10) == (0, 0))
    }

    @Test func roundSplitIsProportional() {
        #expect(StudySession.dailyRoundSplit(reviews: 18, fresh: 10, room: 20) == (13, 7))
        #expect(StudySession.dailyRoundSplit(reviews: 5, fresh: 3, room: 20) == (5, 3))
        // Yeni varsa parçada en az 1.
        #expect(StudySession.dailyRoundSplit(reviews: 60, fresh: 1, room: 20) == (19, 1))
        #expect(StudySession.dailyRoundSplit(reviews: 0, fresh: 25, room: 20) == (0, 20))
        #expect(StudySession.dailyRoundSplit(reviews: 25, fresh: 0, room: 20) == (20, 0))
        #expect(StudySession.dailyRoundSplit(reviews: 25, fresh: 5, room: 0) == (0, 0))
    }

    /// 34 tekrar + 10 yeni: tur 20'şer kelimeyle ilerler, her turda yeni var; kart günün toplam kalanını söyler.
    @Test func roundsContinueUntilTheDayIsDone() throws {
        let context = try makeContext()
        let words = (0..<34).map { due("d\($0)", in: context) } + fresh(12, in: context)
        var seen: Set<ObjectIdentifier> = []
        var rounds: [Int] = []
        for seed in 1...5 as ClosedRange<UInt64> {
            let count = StudySession.dailyCount(words, now: now, newAllowance: 10)
            guard count.weak + count.new > 0 else { break }
            #expect(StudySession.againPlan(after: .daily, words: words, now: now, newAllowance: 10) == .daily)
            let round = session(seed: seed)
            round.start(with: words, plan: .daily, now: now)
            let asked = drain(round)
            let unique = Set(asked.map(ObjectIdentifier.init))
            #expect(unique.isDisjoint(with: seen))
            #expect(asked.contains { $0.english.hasPrefix("n") })
            seen.formUnion(unique)
            rounds.append(unique.count)
        }
        #expect(rounds == [20, 20, 4])
        #expect(seen.count == 44)
        #expect(StudySession.againPlan(after: .daily, words: words, now: now, newAllowance: 10) == .extraPractice)
        #expect(StudySession.againTitle(after: .daily, next: .daily) == "Devam Et")
        #expect(StudySession.againTitle(after: .daily, next: .extraPractice) == "Yine de Çalış")
    }

    /// Yanlış bilinen kelime o gün tekrar gelmez (yarına kalır); günün kalanı yine sonraki turda.
    @Test func wrongAnswerWaitsForTomorrow() throws {
        let context = try makeContext()
        let words = (0..<25).map { due("d\($0)", in: context) }
        let round = session()
        round.start(with: words, plan: .daily, now: now)
        var asked: [Word] = []
        while let current = round.current, asked.count < 100 {
            asked.append(current)
            round.play(known: asked.count > 1, now: now)
        }
        let missed = asked[0]
        #expect(!missed.isDue(at: now))
        #expect(StudySession.dailyCount(words, now: now, newAllowance: 10) == (weak: 5, new: 0))
    }

    @Test func invalidSettingFallsBackToTen() throws {
        let suite = "allowance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DailyNewAllowance.value(in: defaults) == 10)
        for invalid in [0, 7, 25, -5] {
            defaults.set(invalid, forKey: DailyNewAllowance.key)
            #expect(DailyNewAllowance.value(in: defaults) == 10)
        }
        defaults.set(15, forKey: DailyNewAllowance.key)
        #expect(DailyNewAllowance.value(in: defaults) == 15)
        #expect(DailyNewAllowance.options == [5, 10, 15, 20])
        #expect(DailyNewAllowance.validated(5) == 5)
    }

    /// Motor 2 göçünden cevap kaydı olmadan gelen (tabanı olan) eski kelime bugün cevaplanınca tanışma sayılmaz.
    @Test func migratedWordWithoutLogsIsNotAnIntroduction() throws {
        let context = try makeContext()
        let word = Word(english: "legacy", turkish: "eski")
        context.insert(word)
        word.reviewCount = 3
        word.correctCount = 3
        word.stability = 2
        word.lastReviewedAt = now.addingTimeInterval(-10 * Memory.dayLength)
        word.dueDate = now.addingTimeInterval(-8 * Memory.dayLength)
        #expect(word.logs?.isEmpty ?? true)
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        #expect(word.baseAt.map { $0 > .distantPast } == true)
        #expect(StudySession.introducedToday([word], now: now) == 0)
        #expect(StudySession.reviewedToday([word], now: now) == 1)
        // Hiç çalışılmamış kelime ise tanışma sayılır.
        let brand = fresh(1, in: context)[0]
        ReviewRecorder.record(brand, grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        #expect(StudySession.introducedToday([word, brand], now: now) == 1)
        #expect(StudySession.reviewedToday([word, brand], now: now) == 1)
    }

    /// Günün tekrar yükü 100'ü aşınca yeniler o gün geri gelmez (tur bitip bekleyenler azalsa da); ertesi gün gelir.
    @Test func heavyReviewDayStaysWithoutNewWords() throws {
        let context = try makeContext()
        let words = (0..<110).map { due("d\($0)", daysAgo: 150 - Double($0), in: context) } + fresh(5, in: context)
        #expect(StudySession.dailyCount(words, now: now, newAllowance: 10) == (weak: 100, new: 0))
        let round = session()
        round.start(with: words, plan: .daily, now: now)
        #expect(drain(round).count == 20)
        #expect(StudySession.reviewedToday(words, now: now) == 20)
        #expect(StudySession.dailyCount(words, now: now, newAllowance: 10) == (weak: 90, new: 0))
        // Ertesi gün kalan 90 hâlâ bekliyor ama yük 100'ün altında: yeniler geri gelir.
        let tomorrow = DayBoundary.nextStart(after: now).addingTimeInterval(3_600)
        let count = StudySession.dailyCount(words, now: tomorrow, newAllowance: 10)
        #expect(count.weak < 100)
        #expect(count.new == 5)
    }
}
