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
        /// Hepsi güçlüyken "Yine de Çalış": en zayıf 10 kelime.
        case extraPractice
        /// Hızlı Tur: bütün defterden ağırlıklı 5 kelime.
        case quick
        /// Ters Yön: bütün defterden ağırlıklı 10 kelime.
        case reverse
    }

    /// Tur özeti için kelime başına kayıt: ilk sorulduğundaki hafıza ve ilk cevabın doğruluğu.
    struct RoundEntry {
        let word: Word
        let memoryBefore: Double?
        let firstCorrect: Bool
    }

    nonisolated static let dailyLimit = 20
    nonisolated static let dailyNewLimit = 5
    static let quickCount = 5
    static let reverseCount = 10

    /// Kelimeler güçlüyken "Yine de Çalış" ile açılan turdaki kelime sayısı.
    static let extraPracticeCount = 10

    private(set) var current: Word?
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
    private var queue: [Word] = []
    private var generator: SeededGenerator
    private let defaults: UserDefaults
    /// Kartın gösterildiği an ve cevabın açılmasına kadar geçen süre.
    private var shownAt: Date = .now
    private var responseTime: Double = 0
    private var pausedAt: Date?
    /// Turun başladığı an (duraklatmayla kaymaz); tur başka bir günde mi başladı diye bakılır.
    private var roundBeganAt: Date = .now
    /// Kelime başına hafızayı değiştiren son cevabın zamanı. Tur günlerce açık kalırsa (Mac)
    /// kelimenin başka bir günde verilen ilk cevabı yine hafızayı değiştirir.
    private var memoryAnsweredAt: [ObjectIdentifier: Date] = [:]
    /// Son cevaplanan kart; yanlış bilinen kelime hemen arkasından doğru bilinirse zayıf kalır.
    private var lastAnswered: Word?

    /// Arka plana geçerken kaydedilmiş, henüz ilerlenmemiş cevap ve kaydı geri alan işlem.
    private struct Committed {
        let known: Bool
        let undo: () -> Void
    }
    private var committed: Committed?

    /// Önceki turun ilk kelimesi; yeni tur onunla başlamasın diye saklanır.
    static let lastFirstWordKey = "StudySession.lastFirstWord"

    var remaining: Int { queue.count }

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
        memoryAnsweredAt = [:]
        lastAnswered = nil
        startedAt = now
        roundBeganAt = now
        finishedAt = now
        let previousFirst = defaults.string(forKey: Self.lastFirstWordKey)
        queue = switch plan {
        case .weak:
            ordered(words.filter { $0.isWeak(at: now) }, now: now, avoidingFirst: previousFirst)
        case .daily:
            // Önce çalışılmış zayıflar, kalan yere yeniler; kartta yazan dağılımla aynı olsun diye.
            dailyWords(words, now: now, avoidingFirst: previousFirst)
        case .extraPractice:
            ordered(Self.weakest(words, count: Self.extraPracticeCount, now: now), now: now, avoidingFirst: previousFirst)
        case .quick:
            ordered(words, now: now, avoidingFirst: previousFirst, limit: Self.quickCount)
        case .reverse:
            ordered(words, now: now, avoidingFirst: previousFirst, limit: Self.reverseCount)
        }
        if let first = queue.first {
            defaults.set(Self.key(for: first), forKey: Self.lastFirstWordKey)
        }
        wordCount = queue.count
        finishedWordCount = 0
        advance(now: now)
    }

    private func dailyWords(_ words: [Word], now: Date, avoidingFirst previousFirst: String?) -> [Word] {
        let count = Self.dailyCount(words, now: now)
        let weak = ordered(words.filter { !$0.isNew && $0.isWeak(at: now) }, now: now, limit: count.weak)
        let new = ordered(words.filter(\.isNew), now: now, limit: count.new)
        return ordered(weak + new, now: now, avoidingFirst: previousFirst)
    }

    /// Hafızası en düşük kelimeler; yeniler en başta.
    static func weakest(_ words: [Word], count: Int, now: Date) -> [Word] {
        Array(words.sorted { ($0.memory(at: now) ?? -1) < ($1.memory(at: now) ?? -1) }.prefix(count))
    }

    /// Günlük Tekrar turuna girecek kelime sayısı: çalışılmış zayıflar ve (en fazla 5) yeni, toplam en fazla 20.
    static func dailyCount(_ words: [Word], now: Date = .now) -> (weak: Int, new: Int) {
        dailyCount(weak: words.count { !$0.isNew && $0.isWeak(at: now) }, new: words.count(where: \.isNew))
    }

    /// Aynı sınır yalnızca sayılarla; bildirim ve rozet de Günlük Tekrar'ın soracağı sayıyı gösterir.
    nonisolated static func dailyCount(weak: Int, new: Int) -> (weak: Int, new: Int) {
        let takenNew = min(new, dailyNewLimit, max(0, dailyLimit - min(weak, dailyLimit)))
        return (min(weak, dailyLimit), takenNew)
    }

    func reveal(answer: String?, now: Date = .now) {
        guard let word = current, phase == .asking else { return }
        responseTime = now.timeIntervalSince(shownAt)
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            phase = .revealed(.peeked)
        } else if isReverse {
            let verdict: Verdict = switch ReverseChecker.check(trimmed, expected: word.english) {
            case .exact: .correct
            case .typo: .almost
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
        guard committed == nil, let word = current, !word.isDeleted, let known = pendingKnown else { return }
        let before = (word.stability, word.difficulty, word.dueDate, word.lastReviewedAt, word.reviewCount, word.correctCount)
        let entryCount = roundEntries.count
        let finishedBefore = finishedAt
        let answeredBefore = memoryAnsweredAt
        let lastBefore = lastAnswered
        let log = record(word, known: known, now: now)
        committed = Committed(known: known) { [weak self] in
            (word.stability, word.difficulty, word.dueDate, word.lastReviewedAt, word.reviewCount, word.correctCount) = before
            if let log { log.modelContext?.delete(log) }
            self?.roundEntries.removeSubrange(entryCount...)
            self?.finishedAt = finishedBefore
            self?.memoryAnsweredAt = answeredBefore
            self?.lastAnswered = lastBefore
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

    func grade(known: Bool, now: Date = .now) {
        guard let word = current else { return }
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
                record(word, known: known, now: now)
            }
        } else {
            record(word, known: known, now: now)
        }
        // Bilinmeyen kelime bilinene kadar yeniden sorulur; hemen arkasından değil,
        // arada en az iki kelime olacak şekilde.
        if known {
            finishedWordCount += 1
        } else {
            queue.insert(word, at: WordPicker.reinsertionIndex(queueCount: queue.count))
        }
        reviewedCount += 1
        advance(now: now)
    }

    @discardableResult
    private func record(_ word: Word, known: Bool, now: Date) -> ReviewLog? {
        let verdict: Verdict = if case .revealed(let verdict) = phase { verdict } else { .peeked }
        let grade = AnswerGrade.recall(verdict: verdict, known: known, responseTime: responseTime)
        // Eski biçimli kelimenin önceki hafızası "Yeni" görünmesin.
        MemoryMigration.migrate(word)
        // Hafızayı turdaki ilk cevap değiştirir; sonrakiler yalnızca geçmişe yazılır. Tur günlerce
        // açık kalmışsa kelimenin başka bir gündeki ilk cevabı da ilk cevap sayılır.
        let id = ObjectIdentifier(word)
        let isFirstAnswer = memoryAnsweredAt[id].map { !Calendar.current.isDate($0, inSameDayAs: now) } ?? true
        if !roundEntries.contains(where: { $0.word === word }) {
            roundEntries.append(RoundEntry(word: word, memoryBefore: word.memory(at: now), firstCorrect: grade.isCorrect))
        }
        if isFirstAnswer { memoryAnsweredAt[id] = now }
        // Yanlış bilinip hemen arkasından (arada başka kart olmadan) doğru bilinen kelime zayıf kalır:
        // az önce gördüğü cevabı yazmak kelimeyi bildiğini göstermez.
        let clearsLapse = lastAnswered !== word
        lastAnswered = word
        finishedAt = now
        return ReviewRecorder.record(
            word, grade: grade, mode: mode, responseTime: responseTime, updatesMemory: isFirstAnswer,
            clearsLapse: clearsLapse, now: now
        )
    }

    /// Kelime listesi dışarıda değiştiğinde (silme, yeni kelime, iCloud'dan gelen değişiklik)
    /// ya da zaman geçtiğinde sırayı onunla uyumlu tutar: silinenler çıkar, zayıflamış
    /// ama sırada olmayanlar sona eklenir. Tur bitmişse yeni gelenlerle devam eder.
    ///
    /// Yalnızca `.weak` turunda yeni zayıflayanlar eklenir; diğer turların kelimeleri baştan bellidir.
    func sync(with words: [Word], now: Date = .now) {
        for word in words { MemoryMigration.migrate(word) }
        let alive = Set(words.map(\.persistentModelID))
        let queuedBefore = queue.count
        queue.removeAll { !alive.contains($0.persistentModelID) }
        wordCount -= queuedBefore - queue.count
        let currentDeleted = current.map { !alive.contains($0.persistentModelID) } ?? false
        if currentDeleted { wordCount -= 1 }
        guard plan == .weak else {
            if currentDeleted { advance(now: now) }
            return
        }

        // Bu turda bilinenlerin hafızası güçlendiği için tekrar eklenmezler.
        let queued = Set(queue.map(\.persistentModelID) + [current?.persistentModelID].compactMap { $0 })
        let added = ordered(words.filter { $0.isWeak(at: now) && !queued.contains($0.persistentModelID) }, now: now)
        queue += added
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
        current = queue.isEmpty ? nil : queue.removeFirst()
        phase = .asking
        shownAt = now
        // Duraklatılmışken (pencere kapalı) ilerlenirse saat duraklatılmış kalır; yeni kart şimdiden sayılır.
        if pausedAt != nil { pausedAt = now }
        committed = nil
        responseTime = 0
    }
}
