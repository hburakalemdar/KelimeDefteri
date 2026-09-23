import Foundation
import Observation

/// Bir çalışma turunun durumu: sıradaki kelimeler, gösterilen kart ve cevap.
@Observable
final class StudySession {
    enum Verdict: Equatable {
        case correct
        case incorrect
        /// Cevap yazmadan karta dokunup Türkçesine baktı.
        case peeked
    }

    enum Phase: Equatable {
        case asking
        case revealed(Verdict)
    }

    /// Kelimeler güçlüyken "Yine de Çalış" ile açılan turdaki kelime sayısı.
    static let extraPracticeCount = 10

    private(set) var current: Word?
    private(set) var phase: Phase = .asking
    private(set) var isPracticeAll = false
    private(set) var reviewedCount = 0
    /// Cevaplar hangi oyun adına kaydedilir.
    var mode: GameMode = .dailyReview
    private var queue: [Word] = []
    private var generator: SeededGenerator
    private let defaults: UserDefaults
    /// Kartın gösterildiği an ve cevabın açılmasına kadar geçen süre.
    private var shownAt: Date = .now
    private var responseTime: Double = 0

    /// Önceki turun ilk kelimesi; yeni tur onunla başlamasın diye saklanır.
    static let lastFirstWordKey = "StudySession.lastFirstWord"

    var remaining: Int { queue.count }

    /// `seed` testte sırayı sabitlemek için; verilmezse her açılışta farklı sıra çıkar.
    init(seed: UInt64 = .random(in: .min ... .max), defaults: UserDefaults = .standard) {
        generator = SeededGenerator(seed: seed)
        self.defaults = defaults
    }

    /// `practiceAll` false ise zayıf kelimeler (yeni ya da hafızası %90'ın altına inmiş),
    /// true ise en zayıf 10 kelime sorulur. Sıra karışıktır; tekrara en çok ihtiyacı olan
    /// kelime öne gelme eğilimindedir.
    func start(with words: [Word], practiceAll: Bool, now: Date = .now) {
        isPracticeAll = practiceAll
        reviewedCount = 0
        let pool = practiceAll
            ? Array(words.sorted { ($0.memory(at: now) ?? -1) < ($1.memory(at: now) ?? -1) }.prefix(Self.extraPracticeCount))
            : words.filter { $0.isWeak(at: now) }
        queue = ordered(pool, now: now, avoidingFirst: defaults.string(forKey: Self.lastFirstWordKey))
        if let first = queue.first {
            defaults.set(Self.key(for: first), forKey: Self.lastFirstWordKey)
        }
        advance(now: now)
    }

    func reveal(answer: String?, now: Date = .now) {
        guard let word = current, phase == .asking else { return }
        responseTime = now.timeIntervalSince(shownAt)
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            phase = .revealed(.peeked)
        } else {
            phase = .revealed(AnswerChecker.isCorrect(trimmed, expected: word.turkish) ? .correct : .incorrect)
        }
    }

    func grade(known: Bool, now: Date = .now) {
        guard let word = current else { return }
        let verdict: Verdict = if case .revealed(let verdict) = phase { verdict } else { .peeked }
        let grade = AnswerGrade.recall(verdict: verdict, known: known, responseTime: responseTime)
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
    func sync(with words: [Word], now: Date = .now) {
        let alive = Set(words.map(\.persistentModelID))
        queue.removeAll { !alive.contains($0.persistentModelID) }

        // Bu turda bilinenlerin hafızası güçlendiği için tekrar eklenmezler.
        let queued = Set(queue.map(\.persistentModelID) + [current?.persistentModelID].compactMap { $0 })
        queue += ordered(words.filter { $0.isWeak(at: now) && !queued.contains($0.persistentModelID) }, now: now)

        if let current, alive.contains(current.persistentModelID) { return }
        advance(now: now)
    }

    private func ordered(_ words: [Word], now: Date, avoidingFirst previousFirst: String? = nil) -> [Word] {
        // Aynı yazılışlı iki kayıt olabilir; kimlik olarak dizideki yer kullanılır.
        let candidates = words.indices.map { index in
            let memory = words[index].memory(at: now)
            return WordPicker.Candidate(id: index, weight: WordPicker.weight(memory: memory), isNew: memory == nil)
        }
        let avoided = previousFirst.flatMap { key in words.firstIndex { Self.key(for: $0) == key } }
        return WordPicker.order(candidates, avoidingFirst: avoided, using: &generator).map { words[$0] }
    }

    private static func key(for word: Word) -> String { AnswerChecker.fold(word.english) }

    private func advance(now: Date) {
        current = queue.isEmpty ? nil : queue.removeFirst()
        phase = .asking
        shownAt = now
        responseTime = 0
    }
}
