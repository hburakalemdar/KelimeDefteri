import Foundation
import Observation

/// Bir çalışma turunun durumu: sıradaki kelimeler, gösterilen kart ve cevap.
@Observable
final class StudySession {
    enum Verdict: Equatable {
        case correct
        /// Ters Yön'de bir harf farkla doğru (yazım hatası).
        case almost
        case incorrect
        /// Cevap yazmadan karta dokunup Türkçesine baktı.
        case peeked
        /// Ters Yön'de defterdeki eşanlamlı başka bir kelime yazıldı (onun İngilizcesi); doğru ama zor sayılır.
        case synonymOf(String)
    }

    enum Phase: Equatable {
        case asking
        case revealed(Verdict)
    }

    /// Turda hangi kelimelerin sorulacağı.
    enum Plan: Equatable {
        /// Bütün zayıf kelimeler, sınırsız; tur sürerken zayıflayanlar da eklenir.
        case weak
        /// Günlük Tekrar: zayıf kelimeler, en fazla 20, bunların en fazla 5'i yeni.
        case daily
        /// Hepsi güçlüyken "Yine de Çalış": önce son günlerde zorlanılanlar, kalan yere en zayıflar; toplam 10.
        case extraPractice
        /// Yeni Eklenenler: Günlük Tekrar'ın bugün almadığı hiç çalışılmamış kelimeler; en yeni eklenen 10'u.
        case recent
        /// Hızlı Tur: bütün defterden ağırlıklı 5 kelime.
        case quick
        /// Ters Yön: bütün defterden ağırlıklı 10 kelime.
        case reverse
    }

    /// Tur özeti için kelime başına kayıt: turdaki ilk cevaptan hemen önceki vade ve zayıflık,
    /// ilk cevabın doğruluğu.
    struct RoundEntry {
        let word: Word
        /// İlk cevaptan hemen önceki `word.dueDate`; yeni kelimede `nil` ("Yeni").
        let dueBefore: Date?
        /// İlk cevaptan hemen önceki `word.isLapsed`.
        let lapsedBefore: Bool
        let firstCorrect: Bool

        init(word: Word, dueBefore: Date?, lapsedBefore: Bool, firstCorrect: Bool) {
            self.word = word
            self.dueBefore = dueBefore
            self.lapsedBefore = lapsedBefore
            self.firstCorrect = firstCorrect
        }

        /// Cevap kaydedilmeden hemen önce, kelimenin o anki durumundan.
        init(before word: Word, firstCorrect: Bool) {
            self.init(
                word: word, dueBefore: word.isNew ? nil : word.dueDate,
                lapsedBefore: word.isLapsed, firstCorrect: firstCorrect
            )
        }
    }

    /// Turdaki tek soru: yazarak hatırlama, ısınma için Çoktan Seçmeli ya da Harfleri Diz (bkz. `DailyMix`).
    /// Soru içeriği (şıklar, harf taşları) adım kurulurken sabitlenir; Mac'te pencere kapanıp açılınca aynı soru gelir.
    struct Step: Identifiable {
        enum Kind {
            /// Yazarak cevap (`RecallQuestionView`); tur kendi türüyle (`mode`) kaydeder.
            case recall
            /// Isınma: Çoktan Seçmeli.
            case choice(options: [String], correctIndex: Int)
            /// Üretim: Harfleri Diz (Türkçeden İngilizceye).
            case letters(LetterPuzzle)
        }

        /// Turda benzersiz; gecikmiş geri çağrılar (ör. 0,8 sn sonraki otomatik geçiş) eski adımı ilerletemesin diye.
        let id: Int
        let word: Word
        let kind: Kind

        var isWarmup: Bool {
            if case .choice = kind { true } else { false }
        }

        var isRecall: Bool {
            if case .recall = kind { true } else { false }
        }
    }

    nonisolated static let dailyLimit = 20
    nonisolated static let dailyNewLimit = 5
    nonisolated static let recentLimit = 10
    nonisolated static let quickCount = 5
    static let reverseCount = 10

    /// Kelimeler güçlüyken "Yine de Çalış" ile açılan turdaki kelime sayısı.
    static let extraPracticeCount = 10

    /// Sorulan adım; `current` onun kelimesi.
    private(set) var currentStep: Step?
    var current: Word? { currentStep?.word }
    /// Sorulan kelimenin sırası gelen anlamı, soru gösterilirken alınır (ipucu cümlesi bunun cümlesi); cevap
    /// kaydedilince `askedMeaning` ilerler ama açık sorunun cümlesi değişmez.
    private(set) var questionMeaning = ""
    /// Şu anki seçmeli/harf adımının cevabı kaydedildi mi: aynı adım ikinci kez kaydedilmez, ilerleme ancak bundan sonra.
    private(set) var stepAnswered = false
    private var stepCorrect = false
    private(set) var phase: Phase = .asking
    private(set) var plan: Plan = .weak
    private(set) var reviewedCount = 0
    /// Turdaki farklı kelime sayısı ve bilinip turdan çıkanlar. Bilinmeyen kelime sıraya yeniden
    /// girdiği için cevap sayısı büyür ama ilerleme bunlarla gösterilir: "3/5" beşten öteye geçmez.
    private(set) var wordCount = 0
    private(set) var finishedWordCount = 0
    private(set) var roundEntries: [RoundEntry] = []
    private(set) var startedAt: Date = .now
    /// Son cevabın verildiği an; tur süresi buna kadar sayılır.
    private(set) var finishedAt: Date = .now

    var isPracticeAll: Bool { plan == .extraPractice }
    /// Türkçesi gösterilip İngilizcesi mi soruluyor (Ters Yön).
    var isReverse: Bool { plan == .reverse }
    /// Cevaplar hangi oyun adına kaydedilir.
    var mode: GameMode = .dailyReview
    private var queue: [Step] = []
    private var nextStepID = 0
    /// Isınması cevaplanmış kelimelerin ısınmadan önceki durumu ve ısınmanın doğruluğu; tur özeti kaydı
    /// üretim cevabıyla birlikte yazılır.
    private var warmupEntries: [ObjectIdentifier: RoundEntry] = [:]
    private var generator: SeededGenerator
    private let defaults: UserDefaults
    /// Kartın gösterildiği an ve cevabın açılmasına kadar geçen süre.
    private var shownAt: Date = .now
    private var responseTime: Double = 0
    private var pausedAt: Date?
    /// Turun başladığı an (duraklatmayla kaymaz); tur başka bir günde mi başladı diye ve tur özetindeki
    /// "bugün daha önce görüldü" notu için bakılır.
    private(set) var roundBeganAt: Date = .now
    /// En az bir kelimeyle bir tur başlatıldı mı. `current == nil` iken "tur bitti" (özet) ile
    /// "tur hiç başlamadı / soracak kelime yoktu" durumlarını ayırır.
    private(set) var hasRound = false
    /// Turun başında verilen defter; Ters Yön'de eşanlamlı cevabı tanımak için.
    private var words: [Word] = []

    /// Arka plana geçerken kaydedilmiş, henüz ilerlenmemiş cevap ve kaydı geri alan işlem.
    private struct Committed {
        let known: Bool
        let undo: () -> Void
    }
    private var committed: Committed?

    /// Önceki turun ilk kelimesi; yeni tur onunla başlamasın diye saklanır.
    static let lastFirstWordKey = "StudySession.lastFirstWord"

    var remaining: Int { queue.count }

    /// Karışık soru türleri (ısınma + üretim) açık mı: Günlük Tekrar, Tanış ve Yine de Çalış.
    /// Hızlı Tur ve Ters Yön yalnız yazarak sorar.
    var usesMix: Bool { Self.usesMix(plan) }

    static func usesMix(_ plan: Plan) -> Bool {
        switch plan {
        case .daily, .recent, .extraPractice: true
        case .weak, .quick, .reverse: false
        }
    }

    /// `seed` testte sırayı sabitlemek için; verilmezse her açılışta farklı sıra çıkar.
    init(seed: UInt64 = .random(in: .min ... .max), defaults: UserDefaults = .standard) {
        generator = SeededGenerator(seed: seed)
        self.defaults = defaults
    }

    /// `practiceAll` false ise bütün zayıf kelimeler, true ise en zayıf 10 kelime (Mac menü penceresi).
    func start(with words: [Word], practiceAll: Bool, now: Date = .now) {
        start(with: words, plan: practiceAll ? .extraPractice : .weak, now: now)
    }

    /// Sıra karışıktır; tekrara en çok ihtiyacı olan kelime öne gelme eğilimindedir.
    func start(with words: [Word], plan: Plan, now: Date = .now) {
        // Eski biçimli kelime yeni sayılıp seçimi ve özeti bozmasın.
        for word in words { MemoryMigration.migrate(word) }
        self.plan = plan
        reviewedCount = 0
        roundEntries = []
        warmupEntries = [:]
        self.words = words
        startedAt = now
        roundBeganAt = now
        finishedAt = now
        let previousFirst = defaults.string(forKey: Self.lastFirstWordKey)
        let picked: [Word] = switch plan {
        case .weak:
            ordered(words.filter { $0.isDue(at: now) }, now: now, avoidingFirst: previousFirst)
        case .daily:
            // Önce çalışılmış zayıflar, kalan yere yeniler; kartta yazan dağılımla aynı olsun diye.
            dailyWords(words, now: now, avoidingFirst: previousFirst)
        case .extraPractice:
            extraPracticeWords(words, now: now, avoidingFirst: previousFirst)
        case .recent:
            ordered(Self.recentWords(words, now: now), now: now, avoidingFirst: previousFirst)
        case .quick:
            ordered(words, now: now, avoidingFirst: previousFirst, limit: Self.quickCount)
        case .reverse:
            ordered(words, now: now, avoidingFirst: previousFirst, limit: Self.reverseCount)
        }
        queue = steps(for: picked, now: now)
        if let first = queue.first {
            defaults.set(Self.key(for: first.word), forKey: Self.lastFirstWordKey)
        }
        wordCount = picked.count
        finishedWordCount = 0
        hasRound = !queue.isEmpty
        advance(now: now)
    }

    /// "Bir Tur Daha"nın açacağı tur: Yeni Eklenenler bitince Günlük Tekrar, Günlük Tekrar'da iş
    /// kalmayınca en zayıflarla ek tur ("Yine de Çalış"); diğer turlar kendini tekrarlar.
    static func againPlan(after plan: Plan, words: [Word], now: Date = .now) -> Plan {
        switch plan {
        case .recent where !recentWords(words, now: now).isEmpty:
            return .recent
        case .recent, .daily, .extraPractice:
            let count = dailyCount(words, now: now)
            return count.weak + count.new > 0 ? .daily : .extraPractice
        case .weak, .quick, .reverse:
            return plan
        }
    }

    /// Tur özetindeki düğmenin adı: aynı tur tekrarlanıyorsa "Bir Tur Daha", başka akışa geçiliyorsa onun adı.
    static func againTitle(after plan: Plan, next: Plan) -> String {
        guard next != plan else { return "Bir Tur Daha" }
        return switch next {
        case .daily: "Günlük Tekrar'a Geç"
        case .extraPractice: "Yine de Çalış"
        default: "Bir Tur Daha"
        }
    }

    private func dailyWords(_ words: [Word], now: Date, avoidingFirst previousFirst: String?) -> [Word] {
        let count = Self.dailyCount(words, now: now)
        // Yarıda bırakılan turdan üretimi kalan kelimeler önce alınır; sınır dolsa da dışarıda kalmasın.
        let pending = ordered(words.filter { !$0.isNew && $0.isPendingProduction(now: now) }, now: now, limit: count.weak)
        let taken = Set(pending.map(ObjectIdentifier.init))
        let due = ordered(
            words.filter { !$0.isNew && $0.isDue(at: now) && !taken.contains(ObjectIdentifier($0)) },
            now: now, limit: max(0, count.weak - pending.count)
        )
        return ordered(pending + due + Self.dailyNewWords(words, now: now), now: now, avoidingFirst: previousFirst)
    }

    /// Seçilen kelimelerin ilk adımları. Karışık turda ısınmaya uygun kelime Çoktan Seçmeli ile başlar (üretim adımı
    /// ısınma cevaplanınca eklenir), bugün ısınması yapılmış kelime doğrudan üretimle, diğerleri yazarak.
    private func steps(for picked: [Word], now: Date) -> [Step] {
        guard usesMix else { return picked.map { makeStep($0, .recall) } }
        let deckMeanings = GameDeck.distinctMeaningCount(words.map(\.turkish))
        let first = picked.map { word -> Step in
            let pending = !word.isNew && word.isPendingProduction(now: now)
            if DailyMix.needsWarmup(
                isNew: word.isNew, isLapsed: word.isLapsed, pendingProduction: pending, deckMeanings: deckMeanings
            ), let choice = choiceKind(for: word) {
                return makeStep(word, choice)
            }
            return makeStep(word, pending ? productionKind(for: word) : .recall)
        }
        return DailyMix.order(warmups: first.map(\.isWarmup)).map { first[$0] }
    }

    private func makeStep(_ word: Word, _ kind: Step.Kind) -> Step {
        nextStepID += 1
        return Step(id: nextStepID, word: word, kind: kind)
    }

    /// Çoktan Seçmeli şıkları (doğru şık sırası gelen anlam); 3 çeldirici bulunamazsa `nil` (ısınma atlanır).
    private func choiceKind(for word: Word) -> Step.Kind? {
        let others = words.filter { $0 !== word }.map { ChoiceQuiz.Candidate(turkish: $0.turkish) }
        let result = ChoiceQuiz.options(answer: word.askedCandidate, others: others, using: &generator)
        guard result.options.count == DailyMix.minimumMeanings else { return nil }
        return .choice(options: result.options, correctIndex: result.correctIndex)
    }

    /// Üretim sorusu: harfleri sığıyorsa Harfleri Diz, uzun ifadede yazarak.
    private func productionKind(for word: Word) -> Step.Kind {
        DailyMix.productionUsesLetters(english: word.english)
            ? .letters(LetterPuzzle(word: word.english, using: &generator))
            : .recall
    }

    /// Günlük Tekrar kartının ikinci satırı için: üretimi bekleyen kelime sayısı ve soru türlerine göre tahmini
    /// süre (saniye; "yaklaşık 3 dk"). Bekleyen kelimeler tek geçişte bulunur. Çalışılmış kelimeler 20'yi aşarsa
    /// hangilerinin seçileceği rastgele olduğu için ortalamaları alınır. `count`: `dailyCount(words, now:)`.
    static func dailyEstimate(
        _ words: [Word], now: Date = .now, count: (weak: Int, new: Int)
    ) -> (pending: Int, seconds: Double) {
        let pendingIDs = Set(words.filter { !$0.isNew && $0.isPendingProduction(now: now) }.map(ObjectIdentifier.init))
        let deckMeanings = GameDeck.distinctMeaningCount(words.map(\.turkish))
        func seconds(_ word: Word) -> Double {
            let pending = pendingIDs.contains(ObjectIdentifier(word))
            let warmup = DailyMix.needsWarmup(
                isNew: word.isNew, isLapsed: word.isLapsed, pendingProduction: pending, deckMeanings: deckMeanings
            )
            return DailyMix.seconds(
                warmup: warmup, pendingProduction: pending, letters: DailyMix.productionUsesLetters(english: word.english)
            )
        }
        let studied = words.filter { !$0.isNew && ($0.isDue(at: now) || pendingIDs.contains(ObjectIdentifier($0))) }
            .map(seconds)
        let studiedSeconds = studied.isEmpty ? 0 : studied.reduce(0, +) / Double(studied.count) * Double(count.weak)
        let newWords = Array(newWordsOldestFirst(words).prefix(count.new))
        return (pendingIDs.count, studiedSeconds + newWords.map(seconds).reduce(0, +))
    }

    /// Üretimi bekleyen (yarıda bırakılan ısınmadan kalan) kelime sayısı; kartta "zayıfladı"dan ayrı yazılır.
    static func pendingProductionCount(_ words: [Word], now: Date = .now) -> Int {
        words.count { !$0.isNew && $0.isPendingProduction(now: now) }
    }

    // MARK: Yeni kelimelerin paylaşımı

    /// Hiç çalışılmamış kelimeler eklenme sırasıyla (eşitse İngilizce yazılışa göre); sıra her açılışta aynı.
    private static func newWordsOldestFirst(_ words: [Word]) -> [Word] {
        words.filter(\.isNew).sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : AnswerChecker.fold($0.english) < AnswerChecker.fold($1.english)
        }
    }

    /// Günlük Tekrar'ın bugünkü yenileri: en önce eklenenler (sırası gelen bekletilmez).
    static func dailyNewWords(_ words: [Word], now: Date = .now) -> [Word] {
        Array(newWordsOldestFirst(words).prefix(dailyCount(words, now: now).new))
    }

    /// Yeni Eklenenler turunun kelimeleri: Günlük Tekrar'ın almadığı yeniler, en yeni eklenen önce, en fazla 10.
    /// Günlük Tekrar en eskileri aldığı için ikisi aynı kelimeyi sormaz.
    static func recentWords(_ words: [Word], now: Date = .now) -> [Word] {
        let queued = newWordsOldestFirst(words).dropFirst(dailyCount(words, now: now).new)
        return Array(queued.reversed().prefix(recentLimit))
    }

    /// Günlük Tekrar'ın bugün almadığı yeni kelime sayısı; 0 ise Günlük Tekrar kartındaki satır görünmez.
    static func recentWaitingCount(_ words: [Word], now: Date = .now) -> Int {
        words.count(where: \.isNew) - dailyCount(words, now: now).new
    }

    /// Zorlanılan kelimeler ağırlıklı karışık sırayla önde; kalan yer hafızası en düşüklerle dolar.
    private func extraPracticeWords(_ words: [Word], now: Date, avoidingFirst previousFirst: String?) -> [Word] {
        let struggling = ordered(
            words.filter { Self.isStruggling($0, now: now) }, now: now,
            avoidingFirst: previousFirst, limit: Self.extraPracticeCount
        )
        let taken = Set(struggling.map(ObjectIdentifier.init))
        let rest = Self.weakest(
            words.filter { !taken.contains(ObjectIdentifier($0)) },
            count: Self.extraPracticeCount - struggling.count, now: now
        )
        return struggling + ordered(rest, now: now, avoidingFirst: struggling.isEmpty ? previousFirst : nil)
    }

    /// "Yine de Çalış"ta zorlanılan sayılan kelimeler için bakılan süre (gün).
    static let strugglingWindow = 14.0
    static let strugglingMinimumAnswers = 2
    static let strugglingErrorRate = 0.4

    /// Son 14 günde en az 2 cevabı olup en az %40'ı yanlış ya da bu süredeki son cevabı yanlış olan kelime.
    static func isStruggling(_ word: Word, now: Date) -> Bool {
        let since = now.addingTimeInterval(-strugglingWindow * Memory.dayLength)
        let recent = (word.logs ?? []).filter { $0.date >= since && $0.date <= now }
        guard let last = recent.max(by: { $0.date < $1.date }) else { return false }
        if !last.correct { return true }
        guard recent.count >= strugglingMinimumAnswers else { return false }
        return Double(recent.count { !$0.correct }) / Double(recent.count) >= strugglingErrorRate
    }

    /// Hafızası en düşük kelimeler; yeniler en başta.
    static func weakest(_ words: [Word], count: Int, now: Date) -> [Word] {
        Array(words.sorted { ($0.memory(at: now) ?? -1) < ($1.memory(at: now) ?? -1) }.prefix(count))
    }

    /// Günlük Tekrar turuna girecek kelime sayısı: vadesi gelmiş çalışılmış kelimeler ve yeniler; günde en
    /// fazla 5 yeni kelime (bugün tanıtılanlar düşülür), toplam en fazla 20.
    /// Yarıda bırakılan turdan üretimi kalan kelimeler (`isPendingProduction`) de çalışılmış sayılır.
    static func dailyCount(_ words: [Word], now: Date = .now) -> (weak: Int, new: Int) {
        dailyCount(
            weak: words.count { !$0.isNew && ($0.isDue(at: now) || $0.isPendingProduction(now: now)) },
            new: words.count(where: \.isNew),
            introducedToday: introducedToday(words, now: now)
        )
    }

    /// Aynı sınır yalnızca sayılarla; bildirim ve rozet de Günlük Tekrar'ın soracağı sayıyı gösterir.
    nonisolated static func dailyCount(weak: Int, new: Int, introducedToday: Int) -> (weak: Int, new: Int) {
        let takenNew = min(new, max(0, dailyNewLimit - introducedToday), max(0, dailyLimit - min(weak, dailyLimit)))
        return (min(weak, dailyLimit), takenNew)
    }

    /// İlk cevabı bugün (04:00 sınırıyla) verilen kelime sayısı: günlük yeni kelime sınırı bunlarla dolar.
    static func introducedToday(_ words: [Word], now: Date = .now) -> Int {
        let today = DayBoundary.start(of: now)
        return words.count { word in
            guard let first = word.logs?.min(by: { $0.date < $1.date }) else { return false }
            return DayBoundary.start(of: first.date) == today
        }
    }

    func reveal(answer: String?, now: Date = .now) {
        guard let step = currentStep, step.isRecall, phase == .asking else { return }
        let word = step.word
        responseTime = now.timeIntervalSince(shownAt)
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            phase = .revealed(.peeked)
        } else if isReverse {
            let verdict: Verdict = switch ReverseChecker.check(trimmed, expected: word.english, in: words) {
            case .exact: .correct
            case .typo: .almost
            case .synonymOf(let other): .synonymOf(other)
            case .wrong: .incorrect
            }
            phase = .revealed(verdict)
        } else {
            phase = .revealed(AnswerChecker.isCorrect(trimmed, expected: word.turkish) ? .correct : .incorrect)
        }
    }

    /// Sonucu belli olan ama düğmesine basılmamış cevabı öne çıkan düğmeyle kaydeder (ör. ✕ ile kapatılınca).
    /// Yalnızca cevaba bakıldıysa ne bilindiği belli olmadığı için kaydedilmez.
    func gradePendingAnswer(now: Date = .now) {
        guard let known = pendingKnown else { return }
        grade(known: known, now: now)
    }

    /// Uygulama arka plana geçerken (kapatılabilir) sonucu belli cevabı hemen kaydeder ama karttan
    /// ilerlemez; kullanıcı döndüğünde aynı ekranı görür. Sonra aynı düğmeye basarsa yalnızca ilerlenir,
    /// başka düğmeye basarsa (ör. "Doğru Say") bu kayıt geri alınıp yenisi yazılır.
    func commitPendingAnswer(now: Date = .now) {
        guard committed == nil, let step = currentStep, step.isRecall, !step.word.isDeleted,
              let known = pendingKnown else { return }
        let entryCount = roundEntries.count
        let finishedBefore = finishedAt
        let log = record(step, grade: recallGrade(step.word, known: known), now: now)
        // Geri alma: kayıt silinir, hafıza kalan cevaplardan yeniden hesaplanır.
        committed = Committed(known: known) { [weak self] in
            if let log { ReviewRecorder.undo(log, now: now) }
            self?.roundEntries.removeSubrange(entryCount...)
            self?.finishedAt = finishedBefore
        }
    }

    /// Öne çıkan düğmenin anlamı: doğru cevap bilinmiş, yanlış cevap bilinmemiş. Cevaba bakıldıysa `nil`.
    private var pendingKnown: Bool? {
        guard case .revealed(let verdict) = phase, verdict != .peeked else { return nil }
        return verdict.gradeOptions.first(where: \.isPrimary)?.known
    }

    /// Uygulama arka plandayken geçen süre cevap süresine sayılmaz.
    func pauseClock(now: Date = .now) {
        if pausedAt == nil { pausedAt = now }
    }

    /// Tur sürüyorsa arka planda geçen süre tur süresine de sayılmaz.
    func resumeClock(now: Date = .now) {
        guard let pausedAt else { return }
        let paused = now.timeIntervalSince(pausedAt)
        shownAt += paused
        if current != nil { startedAt += paused }
        self.pausedAt = nil
    }

    /// Tur `now`'dan farklı bir takvim gününde başladı (Mac'te pencere günlerce açık kalabilir).
    func began(onAnotherDayThan now: Date = .now, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(roundBeganAt, inSameDayAs: now)
    }

    /// Yazarak cevap adımının notu (Bilemedim / Bildim ya da öne çıkan düğme).
    func grade(known: Bool, now: Date = .now) {
        guard let step = currentStep, step.isRecall else { return }
        let word = step.word
        // Kelime başka yerde silinmişse kaydetmeden geç.
        guard !word.isDeleted else {
            wordCount -= 1
            advance(now: now)
            return
        }
        if let committed {
            self.committed = nil
            if committed.known != known {
                committed.undo()
                record(step, grade: recallGrade(word, known: known), now: now)
            }
        } else {
            record(step, grade: recallGrade(word, known: known), now: now)
        }
        reviewedCount += 1
        complete(step, correct: known, now: now)
    }

    /// Seçmeli ya da harf adımının cevabı: yalnız sorulan adımsa (`stepID`) ve daha önce kaydedilmediyse kaydedilir.
    func answer(_ grade: AnswerGrade, step stepID: Int, now: Date = .now) {
        guard let step = currentStep, step.id == stepID, !step.isRecall, !stepAnswered, !step.word.isDeleted else { return }
        responseTime = now.timeIntervalSince(shownAt)
        stepAnswered = true
        stepCorrect = grade.isCorrect
        record(step, grade: grade, now: now)
    }

    /// Seçmeli ya da harf adımından sonrakine geçer. Soru bu arada değiştiyse (gecikmiş otomatik geçiş, pencere
    /// kapanıp açılınca atlanan adım) ya da cevap kaydedilmediyse bir şey yapmaz.
    func next(from stepID: Int, now: Date = .now) {
        guard let step = currentStep, step.id == stepID, stepAnswered else { return }
        complete(step, correct: stepCorrect, now: now)
    }

    /// Mac'te pencere yeniden açılınca: cevabı kaydedilmiş seçmeli/harf sorusu yeniden gösterilmez (görünümün
    /// seçimi sıfırlanır, aynı soru ikinci kez cevaplanabilirdi); sıradaki adıma geçilir.
    func skipAnsweredStep(now: Date = .now) {
        guard let step = currentStep, stepAnswered else { return }
        next(from: step.id, now: now)
    }

    /// Cevaplanan adımdan sonra sıra: ısınmadan sonra üretim adımı araya en az iki kelime girecek yere eklenir
    /// (o kadar kelime yoksa sona; üretim hiç atlanmaz). Üretim yanlışsa aynı tür yeniden sorulur; hemen arkasından
    /// değil, arada en az iki kelime olacak şekilde. O kadar kelime kalmadıysa yeniden sorulmaz, turdan çıkar.
    /// Kuyrukta bir kelimenin en fazla bir adımı bulunur; bu yüzden "iki adım" iki farklı kelime demektir.
    private func complete(_ step: Step, correct: Bool, now: Date) {
        if step.isWarmup {
            let production = makeStep(step.word, productionKind(for: step.word))
            queue.insert(production, at: WordPicker.reinsertionIndex(queueCount: queue.count) ?? queue.count)
        } else if !correct, let index = WordPicker.reinsertionIndex(queueCount: queue.count) {
            let retry: Step.Kind = step.isRecall ? .recall : productionKind(for: step.word)
            queue.insert(makeStep(step.word, retry), at: index)
        } else {
            finishedWordCount += 1
        }
        advance(now: now)
    }

    private func recallGrade(_ word: Word, known: Bool) -> AnswerGrade {
        let verdict: Verdict = if case .revealed(let verdict) = phase { verdict } else { .peeked }
        let letters = (isReverse ? word.english : word.turkish).count(where: \.isLetter)
        return AnswerGrade.recall(verdict: verdict, known: known, responseTime: responseTime, letters: letters)
    }

    /// Adımın kaydedildiği oyun türü: yazarak cevap turun türüyle, diğerleri kendi oyunlarıyla.
    private func mode(of step: Step) -> GameMode {
        switch step.kind {
        case .recall: mode
        case .choice: DailyMix.warmupMode
        case .letters: .letters
        }
    }

    @discardableResult
    private func record(_ step: Step, grade: AnswerGrade, now: Date) -> ReviewLog? {
        let word = step.word
        // Eski biçimli kelimenin önceki durumu "Yeni" görünmesin.
        MemoryMigration.migrate(word)
        // Tur özeti turdaki ilk cevaba bakar; aynı gündeki bütün cevaplar motorda birlikte değerlendirilir.
        // Isınan kelime özete ilk üretim cevabıyla girer: önceki durum ısınmadan önceki, doğru sayılması için
        // ısınma da ilk üretim de doğru olmalı. Üretimi yapılmadan bırakılan kelime özete girmez.
        let key = ObjectIdentifier(word)
        if !roundEntries.contains(where: { $0.word === word }) {
            if step.isWarmup {
                if warmupEntries[key] == nil {
                    warmupEntries[key] = RoundEntry(before: word, firstCorrect: grade.isCorrect)
                }
            } else if let warmup = warmupEntries[key] {
                roundEntries.append(RoundEntry(
                    word: word, dueBefore: warmup.dueBefore, lapsedBefore: warmup.lapsedBefore,
                    firstCorrect: warmup.firstCorrect && grade.isCorrect
                ))
            } else {
                roundEntries.append(RoundEntry(before: word, firstCorrect: grade.isCorrect))
            }
        }
        finishedAt = now
        return ReviewRecorder.record(word, grade: grade, mode: mode(of: step), responseTime: responseTime, now: now)
    }

    /// Kelime listesi dışarıda değiştiğinde (silme, yeni kelime, iCloud'dan gelen değişiklik)
    /// ya da zaman geçtiğinde sırayı onunla uyumlu tutar: silinenler çıkar, zayıflamış
    /// ama sırada olmayanlar sona eklenir. Tur bitmişse yeni gelenlerle devam eder.
    ///
    /// Yalnızca `.weak` turunda yeni zayıflayanlar eklenir; diğer turların kelimeleri baştan bellidir.
    func sync(with words: [Word], now: Date = .now) {
        for word in words { MemoryMigration.migrate(word) }
        self.words = words
        let alive = Set(words.map(\.persistentModelID))
        // İlerleme benzersiz kelimeyle sayılır: silinen kelimenin kaç adımı olursa olsun sayaçtan bir düşer.
        var gone = Set(queue.filter { !alive.contains($0.word.persistentModelID) }.map { ObjectIdentifier($0.word) })
        queue.removeAll { !alive.contains($0.word.persistentModelID) }
        let currentDeleted = current.map { !alive.contains($0.persistentModelID) } ?? false
        if currentDeleted, let current { gone.insert(ObjectIdentifier(current)) }
        wordCount -= gone.count
        guard plan == .weak else {
            if currentDeleted { advance(now: now) }
            return
        }

        // Bu turda bilinenlerin hafızası güçlendiği için tekrar eklenmezler.
        let queued = Set(queue.map(\.word.persistentModelID) + [current?.persistentModelID].compactMap { $0 })
        let added = ordered(words.filter { $0.isDue(at: now) && !queued.contains($0.persistentModelID) }, now: now)
        queue += added.map { makeStep($0, .recall) }
        wordCount += added.count

        if let current, alive.contains(current.persistentModelID) { return }
        advance(now: now)
    }

    private func ordered(
        _ words: [Word], now: Date, avoidingFirst previousFirst: String? = nil,
        limit: Int? = nil, maxNew: Int? = nil
    ) -> [Word] {
        // Aynı yazılışlı iki kayıt olabilir; kimlik olarak dizideki yer kullanılır.
        let candidates = words.indices.map { index in
            let memory = words[index].memory(at: now)
            return WordPicker.Candidate(id: index, weight: WordPicker.weight(memory: memory), isNew: memory == nil)
        }
        let avoided = previousFirst.flatMap { key in words.firstIndex { Self.key(for: $0) == key } }
        return WordPicker.order(candidates, limit: limit, maxNew: maxNew, avoidingFirst: avoided, using: &generator)
            .map { words[$0] }
    }

    private static func key(for word: Word) -> String { AnswerChecker.fold(word.english) }

    private func advance(now: Date) {
        currentStep = queue.isEmpty ? nil : queue.removeFirst()
        questionMeaning = currentStep.map { step in
            // Seçmeli adımda doğru şık zaten sorulan anlam.
            if case .choice(let options, let correctIndex) = step.kind { options[correctIndex] }
            else if step.word.isDeleted { "" } else { step.word.askedMeaning }
        } ?? ""
        stepAnswered = false
        stepCorrect = false
        phase = .asking
        shownAt = now
        // Duraklatılmışken (pencere kapalı) ilerlenirse saat duraklatılmış kalır; yeni kart şimdiden sayılır.
        // O ana kadarki duraklama tur süresinden düşülür (Mac'te cevaplanmış soru pencere açılınca atlanır);
        // tur bittiyse düşülmez: süre son cevaba (`finishedAt`) kadar sayılır, duraklama zaten dışında kalır.
        if let pausedAt {
            if currentStep != nil { startedAt += now.timeIntervalSince(pausedAt) }
            self.pausedAt = now
        }
        committed = nil
        responseTime = 0
    }
}

extension Word {
    /// Bugün ısınması yapılıp üretimi yapılmamış mı (bkz. `DailyMix.isPendingProduction`).
    ///
    /// "Bugün yeniydi" çıpadan (`lastReviewedAt`) okunur (gerekçe `DailyMix.isPendingProduction`'da).
    func isPendingProduction(now: Date = .now) -> Bool {
        let anchoredToday = lastReviewedAt.map { DayBoundary.isSameDay($0, now) } ?? false
        // Kayıtlara bakmadan eleme: zayıf değilse ve çıpası bugün değilse bekleyemez.
        guard isLapsed || anchoredToday, let logs, !logs.isEmpty else { return false }
        return DailyMix.isPendingProduction(
            logs: logs.map { ($0.date, $0.mode) }, isLapsed: isLapsed, anchoredToday: anchoredToday, now: now
        )
    }
}
