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

    nonisolated static let dailyLimit = 20
    nonisolated static let dailyNewLimit = 5
    nonisolated static let recentLimit = 10
    nonisolated static let quickCount = 5
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
        self.words = words
        startedAt = now
        roundBeganAt = now
        finishedAt = now
        let previousFirst = defaults.string(forKey: Self.lastFirstWordKey)
        queue = switch plan {
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
        if let first = queue.first {
            defaults.set(Self.key(for: first), forKey: Self.lastFirstWordKey)
        }
        wordCount = queue.count
        finishedWordCount = 0
        advance(now: now)
    }

    private func dailyWords(_ words: [Word], now: Date, avoidingFirst previousFirst: String?) -> [Word] {
        let count = Self.dailyCount(words, now: now)
        let weak = ordered(words.filter { !$0.isNew && $0.isDue(at: now) }, now: now, limit: count.weak)
        return ordered(weak + Self.dailyNewWords(words, now: now), now: now, avoidingFirst: previousFirst)
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
    static func dailyCount(_ words: [Word], now: Date = .now) -> (weak: Int, new: Int) {
        dailyCount(
            weak: words.count { !$0.isNew && $0.isDue(at: now) }, new: words.count(where: \.isNew),
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
        guard let word = current, phase == .asking else { return }
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
        guard committed == nil, let word = current, !word.isDeleted, let known = pendingKnown else { return }
        let entryCount = roundEntries.count
        let finishedBefore = finishedAt
        let log = record(word, known: known, now: now)
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
        // Bilinmeyen kelime bilinene kadar yeniden sorulur; hemen arkasından değil, arada en az iki
        // kelime olacak şekilde. O kadar kelime kalmadıysa yeniden sorulmaz, turdan çıkar.
        if !known, let index = WordPicker.reinsertionIndex(queueCount: queue.count) {
            queue.insert(word, at: index)
        } else {
            finishedWordCount += 1
        }
        reviewedCount += 1
        advance(now: now)
    }

    @discardableResult
    private func record(_ word: Word, known: Bool, now: Date) -> ReviewLog? {
        let verdict: Verdict = if case .revealed(let verdict) = phase { verdict } else { .peeked }
        let letters = (isReverse ? word.english : word.turkish).count(where: \.isLetter)
        let grade = AnswerGrade.recall(verdict: verdict, known: known, responseTime: responseTime, letters: letters)
        // Eski biçimli kelimenin önceki durumu "Yeni" görünmesin.
        MemoryMigration.migrate(word)
        // Tur özeti turdaki ilk cevaba bakar; aynı gündeki bütün cevaplar motorda birlikte değerlendirilir.
        if !roundEntries.contains(where: { $0.word === word }) {
            roundEntries.append(RoundEntry(before: word, firstCorrect: grade.isCorrect))
        }
        finishedAt = now
        return ReviewRecorder.record(word, grade: grade, mode: mode, responseTime: responseTime, now: now)
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
        let added = ordered(words.filter { $0.isDue(at: now) && !queued.contains($0.persistentModelID) }, now: now)
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
