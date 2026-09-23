import Foundation
import Observation

/// Soru soru ilerleyen oyunların ortak turu: kelimeleri seçer, sırayı tutar, cevapları
/// `ReviewRecorder` ile kaydeder ve tur özeti için kelime başına ilk cevabı saklar.
@Observable
final class GameRound {
    let mode: GameMode
    private(set) var words: [Word] = []
    private(set) var index = 0
    private(set) var entries: [StudySession.RoundEntry] = []
    private(set) var startedAt: Date = .now
    private(set) var finishedAt: Date = .now
    private(set) var shownAt: Date = .now
    private var generator: SeededGenerator
    private let defaults: UserDefaults

    init(mode: GameMode, seed: UInt64 = .random(in: .min ... .max), defaults: UserDefaults = .standard) {
        self.mode = mode
        generator = SeededGenerator(seed: seed)
        self.defaults = defaults
    }

    var current: Word? { words.indices.contains(index) ? words[index] : nil }
    var isFinished: Bool { !words.isEmpty && index >= words.count }
    var count: Int { words.count }

    /// Oyunlar kendi rastgele kararları (seçenek, harf sırası) için de bu üreteci kullanır; testte sabit sonuç verir.
    func random<T>(_ body: (inout SeededGenerator) -> T) -> T { body(&generator) }

    /// `pool` içinden ağırlıklı `count` kelime seçer; önceki turun ilk kelimesiyle başlamaz.
    /// `distinctBy` verilirse aynı anahtarı taşıyan ikinci kelime alınmaz (ör. Eşleştir'de aynı anlam).
    func start(with pool: [Word], count: Int, distinctBy key: ((Word) -> String)? = nil, now: Date = .now) {
        let candidates = pool.indices.map { index in
            let memory = pool[index].memory(at: now)
            return WordPicker.Candidate(id: index, weight: WordPicker.weight(memory: memory), isNew: memory == nil)
        }
        let previous = defaults.string(forKey: StudySession.lastFirstWordKey)
        let avoided = previous.flatMap { key in pool.firstIndex { AnswerChecker.fold($0.english) == key } }
        let ordered = WordPicker.order(candidates, limit: key == nil ? count : nil, avoidingFirst: avoided, using: &generator)
            .map { pool[$0] }
        if let key {
            var seen: Set<String> = []
            words = Array(ordered.filter { seen.insert(key($0)).inserted }.prefix(count))
        } else {
            words = ordered
        }
        if let first = words.first {
            defaults.set(AnswerChecker.fold(first.english), forKey: StudySession.lastFirstWordKey)
        }
        index = 0
        entries = []
        startedAt = now
        finishedAt = now
        shownAt = now
    }

    /// Şu anki kelimenin cevabını kaydeder. Aynı kelime turda ikinci kez cevaplanırsa özet ilk cevabı tutar.
    /// `timed` false ise (ör. Eşleştir) cevap süresi kaydedilmez.
    func record(_ word: Word, grade: AnswerGrade, timed: Bool = true, now: Date = .now) {
        if !entries.contains(where: { $0.word === word }) {
            entries.append(StudySession.RoundEntry(word: word, memoryBefore: word.memory(at: now), firstCorrect: grade.isCorrect))
        }
        ReviewRecorder.record(word, grade: grade, mode: mode, responseTime: timed ? now.timeIntervalSince(shownAt) : 0, now: now)
        finishedAt = now
    }

    /// Soru sırası olmayan oyunlarda (Eşleştir) turu bitirir.
    func finish() {
        index = words.count
    }

    func advance(now: Date = .now) {
        index += 1
        shownAt = now
    }
}
