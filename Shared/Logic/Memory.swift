import Foundation

/// Gün sabah 04:00'te döner: gece yarısından sonra verilen cevap hâlâ önceki güne sayılır.
nonisolated enum DayBoundary {
    static let hour = 4

    /// Tarihin ait olduğu günün başlangıcı (04:00; saat 04:00'ten önceyse bir önceki günün 04:00'ü).
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        let sameDay = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        guard date < sameDay else { return sameDay }
        return calendar.date(byAdding: .day, value: -1, to: sameDay) ?? sameDay.addingTimeInterval(-Memory.dayLength)
    }

    /// Bir sonraki günün başlangıcı (04:00).
    static func nextStart(after date: Date, calendar: Calendar = .current) -> Date {
        let start = start(of: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(Memory.dayLength)
    }

    /// İki tarihin günleri arasındaki tam gün farkı (takvim bileşeniyle, `timeInterval/86400` değil).
    static func days(from a: Date, to b: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: start(of: a, calendar: calendar), to: start(of: b, calendar: calendar)).day ?? 0
    }

    static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        start(of: a, calendar: calendar) == start(of: b, calendar: calendar)
    }
}

/// Hafıza motoru (Motor 2): kelimenin durumu, bir tabandan sonraki bütün cevapların gün gün yeniden
/// oynatılmasıyla hesaplanır (`replay`). Cevapların sırası, hangi cihazdan geldiği ya da hangi sırayla
/// eşitlendiği sonucu değiştirmez. Ayrıntılar `docs/SPEC-MOTOR2.md` §2.
///
/// S gün cinsindendir: çıpadan S gün sonra kelimeyi hatırlama ihtimali %90'a iner.
nonisolated enum Memory {
    static let dayLength: TimeInterval = 86_400
    /// Sıradaki tekrar bu hatırlama ihtimaline göre konur.
    static let targetRetention = 0.9
    static let minimumStability = 0.3
    static let maximumStability = 3650.0
    static let difficultyRange = 1.0...10.0
    /// "Öğrenildi" sınırı (gün): dayanıklılığı üç haftayı geçen kelime uzun süre akılda kalır.
    static let learnedStability = 21.0
    /// Tanıma (seçmeli oyunlar, widget) olgunlaşmamış kelimeyi en fazla buraya kadar büyütür.
    static let recognitionCap = 20.9
    /// Zayıf kelimede gösterilen en yüksek hafıza.
    static let lapseMemory = 0.5
    /// Yanlıştan sonra bu süreden (saniye) kısa sürede gelen doğru, günün notuna sayılmaz.
    static let wrongGate: TimeInterval = 1800
    /// Yanlış oranı bunu aşarsa gün "yanlış" sayılır.
    static let wrongRatio = 1.0 / 3.0

    static let firstStability = [0.4, 1.2, 3.0, 8.0]
    static let firstDifficulty = [7.0, 6.0, 5.0, 3.5]

    /// Hatırlama ihtimali: `(1 + 19/81 · t / S) ^ −0.5`. `t = S` iken 0.9.
    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + 19.0 / 81.0 * max(elapsedDays, 0) / stability, -0.5)
    }

    /// Nota göre zorluk değişir, sonra 5'e doğru %15 yaklaşır ve 1…10 içinde kalır.
    static func nextDifficulty(_ difficulty: Double, grade: AnswerGrade) -> Double {
        let delta = switch grade {
        case .again: 1.0
        case .hard: 0.4
        case .good: 0.0
        case .easy: -0.6
        }
        let moved = difficulty + delta
        let reverted = moved + (5 - moved) * 0.15
        return min(max(reverted, difficultyRange.lowerBound), difficultyRange.upperBound)
    }

    // MARK: - Yeniden oynatma

    /// Motorun okuduğu tek cevap (`ReviewLog`un değer kopyası).
    struct Answer: Equatable, Sendable {
        var date: Date
        var mode: GameMode
        var correct: Bool
        var grade: AnswerGrade

        init(date: Date, mode: GameMode, correct: Bool, grade: AnswerGrade) {
            self.date = date
            self.mode = mode
            self.correct = correct
            self.grade = correct ? (grade == .again ? .good : grade) : .again
        }

        /// Kayıtlı cevaptan; bilinmeyen oyun adı hatırlama sayılır, tutarsız not doğruluğa göre düzeltilir.
        init(date: Date, mode: String, correct: Bool, grade: Int) {
            self.init(
                date: date, mode: GameMode(rawValue: mode) ?? .dailyReview, correct: correct,
                grade: AnswerGrade(rawValue: grade) ?? .good
            )
        }

        /// Eşit zamanlı cevaplarda sıra: önce yanlış, sonra oyun adı (alfabetik), sonra not.
        static func precedes(_ a: Answer, _ b: Answer) -> Bool {
            if a.date != b.date { return a.date < b.date }
            if a.correct != b.correct { return !a.correct }
            if a.mode.rawValue != b.mode.rawValue { return a.mode.rawValue < b.mode.rawValue }
            return a.grade.rawValue < b.grade.rawValue
        }
    }

    /// Kayıtlı taban: bu ana (`at`) kadarki her şey hesaba katılmış kabul edilir.
    struct Base: Equatable, Sendable {
        var stability = 0.0
        var difficulty = 5.0
        var dueDate = Date.distantPast
        var lapsedAt: Date? = nil
        var anchorAt: Date? = nil
        var learnedAt: Date? = nil
        /// `nil` ya da `.distantPast`: boş taban, bütün cevaplar oynatılır.
        var at: Date? = nil

        static let empty = Base()

        var isEmpty: Bool { at == nil || at == .distantPast }
    }

    /// `replay`in sonucu; `Word` üzerindeki önbellek alanlarına yazılır.
    struct State: Equatable, Sendable {
        var stability: Double
        var difficulty: Double
        var dueDate: Date
        var lapsedAt: Date?
        var learnedAt: Date?
        /// Büyüme hesabının başlangıç anı (`Word.lastReviewedAt`); hiç cevaplanmamışsa `nil`.
        var anchorAt: Date?
    }

    /// Günün notunun kaynağı: üretim (yazarak hatırlama, Harfleri Diz) ya da tanıma.
    private struct DayResult {
        let grade: AnswerGrade
        let source: GameMode
        let isProduction: Bool
    }

    /// Oynatma sırasında taşınan, önbelleğe yazılmayan ara bilgi.
    private struct Progress {
        var state: State
        /// Yanlış olmayan üretim günü sayısı (`learnedAt` şartı için).
        var productionDays: Int
        /// Zayıflıktan sonra yanlış olmayan gün sayısı (tanımayla temizleme için).
        var cleanDaysSinceLapse: Int
    }

    /// Tabandan sonraki (`date > base.at`) ve `now`dan ileri olmayan cevapları gün gün oynatır.
    static func replay(base: Base, answers: [Answer], now: Date, calendar: Calendar = .current) -> State {
        var progress = Progress(
            state: State(
                stability: base.isEmpty ? 0 : base.stability,
                difficulty: base.isEmpty ? 5 : base.difficulty,
                dueDate: base.isEmpty ? .distantPast : base.dueDate,
                lapsedAt: base.isEmpty ? nil : base.lapsedAt,
                learnedAt: base.isEmpty ? nil : base.learnedAt,
                anchorAt: base.isEmpty ? nil : (base.anchorAt ?? base.at)
            ),
            productionDays: !base.isEmpty && base.learnedAt != nil ? 2 : 0,
            cleanDaysSinceLapse: 0
        )
        let since = base.isEmpty ? nil : base.at
        let played = answers
            .filter { answer in answer.date <= now && since.map { answer.date > $0 } ?? true }
            .sorted(by: Answer.precedes)
        let days = Dictionary(grouping: played) { DayBoundary.start(of: $0.date, calendar: calendar) }
        for day in days.keys.sorted() {
            guard let result = dayResult(days[day] ?? []) else { continue }
            progress = process(progress, day: day, result: result, calendar: calendar)
        }
        return progress.state
    }

    /// Günün notu (§2.4): yanlışlar her zaman, yanlıştan 30 dakikadan kısa süre sonra gelmeyen doğrular
    /// sayılır; üretim cevabı varsa yalnız onlara, yoksa tanımaya bakılır.
    private static func dayResult(_ answers: [Answer]) -> DayResult? {
        let sorted = answers.sorted(by: Answer.precedes)
        var primary: [Answer] = []
        for (index, answer) in sorted.enumerated() {
            if !answer.correct {
                primary.append(answer)
                continue
            }
            let gated = sorted[..<index].contains { earlier in
                !earlier.correct && answer.date.timeIntervalSince(earlier.date).rounded() < wrongGate
            }
            if !gated { primary.append(answer) }
        }
        guard !primary.isEmpty else { return nil }
        let production = primary.filter(\.mode.isProduction)
        let isProduction = !production.isEmpty
        let group = isProduction ? production : primary
        let wrong = group.filter { !$0.correct }
        let ratio = Double(wrong.count) / Double(group.count)
        if ratio > wrongRatio {
            // En sert yanlış: tanıma > Harfleri Diz > hatırlama.
            let source = wrong.min { $0.mode.lapseFactor < $1.mode.lapseFactor } ?? wrong[0]
            return DayResult(grade: .again, source: source.mode, isProduction: isProduction)
        }
        let right = group.filter(\.correct)
        // En iyi not; eşitse ağırlığı büyük olan; o da eşitse günün en erken cevabı.
        let best = right.enumerated().max { lhs, rhs in
            let (l, r) = (lhs.element, rhs.element)
            if l.grade != r.grade { return l.grade.rawValue < r.grade.rawValue }
            if l.mode.weight != r.mode.weight { return l.mode.weight < r.mode.weight }
            return lhs.offset > rhs.offset
        }?.element ?? right[0]
        return DayResult(grade: ratio > 0 ? .hard : best.grade, source: best.mode, isProduction: isProduction)
    }

    /// Günün işlenmesi (§2.5–§2.7).
    private static func process(_ progress: Progress, day: Date, result: DayResult, calendar: Calendar) -> Progress {
        var next = progress
        let old = progress.state
        let weight = result.source.weight
        let index = result.grade.rawValue - 1
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(dayLength)

        // Yeni kelimenin ilk günü: büyüme formülü S = 0'da tanımsız, sabit tablodan başlar.
        if old.stability <= 0 {
            let stability = max(minimumStability, firstStability[index] * weight)
            next.state.stability = stability
            next.state.difficulty = firstDifficulty[index]
            next.state.anchorAt = day
            if result.grade == .again {
                next.state.lapsedAt = day
                next.state.dueDate = tomorrow
                next.cleanDaysSinceLapse = 0
                return next
            }
            next.state.dueDate = day.addingTimeInterval(stability * dayLength)
            if result.isProduction { next.productionDays += 1 }
            return checkLearned(next, day: day)
        }

        let elapsed = old.anchorAt.map { Double(DayBoundary.days(from: $0, to: day, calendar: calendar)) } ?? old.stability
        let r = retrievability(elapsedDays: elapsed, stability: old.stability)

        if result.grade == .again {
            let factor = result.source.lapseFactor
            let stability = if old.lapsedAt != nil {
                max(minimumStability, old.stability * 0.5 * factor)
            } else {
                max(minimumStability, min(old.stability * (0.65 - 0.30 * r) * factor, 3 * old.stability.squareRoot()))
            }
            next.state.stability = min(stability, maximumStability)
            next.state.difficulty = nextDifficulty(old.difficulty, grade: .again)
            next.state.anchorAt = day
            next.state.lapsedAt = day
            next.state.dueDate = tomorrow
            next.cleanDaysSinceLapse = 0
            return next
        }

        let isRecognition = !result.isProduction
        if !(isRecognition && old.stability >= learnedStability) {
            let growth = exp(1.5) * (11 - old.difficulty) * pow(old.stability, -0.2) * (exp(1.2 * (1 - r)) - 1)
            let multiplier = switch result.grade {
            case .hard: 0.5
            case .easy: 1.5
            default: 1.0
            }
            var stability = old.stability * (1 + growth * multiplier * weight)
            if isRecognition { stability = min(stability, recognitionCap) }
            next.state.stability = min(stability, maximumStability)
            next.state.difficulty = nextDifficulty(old.difficulty, grade: result.grade)
            // Tanıma çıpayı ilerletmez.
            if !isRecognition { next.state.anchorAt = day }
        }
        if let lapsedAt = old.lapsedAt {
            next.cleanDaysSinceLapse += 1
            let cleared = result.isProduction
                ? !DayBoundary.isSameDay(lapsedAt, day, calendar: calendar)
                : old.stability < learnedStability && next.cleanDaysSinceLapse >= 2
            if cleared { next.state.lapsedAt = nil }
        }
        if next.state.lapsedAt == nil, let anchor = next.state.anchorAt {
            next.state.dueDate = anchor.addingTimeInterval(next.state.stability * dayLength)
        } else {
            next.state.dueDate = old.dueDate
        }
        if result.isProduction { next.productionDays += 1 }
        return checkLearned(next, day: day)
    }

    /// `learnedAt`: S ≥ 21, zayıf değil ve en az 2 farklı günde yanlış olmayan üretim katkısı; bir kez yazılır.
    private static func checkLearned(_ progress: Progress, day: Date) -> Progress {
        var next = progress
        let state = next.state
        if state.learnedAt == nil, state.stability >= learnedStability, state.lapsedAt == nil, next.productionDays >= 2 {
            next.state.learnedAt = day
        }
        return next
    }
}

extension GameMode {
    /// Günün notunda üretim mi (yazarak hatırlama, Harfleri Diz) yoksa tanıma mı (seçmeli oyunlar, widget).
    nonisolated var isProduction: Bool {
        switch self {
        case .dailyReview, .quickRound, .reverse, .letters: true
        case .multipleChoice, .match, .fillBlank: false
        }
    }

    /// Yanlış cevabın cezası: hatırlamada bilememek tanımada bilememekten daha az serttir.
    nonisolated var lapseFactor: Double {
        switch self {
        case .dailyReview, .quickRound, .reverse: 1.0
        case .letters: 0.85
        case .multipleChoice, .match, .fillBlank: 0.7
        }
    }
}
