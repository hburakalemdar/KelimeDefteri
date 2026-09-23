import Foundation
import SwiftData

/// Uygulama öne gelince çalışan depo bakımı: çift kayıtları birleştirir, sahipsiz cevap kayıtlarını siler.
///
/// Aynı İngilizce kelime iki cihazda eşitlenmeden eklenirse iCloud'dan iki kayıt gelir. Birleştirme
/// deterministiktir: iki cihaz aynı kayıtları gördüğünde aynı sonucu üretir.
nonisolated enum StoreMaintenance {
    struct Summary: Equatable {
        /// Silinen (başka kayda katılan) kelime sayısı.
        var mergedWords = 0
        /// Silinen sahipsiz cevap kaydı sayısı.
        var removedLogs = 0

        var changed: Bool { mergedWords > 0 || removedLogs > 0 }
    }

    /// Bakımı yapar; değişiklik olduysa kaydeder (hata günlüğe yazılır).
    @MainActor @discardableResult
    static func run(in context: ModelContext) -> Summary {
        var summary = Summary()
        do {
            let words = try context.fetch(FetchDescriptor<Word>())
            for group in duplicateGroups(words) {
                merge(group)
                summary.mergedWords += group.count - 1
            }
            // Kelimesi silinmiş cevap kayıtları (birleştirmede taşınanlar artık sahipli).
            let orphans = try context.fetch(FetchDescriptor<ReviewLog>()).filter { $0.word == nil }
            for log in orphans { context.delete(log) }
            summary.removedLogs = orphans.count

            if summary.changed { try context.save() }
        } catch {
            SharedStore.logger.error("Depo bakımı yapılamadı: \(String(describing: error), privacy: .public)")
        }
        return summary
    }

    /// `WordMatcher.isSame` ile eşleşen, birden fazla kayıtlı gruplar; her grup kalacak kayıt başta olacak
    /// şekilde sıralı (en eski `createdAt`, eşitse İngilizce yazılış, sonra kayıt kimliği).
    @MainActor
    static func duplicateGroups(_ words: [Word]) -> [[Word]] {
        let groups = Dictionary(grouping: words.filter { !AnswerChecker.fold($0.english).isEmpty }) {
            AnswerChecker.fold($0.english)
        }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], group.count > 1 else { return nil }
            return group.sorted(by: comesFirst)
        }
    }

    @MainActor
    private static func comesFirst(_ a: Word, _ b: Word) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        if a.english != b.english { return a.english < b.english }
        return a.persistentModelID < b.persistentModelID
    }

    /// Grubu ilk kayıtta toplar, ötekileri siler.
    @MainActor
    private static func merge(_ group: [Word]) {
        guard let keeper = group.first else { return }
        let others = group.dropFirst()

        // Hafıza, en son çalışılan kayıttan gelir; hiçbiri çalışılmadıysa kalan kayıttaki durur.
        // Eşit tarihte sıradaki ilk kayıt seçilir.
        let latest = group
            .filter { $0.lastReviewedAt != nil }
            .reduce(nil as Word?) { best, word in
                guard let best, let bestDate = best.lastReviewedAt else { return word }
                return word.lastReviewedAt! > bestDate ? word : best
            }
        if let latest, latest !== keeper {
            keeper.stability = latest.stability
            keeper.difficulty = latest.difficulty
            keeper.dueDate = latest.dueDate
            keeper.lastReviewedAt = latest.lastReviewedAt
        }

        for other in others {
            keeper.turkish = WordMatcher.mergedMeanings(existing: keeper.turkish, adding: other.turkish)
            if keeper.example.isEmpty { keeper.example = other.example }
            keeper.reviewCount += other.reviewCount
            keeper.correctCount += other.correctCount
            // Kayıt silinince cevapları da silinir (cascade); önce kalan kayda taşı.
            for log in other.logs ?? [] { log.word = keeper }
            other.modelContext?.delete(other)
        }
    }
}
