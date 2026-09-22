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

    var remaining: Int { queue.count }

    /// `practiceAll` false ise sadece zamanı gelenler, true ise tüm kelimeler karışık sorulur.
    func start(with words: [Word], practiceAll: Bool, now: Date = .now) {
        isPracticeAll = practiceAll
        reviewedCount = 0
        queue = practiceAll
            ? words.shuffled()
            : words.filter { $0.isDue(at: now) }.sorted { $0.dueDate < $1.dueDate }
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
        // Bilinmeyen kelime turun sonunda, bilinene kadar yeniden sorulur.
        if !known { queue.append(word) }
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
        queue += words
            .filter { $0.isDue(at: now) && !queued.contains($0.persistentModelID) }
            .sorted { $0.dueDate < $1.dueDate }

        if let current, alive.contains(current.persistentModelID) { return }
        advance()
    }

    private func advance() {
        current = queue.isEmpty ? nil : queue.removeFirst()
        phase = .asking
    }
}
