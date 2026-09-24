import CoreData
import Foundation
import SwiftData

/// `Word` üzerindeki hafıza alanlarını `Memory.replay`den yeniden hesaplar (SPEC-MOTOR2 §2.9).
///
/// Cevap kaydedilince yalnızca o kelime; uygulama öne gelince, Mac pencereleri açılınca ve iCloud'dan
/// değişiklik gelince bütün defter. Alanlar yalnızca hesaplanan değer farklıysa yazılır; gereksiz
/// iCloud yazımı ve çakışma olmasın diye.
enum MemoryCache {
    /// Kelimeyi önce (gerekirse) göçten geçirir, sonra cevap kayıtlarından yeniden hesaplar.
    /// `logs` verilmezse kelimenin kendi kayıtları okunur. Bir alan değiştiyse `true`.
    @discardableResult
    static func refresh(_ word: Word, logs: [ReviewLog]? = nil, now: Date = .now) -> Bool {
        guard !word.isDeleted else { return false }
        MemoryMigration.migrateBaseIfNeeded(word, now: now)
        let answers = (logs ?? word.logs ?? [])
            .filter { !$0.isDeleted }
            .map { Memory.Answer(date: $0.date, mode: $0.mode, correct: $0.correct, grade: $0.grade) }
        let state = Memory.replay(base: MemoryMigration.base(of: word), answers: answers, now: now)
        return apply(state, to: word)
    }

    /// Bütün defteri yeniden hesaplar: cevap kayıtları tek sorguyla çekilip kelimeye göre gruplanır.
    /// Değişiklik olduysa kaydeder; değişen kelime sayısını döner.
    @discardableResult
    static func refreshAll(in context: ModelContext, now: Date = .now) -> Int {
        guard let words = try? context.fetch(FetchDescriptor<Word>()),
              let logs = try? context.fetch(FetchDescriptor<ReviewLog>()) else { return 0 }
        var byWord: [PersistentIdentifier: [ReviewLog]] = [:]
        for log in logs {
            guard let word = log.word else { continue }
            byWord[word.persistentModelID, default: []].append(log)
        }
        var changed = 0
        for word in words where !word.isDeleted {
            let before = word.baseAt
            if refresh(word, logs: byWord[word.persistentModelID] ?? [], now: now) || before != word.baseAt {
                changed += 1
            }
        }
        if changed > 0 { context.saveLogging() }
        return changed
    }

    private static func apply(_ state: Memory.State, to word: Word) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Word, T>, _ value: T) {
            if word[keyPath: keyPath] != value {
                word[keyPath: keyPath] = value
                changed = true
            }
        }
        set(\.stability, state.stability)
        set(\.difficulty, state.difficulty)
        set(\.dueDate, state.dueDate)
        set(\.lastReviewedAt, state.anchorAt)
        set(\.lapsedAt, state.lapsedAt)
        set(\.learnedAt, state.learnedAt)
        return changed
    }

    // MARK: - iCloud'dan gelen değişiklikler

    private static weak var observedContext: ModelContext?
    private static var observer: NSObjectProtocol?
    private static var pending: Task<Void, Never>?

    /// Depo başka yerden (iCloud içe aktarımı, paylaşım eklentisi, widget) değişince bütün defteri
    /// yeniden hesaplar. Yalnızca uygulamalarda kurulur (`SharedStore.result`), eklenti ve widget'ta değil.
    static func observeRemoteChanges(context: ModelContext) {
        observedContext = context
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in scheduleRefresh() }
        }
    }

    /// Art arda gelen bildirimleri tek hesaba indirir.
    private static func scheduleRefresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let context = observedContext else { return }
            refreshAll(in: context)
        }
    }
}
