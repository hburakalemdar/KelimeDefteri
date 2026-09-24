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
    private var pausedAt: Date?
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
    /// `conflicts` verilirse seçilmiş bir kelimeyle çakışan kelime alınmaz (ör. Eşleştir'de ortak anlam).
    func start(with pool: [Word], count: Int, conflicts: ((Word, Word) -> Bool)? = nil, now: Date = .now) {
        let candidates = pool.indices.map { index in
            let memory = pool[index].memory(at: now)
            return WordPicker.Candidate(id: index, weight: WordPicker.weight(memory: memory), isNew: memory == nil)
        }
        let previous = defaults.string(forKey: StudySession.lastFirstWordKey)
        let avoided = previous.flatMap { key in pool.firstIndex { AnswerChecker.fold($0.english) == key } }
        let ordered = WordPicker.order(candidates, limit: conflicts == nil ? count : nil, avoidingFirst: avoided, using: &generator)
            .map { pool[$0] }
        if let conflicts {
            var picked: [Word] = []
            for word in ordered where picked.count < count && !picked.contains(where: { conflicts($0, word) }) {
                picked.append(word)
            }
            words = picked
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
        // Duraklatılmışken başlatılırsa saat duraklatılmış kalır.
        if pausedAt != nil { pausedAt = now }
    }

    /// Şu anki kelimenin cevabını kaydeder. Aynı kelime turda ikinci kez cevaplanırsa özet ilk cevabı tutar;
    /// aynı gündeki bütün cevaplar motorda birlikte değerlendirilir (günün notu).
    /// `timed` false ise (ör. Eşleştir) cevap süresi kaydedilmez. `mode` verilirse cevap o oyun adına
    /// (ve o oyunun ağırlığıyla) kaydedilir; karışık Hızlı Tur her soruyu kendi türüyle yazar.
    func record(_ word: Word, grade: AnswerGrade, mode: GameMode? = nil, timed: Bool = true, now: Date = .now) {
        guard !word.isDeleted else { return }
        // Eski biçimli kelimenin önceki durumu "Yeni" görünmesin.
        MemoryMigration.migrate(word)
        if !entries.contains(where: { $0.word === word }) {
            entries.append(StudySession.RoundEntry(before: word, firstCorrect: grade.isCorrect))
        }
        ReviewRecorder.record(
            word, grade: grade, mode: mode ?? self.mode,
            responseTime: timed ? now.timeIntervalSince(shownAt) : 0, now: now
        )
        finishedAt = now
    }

    /// Başka bir oturumun (ör. hatırlama sorusu) kaydettiği cevabı tur özetine ekler.
    func adopt(_ entry: StudySession.RoundEntry, now: Date = .now) {
        if !entries.contains(where: { $0.word === entry.word }) { entries.append(entry) }
        finishedAt = now
    }

    /// Uygulama arka plandayken geçen süre cevap süresine sayılmaz.
    func pauseClock(now: Date = .now) {
        if pausedAt == nil { pausedAt = now }
    }

    /// Tur sürüyorsa arka planda geçen süre tur süresine (ve Eşleştir sayacına) de sayılmaz.
    func resumeClock(now: Date = .now) {
        guard let pausedAt else { return }
        let paused = now.timeIntervalSince(pausedAt)
        shownAt += paused
        if !words.isEmpty && !isFinished { startedAt += paused }
        self.pausedAt = nil
    }

    /// Soru sırası olmayan oyunlarda (Eşleştir) turu bitirir.
    func finish() {
        index = words.count
    }

    func advance(now: Date = .now) {
        index += 1
        shownAt = now
        if pausedAt != nil { pausedAt = now }
    }
}
