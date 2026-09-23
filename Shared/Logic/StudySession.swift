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

    static let dailyLimit = 20
    static let dailyNewLimit = 5
    static let quickCount = 5
    static let reverseCount = 10

    /// Kelimeler güçlüyken "Yine de Çalış" ile açılan turdaki kelime sayısı.
    static let extraPracticeCount = 10

    private(set) var current: Word?
    private(set) var phase: Phase = .asking
    private(set) var plan: Plan = .weak
    private(set) var reviewedCount = 0
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
        self.plan = plan
        reviewedCount = 0
        roundEntries = []
        startedAt = now
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
        let weak = words.count { !$0.isNew && $0.isWeak(at: now) }
        let new = words.count(where: \.isNew)
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
        guard case .revealed(let verdict) = phase, verdict != .peeked,
              let option = verdict.gradeOptions.first(where: \.isPrimary) else { return }
        grade(known: option.known, now: now)
    }

    /// Uygulama arka plandayken geçen süre cevap süresine sayılmaz.
    func pauseClock(now: Date = .now) {
        if pausedAt == nil { pausedAt = now }
    }

    func resumeClock(now: Date = .now) {
        guard let pausedAt else { return }
        shownAt += now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    func grade(known: Bool, now: Date = .now) {
        guard let word = current else { return }
        let verdict: Verdict = if case .revealed(let verdict) = phase { verdict } else { .peeked }
        let grade = AnswerGrade.recall(verdict: verdict, known: known, responseTime: responseTime)
        if !roundEntries.contains(where: { $0.word === word }) {
            roundEntries.append(RoundEntry(word: word, memoryBefore: word.memory(at: now), firstCorrect: grade.isCorrect))
        }
        finishedAt = now
        ReviewRecorder.record(word, grade: grade, mode: mode, responseTime: responseTime, now: now)
        // Bilinmeyen kelime bilinene kadar yeniden sorulur; hemen arkasından değil,
        // arada en az iki kelime olacak şekilde.
        if !known { queue.insert(word, at: WordPicker.reinsertionIndex(queueCount: queue.count)) }
        reviewedCount += 1
        advance(now: now)
    }

    /// Kelime listesi dışarıda değiştiğinde (silme, yeni kelime, iCloud'dan gelen değişiklik)
    /// ya da zaman geçtiğinde sırayı onunla uyumlu tutar: silinenler çıkar, zayıflamış
    /// ama sırada olmayanlar sona eklenir. Tur bitmişse yeni gelenlerle devam eder.
    ///
    /// Yalnızca `.weak` turunda yeni zayıflayanlar eklenir; diğer turların kelimeleri baştan bellidir.
    func sync(with words: [Word], now: Date = .now) {
        let alive = Set(words.map(\.persistentModelID))
        queue.removeAll { !alive.contains($0.persistentModelID) }
        guard plan == .weak else {
            if let current, !alive.contains(current.persistentModelID) { advance(now: now) }
            return
        }

        // Bu turda bilinenlerin hafızası güçlendiği için tekrar eklenmezler.
        let queued = Set(queue.map(\.persistentModelID) + [current?.persistentModelID].compactMap { $0 })
        queue += ordered(words.filter { $0.isWeak(at: now) && !queued.contains($0.persistentModelID) }, now: now)

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
        pausedAt = nil
        responseTime = 0
    }
}
