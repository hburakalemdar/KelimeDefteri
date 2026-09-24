import Foundation
import Testing
@testable import KelimeDefteri

/// Hafıza motoru (`Memory.replay`): SPEC-MOTOR2 §7.1 senaryo tablosu ve §7.2 A'nın saf motor testleri.
/// Sayılar `docs/motor/sim_v8.py` ile karşılaştırıldı.
struct MotorReplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 1 Ocak 2026 + gün, verilen saat ve dakika (İstanbul).
    private func at(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute, second: second))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    /// Günün başı (04:00).
    private func dayStart(_ day: Int) -> Date { at(day, 4) }

    /// Olgun kelime: `day` günü 09:00'da S gün dayanıklılıkla kaydedilmiş taban (vadesi S gün sonra).
    private func mature(_ stability: Double, difficulty: Double = 5, day: Int = 0, hour: Int = 9, learned: Bool = false) -> Memory.Base {
        let anchor = at(day, hour)
        return Memory.Base(
            stability: stability, difficulty: difficulty, dueDate: anchor.addingTimeInterval(stability * Memory.dayLength),
            anchorAt: anchor, learnedAt: learned ? anchor : nil, at: anchor
        )
    }

    private func answer(_ date: Date, _ correct: Bool, _ mode: GameMode = .dailyReview, _ grade: AnswerGrade = .good) -> Memory.Answer {
        Memory.Answer(date: date, mode: mode, correct: correct, grade: correct ? grade : .again)
    }

    private func replay(_ base: Memory.Base, _ answers: [Memory.Answer], now: Date? = nil) -> Memory.State {
        Memory.replay(base: base, answers: answers, now: now ?? answers.map(\.date).max() ?? .now, calendar: calendar)
    }

    /// Yeni kelime (boş taban).
    private func replay(_ answers: [Memory.Answer]) -> Memory.State { replay(.empty, answers) }

    private func due(_ state: Memory.State, _ now: Date) -> String {
        Leitner.dueDescription(for: state.dueDate, now: now, calendar: calendar)
    }

    private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.005 }

    // MARK: - §7.1 senaryo tablosu

    @Test func newWordFirstWrong() {
        let recall = replay([answer(at(0), false)])
        #expect(close(recall.stability, 0.40))
        #expect(recall.difficulty == 7)
        #expect(recall.lapsedAt == dayStart(0))
        #expect(recall.dueDate == dayStart(1))
        #expect(recall.anchorAt == dayStart(0))
        #expect(due(recall, at(0)) == "Yarın")
        #expect(recall.learnedAt == nil)

        let recognition = replay([answer(at(0), false, .multipleChoice)])
        #expect(close(recognition.stability, 0.30))
        #expect(recognition.difficulty == 7)
    }

    @Test func newWordFirstCorrectStartsFromTheTable() {
        for (grade, stability, difficulty) in [(AnswerGrade.hard, 1.2, 6.0), (.good, 3, 5), (.easy, 8, 3.5)] {
            let state = replay([answer(at(0), true, .dailyReview, grade)])
            #expect(close(state.stability, stability))
            #expect(state.difficulty == difficulty)
            #expect(state.anchorAt == dayStart(0))
            #expect(state.dueDate == dayStart(0).addingTimeInterval(stability * Memory.dayLength))
            #expect(state.lapsedAt == nil)
        }
        // Tanıma ilk günde de az verir; çıpa yine o günün 04:00'ü.
        let recognition = replay([answer(at(0), true, .match)])
        #expect(close(recognition.stability, 1.8))
        #expect(recognition.anchorAt == dayStart(0))
    }

    @Test func newWordWrongAndRightInTwoRoundsIsWrong() {
        for order in [[false, true], [true, false]] {
            let state = replay([answer(at(0), order[0]), answer(at(0, 11), order[1])])
            #expect(close(state.stability, 0.40))
            #expect(state.difficulty == 7)
            #expect(state.lapsedAt == dayStart(0))
            #expect(due(state, at(0, 11)) == "Yarın")
        }
    }

    @Test func matureRightAndWrongInTwoRoundsIsWrong() {
        for order in [[true, false], [false, true]] {
            let state = replay(mature(30), [answer(at(30), order[0]), answer(at(30, 11), order[1])])
            #expect(close(state.stability, 11.40))
            #expect(close(state.difficulty, 5.85))
            #expect(state.lapsedAt == dayStart(30))
            #expect(due(state, at(30, 11)) == "Yarın")
        }
    }

    @Test func oneWrongInThreeRoundsIsHard() {
        for wrongIndex in 0..<3 {
            let answers = (0..<3).map { answer(at(30, 9 + 2 * $0), $0 != wrongIndex) }
            let state = replay(mature(30), answers)
            #expect(close(state.stability, 56.05))
            #expect(close(state.difficulty, 5.34))
            #expect(state.lapsedAt == nil)
            #expect(due(state, at(30, 13)) == "56 gün sonra")
            // Tabanda üretim günü taşınmaz: tek üretim günüyle öğrenildi yazılmaz.
            #expect(state.learnedAt == nil)
        }
    }

    @Test func correctsWithinThirtyMinutesOfAWrongDoNotCount() {
        let state = replay(mature(30), [answer(at(30), false), answer(at(30, 9, 5), true), answer(at(30, 9, 10), true)])
        #expect(close(state.stability, 11.40))
        #expect(state.lapsedAt == dayStart(30))
        // 31. ve 45. dakikada: ikisi de sayılır, oran 1/3 → zor.
        let later = replay(mature(30), [answer(at(30), false), answer(at(30, 9, 31), true), answer(at(30, 9, 45), true)])
        #expect(close(later.stability, 56.05))
        #expect(later.lapsedAt == nil)
    }

    @Test func matureOnTime() {
        let right = replay(mature(30), [answer(at(30), true)])
        #expect(close(right.stability, 82.09))
        #expect(right.difficulty == 5)
        #expect(due(right, at(30)) == "82 gün sonra")
        #expect(right.anchorAt == dayStart(30))

        let wrong = replay(mature(30), [answer(at(30), false)])
        #expect(close(wrong.stability, 11.40))
        #expect(close(wrong.difficulty, 5.85))
        #expect(wrong.dueDate == dayStart(31))
        #expect(due(wrong, at(30)) == "Yarın")
    }

    @Test func wrongYesterdayRightToday() {
        let state = replay(mature(30), [answer(at(30), false), answer(at(31), true)])
        #expect(close(state.stability, 13.38))
        #expect(close(state.difficulty, 5.72))
        #expect(state.lapsedAt == nil)
        #expect(due(state, at(31)) == "13 gün sonra")
    }

    @Test func wrongOnConsecutiveDaysUsesTheFixedPenalty() {
        let second = replay(mature(30), [answer(at(30), false), answer(at(31), false)])
        #expect(close(second.stability, 5.70))
        #expect(close(second.difficulty, 6.57))
        #expect(second.lapsedAt == dayStart(31))
        let third = replay(mature(30), [answer(at(30), false), answer(at(31), false), answer(at(32), false)])
        #expect(close(third.stability, 2.85))
        #expect(close(third.difficulty, 7.19))
        #expect(due(third, at(32)) == "Yarın")
    }

    @Test func veryStrongWordIsCappedAndRecoversWithRecall() {
        let learnedAt = at(0)
        var base = mature(300)
        base.learnedAt = learnedAt
        let wrong = replay(base, [answer(at(300), false)])
        #expect(close(wrong.stability, 51.96))
        #expect(close(wrong.difficulty, 5.85))
        #expect(due(wrong, at(300)) == "Yarın")
        #expect(wrong.learnedAt == learnedAt)

        let next = replay(base, [answer(at(300), false), answer(at(301), true)])
        #expect(close(next.stability, 53.43))
        #expect(close(next.difficulty, 5.72))
        #expect(next.lapsedAt == nil)
        #expect(due(next, at(301)) == "53 gün sonra")
        #expect(next.learnedAt == learnedAt)
    }

    @Test func luckyRecognitionOnYoungWordIsCappedAndKeepsTheAnchor() {
        let base = mature(10)
        let state = replay(base, [answer(at(10), true, .multipleChoice)])
        #expect(close(state.stability, 20.90))
        #expect(state.difficulty == 5)
        #expect(state.anchorAt == base.anchorAt)
        #expect(state.dueDate == base.anchorAt!.addingTimeInterval(20.9 * Memory.dayLength))
        #expect(due(state, at(10)) == "11 gün sonra")
        #expect(state.learnedAt == nil)
    }

    @Test func weakYoungWordClearsWithRecognitionOnTheSecondDay() {
        let first = replay(mature(30), [answer(at(30), false), answer(at(31), true, .fillBlank)])
        #expect(close(first.stability, 12.59))
        #expect(first.lapsedAt == dayStart(30))
        // Vade sabit: zayıflık gününün ertesi 04:00'ü.
        #expect(first.dueDate == dayStart(31))
        #expect(due(first, at(31)) == "Bugün")

        let second = replay(mature(30), [answer(at(30), false), answer(at(31), true, .fillBlank), answer(at(32), true, .match)])
        #expect(close(second.stability, 14.95))
        #expect(second.lapsedAt == nil)
        // Çıpa hâlâ yanlış gününde.
        #expect(second.anchorAt == dayStart(30))
        #expect(due(second, at(32)) == "12 gün sonra")
    }

    @Test func weakMatureWordNeedsRecall() {
        let answers = [answer(at(300), false), answer(at(301), true, .multipleChoice), answer(at(302), true, .match)]
        let state = replay(mature(300), answers)
        #expect(close(state.stability, 51.96))
        #expect(state.lapsedAt == dayStart(300))
        #expect(state.dueDate == dayStart(301))
        #expect(due(state, at(301)) == "Bugün")
        #expect(due(state, at(302)) == "1 gün gecikti")

        let recalled = replay(mature(300), answers + [answer(at(303), true)])
        #expect(recalled.lapsedAt == nil)
    }

    @Test func matureWordIsFrozenUnderRecognition() {
        let base = mature(30)
        let answers = (1...40).map { answer(at($0), true, .multipleChoice) }
        let state = replay(base, answers)
        #expect(state.stability == 30)
        #expect(state.difficulty == 5)
        #expect(state.anchorAt == base.anchorAt)
        #expect(state.dueDate == base.dueDate)
        #expect(due(state, at(40)) == "10 gün gecikti")
    }

    @Test func dayTurnsAtFourInTheMorning() {
        // 23:58 yanlış, 00:02 doğru: aynı gün.
        let night = replay(mature(30, hour: 12), [answer(at(30, 23, 58), false), answer(at(31, 0, 2), true)])
        #expect(close(night.stability, 11.40))
        #expect(night.lapsedAt == dayStart(30))
        #expect(due(night, at(31, 0, 10)) == "Yarın")

        // 03:58 yanlış, 04:02 doğru: farklı günler.
        let dawn = replay(mature(30, hour: 12), [answer(at(31, 3, 58), false), answer(at(31, 4, 2), true)])
        #expect(close(dawn.stability, 13.38))
        #expect(close(dawn.difficulty, 5.72))
        #expect(dawn.lapsedAt == nil)
        #expect(due(dawn, at(31, 4, 10)) == "13 gün sonra")
    }

    @Test func twoDevicesConverge() {
        let deviceA = [answer(at(30), false)]
        let deviceB = [answer(at(30, 11), true), answer(at(30, 13), true)]
        let onlyB = replay(mature(30), deviceB)
        #expect(close(onlyB.stability, 82.09))
        let merged = replay(mature(30), deviceB + deviceA)
        #expect(close(merged.stability, 56.05))
        #expect(close(merged.difficulty, 5.34))
        #expect(merged == replay(mature(30), deviceA + deviceB))
    }

    @Test func removingALogRestoresThePreviousState() {
        let before = replay(mature(30), [answer(at(30), true)])
        let after = replay(mature(30), [answer(at(30), true), answer(at(30, 11), false)])
        #expect(after != before)
        #expect(replay(mature(30), [answer(at(30), true)], now: at(30, 11)) == before)
    }

    // MARK: - §7.2 A: motor kuralları

    @Test func replayIsDeterministicAndOrderFree() {
        let answers = [
            answer(at(30), true), answer(at(30, 12), false, .letters), answer(at(31), true, .match),
            answer(at(33), true, .reverse, .easy), answer(at(33, 20), false, .fillBlank), answer(at(40), true),
        ]
        let expected = replay(mature(30), answers)
        var generator = SeededGenerator(seed: 5)
        for _ in 0..<10 {
            #expect(replay(mature(30), answers.shuffled(using: &generator), now: at(40)) == expected)
        }
    }

    @Test func simultaneousAnswersPutTheWrongOneFirst() {
        // Aynı saniyede doğru ve yanlış: yanlış önce sayılır, doğru 30 dakika kapısına takılır.
        let date = at(30)
        let state = replay(mature(30), [answer(date, true), answer(date, false)])
        #expect(close(state.stability, 11.40))
        #expect(state.lapsedAt == dayStart(30))
    }

    @Test func futureAnswersAreNotPlayed() {
        let state = replay(mature(30), [answer(at(30), true), answer(at(35), false)], now: at(31))
        #expect(close(state.stability, 82.09))
        #expect(state.lapsedAt == nil)
    }

    @Test func gateIsCountedInSeconds() {
        let wrong = at(30)
        // 1799. saniyedeki doğru sayılmaz: [Y, D] → 1/2 → yanlış.
        let inside = replay(mature(30), [
            answer(wrong, false), answer(wrong.addingTimeInterval(1799), true), answer(wrong.addingTimeInterval(2400), true),
        ])
        #expect(inside.lapsedAt == dayStart(30))
        // Tam 1800. saniyedeki doğru sayılır: [Y, D, D] → 1/3 → zor.
        let edge = replay(mature(30), [
            answer(wrong, false), answer(wrong.addingTimeInterval(1800), true), answer(wrong.addingTimeInterval(2400), true),
        ])
        #expect(edge.lapsedAt == nil)
        #expect(close(edge.stability, 56.05))
    }

    @Test func productionAnswersDecideTheDayWhenPresent() {
        // Tanımada yanlış ama hatırlamada doğru: günün notu üretimden.
        let state = replay(mature(30), [answer(at(30), false, .multipleChoice), answer(at(30, 12), true)])
        #expect(close(state.stability, 82.09))
        #expect(state.lapsedAt == nil)
        // Yalnız tanıma: tanımadaki yanlış kelimeyi zayıflatır, çıpayı ilerletir.
        let recognition = replay(mature(30), [answer(at(30), false, .match)])
        #expect(recognition.lapsedAt == dayStart(30))
        #expect(recognition.anchorAt == dayStart(30))
        // Tanıma yanlışının cezası daha sert (0.7).
        #expect(recognition.stability < 11.40)
    }

    @Test func productionClearsTheLapseAtAnyStability() {
        let young = replay(mature(10), [answer(at(10), false), answer(at(11), true, .letters)])
        #expect(young.lapsedAt == nil)
        let old = replay(mature(300), [answer(at(300), false), answer(at(301), true, .reverse)])
        #expect(old.lapsedAt == nil)
    }

    @Test func learnedAtIsWrittenOnceOnTheSecondProductionDay() {
        // Taban öğrenilmemiş: üretim günü sayımı sıfırdan başlar.
        let first = replay(mature(30), [answer(at(30), true)])
        #expect(first.learnedAt == nil)
        let answers = [answer(at(30), true), answer(at(113), true)]
        let second = replay(mature(30), answers)
        #expect(second.learnedAt == dayStart(113))
        // Sonra zayıflasa da tarih değişmez; canlı rozet (`isLearned`) ayrı.
        let lapsed = replay(mature(30), answers + [answer(at(114), false)])
        #expect(lapsed.learnedAt == dayStart(113))
        #expect(lapsed.lapsedAt != nil)
        // Tanıma günleri sayılmaz.
        let recognition = replay(mature(30), [answer(at(30), true), answer(at(113), true, .match)])
        #expect(recognition.learnedAt == nil)
    }

    @Test func learnedBaseCountsAsAlreadySatisfied() {
        var base = mature(15)
        base.learnedAt = at(-10)
        let state = replay(base, [answer(at(15), true)])
        #expect(state.learnedAt == at(-10))
    }

    @Test func answersUpToTheBaseAreNotPlayedAgain() {
        let base = mature(30)
        // Tabanın kendi anındaki ve öncesindeki cevaplar tabanda sayılmış kabul edilir.
        let state = replay(base, [answer(base.at!, false), answer(at(-3), false)], now: at(1))
        #expect(state.stability == 30)
        #expect(state.lapsedAt == nil)
        #expect(state.dueDate == base.dueDate)
        // Sonraki cevap oynatılır.
        #expect(replay(base, [answer(base.at!, false), answer(at(30), true)]).stability > 30)
    }

    @Test func emptyBaseIgnoresStrayBaseValues() {
        // `baseAt == .distantPast` iken diğer taban alanları (ör. iki cihazın alan bazında birleşmesi) yok sayılır.
        let stray = Memory.Base(stability: 40, difficulty: 2, dueDate: at(90), lapsedAt: at(1), anchorAt: at(1), learnedAt: at(1), at: .distantPast)
        #expect(replay(stray, [answer(at(0), true)]) == replay(.empty, [answer(at(0), true)]))
    }

    @Test func dueDescriptionNeverSaysNow() {
        let now = at(10, 12)
        #expect(Leitner.dueDescription(for: at(7, 12), now: now, calendar: calendar) == "3 gün gecikti")
        #expect(Leitner.dueDescription(for: at(10, 5), now: now, calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: at(10, 20), now: now, calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: at(11, 4), now: now, calendar: calendar) == "Yarın")
        #expect(Leitner.dueDescription(for: at(13, 9), now: now, calendar: calendar) == "3 gün sonra")
        // Gece yarısından sonra hâlâ önceki gün: aynı sabah 04:00'teki vade "Yarın".
        #expect(Leitner.dueDescription(for: at(11, 4), now: at(11, 1), calendar: calendar) == "Yarın")
        #expect(Leitner.dueDescription(for: at(11, 3), now: at(11, 1), calendar: calendar) == "Bugün")
        #expect(Leitner.dueDescription(for: .distantPast, now: now, calendar: calendar) == "Yeni")
    }
}
