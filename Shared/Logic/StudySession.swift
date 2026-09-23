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

    private(set) var current: Word?
    private(set) var phase: Phase = .asking
    private(set) var isPracticeAll = false
    private(set) var reviewedCount = 0
    private var queue: [Word] = []
    private var generator: SeededGenerator
    private let defaults: UserDefaults

    /// Önceki turun ilk kelimesi; yeni tur onunla başlamasın diye saklanır.
    static let lastFirstWordKey = "StudySession.lastFirstWord"

    var remaining: Int { queue.count }

    /// `seed` testte sırayı sabitlemek için; verilmezse her açılışta farklı sıra çıkar.
    init(seed: UInt64 = .random(in: .min ... .max), defaults: UserDefaults = .standard) {
        generator = SeededGenerator(seed: seed)
        self.defaults = defaults
    }

    /// `practiceAll` false ise sadece zamanı gelenler, true ise tüm kelimeler sorulur.
    /// Sıra karışıktır; tekrara en çok ihtiyacı olan kelime öne gelme eğilimindedir.
    func start(with words: [Word], practiceAll: Bool, now: Date = .now) {
        isPracticeAll = practiceAll
        reviewedCount = 0
        let pool = practiceAll ? words : words.filter { $0.isDue(at: now) }
        queue = ordered(pool, now: now, avoidingFirst: defaults.string(forKey: Self.lastFirstWordKey))
        if let first = queue.first {
            defaults.set(Self.key(for: first), forKey: Self.lastFirstWordKey)
        }
        advance()
    }

    func reveal(answer: String?) {
        guard let word = current, phase == .asking else { return }
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            phase = .revealed(.peeked)
        } else {
            phase = .revealed(AnswerChecker.isCorrect(trimmed, expected: word.turkish) ? .correct : .incorrect)
        }
    }

    func grade(known: Bool, now: Date = .now) {
        guard let word = current else { return }
        let result = Leitner.review(box: word.box, known: known, now: now)
        word.box = result.box
        word.dueDate = result.due
        word.reviewCount += 1
        if known { word.correctCount += 1 }
        // Bilinmeyen kelime bilinene kadar yeniden sorulur; hemen arkasından değil,
        // arada en az iki kelime olacak şekilde.
        if !known { queue.insert(word, at: WordPicker.reinsertionIndex(queueCount: queue.count)) }
        reviewedCount += 1
        advance()
    }

    /// Kelime listesi dışarıda değiştiğinde (silme, yeni kelime, iCloud'dan gelen değişiklik)
    /// ya da gün döndüğünde sırayı onunla uyumlu tutar: silinenler çıkar, zamanı gelmiş
    /// ama sırada olmayanlar sona eklenir. Tur bitmişse yeni gelenlerle devam eder.
    func sync(with words: [Word], now: Date = .now) {
        let alive = Set(words.map(\.persistentModelID))
        queue.removeAll { !alive.contains($0.persistentModelID) }

        // Bu turda "Bildim" denenlerin tarihi ileri alındığı için tekrar eklenmezler.
        let queued = Set(queue.map(\.persistentModelID) + [current?.persistentModelID].compactMap { $0 })
        queue += ordered(words.filter { $0.isDue(at: now) && !queued.contains($0.persistentModelID) }, now: now)

        if let current, alive.contains(current.persistentModelID) { return }
        advance()
    }

    private func ordered(_ words: [Word], now: Date, avoidingFirst previousFirst: String? = nil) -> [Word] {
        // Aynı yazılışlı iki kayıt olabilir; kimlik olarak dizideki yer kullanılır.
        let candidates = words.indices.map { index in
            let word = words[index]
            let isNew = word.reviewCount == 0
            return WordPicker.Candidate(
                id: index,
                weight: WordPicker.delayWeight(dueDate: word.dueDate, isNew: isNew, now: now),
                isNew: isNew
            )
        }
        let avoided = previousFirst.flatMap { key in words.firstIndex { Self.key(for: $0) == key } }
        return WordPicker.order(candidates, avoidingFirst: avoided, using: &generator).map { words[$0] }
    }

    private static func key(for word: Word) -> String { AnswerChecker.fold(word.english) }

    private func advance() {
        current = queue.isEmpty ? nil : queue.removeFirst()
        phase = .asking
    }
}
