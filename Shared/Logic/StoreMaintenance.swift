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

    /// Sahipsiz cevap kaydı ancak bu kadar süre sonra hâlâ sahipsizse silinir: iCloud bir cevap
    /// kaydını kelimesinden önce getirebilir, ilk görüşte silmek onu kaybettirir.
    static let orphanGracePeriod: TimeInterval = 60 * 60
    static let orphanDefaultsKey = "StoreMaintenance.orphanLogs"

    /// Sahipsiz görülen cevap kaydı ve ilk görüldüğü zaman. Kayıt, kimliğinin JSON kodlamasıyla tutulur;
    /// çözülen `PersistentIdentifier` depodakine her zaman eşit çıkmadığı için karşılaştırma metinle yapılır.
    struct OrphanSighting: Codable {
        var id: String
        var firstSeen: Date
    }

    private static func key(for id: PersistentIdentifier) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(id)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Bakımı yapar; değişiklik olduysa kaydeder (hata günlüğe yazılır).
    ///
    /// Sahipsiz cevap kayıtları iki aşamada silinir: ilk görüşte `defaults`'a not edilir; sonraki
    /// çalışmada en az `orphanGracePeriod` önce de sahipsiz görülmüş ve hâlâ sahipsizse silinir.
    @MainActor @discardableResult
    static func run(in context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) -> Summary {
        var summary = Summary()
        do {
            let words = try context.fetch(FetchDescriptor<Word>())
            for group in duplicateGroups(words) {
                merge(group, now: now)
                summary.mergedWords += group.count - 1
            }

            // Kelimesi olmayan cevap kayıtları (birleştirmede taşınanlar artık sahipli).
            let orphans = try context.fetch(FetchDescriptor<ReviewLog>()).filter { $0.word == nil }
            let seen = Dictionary(
                loadSightings(defaults).map { ($0.id, $0.firstSeen) },
                uniquingKeysWith: { min($0, $1) }
            )
            var pending: [OrphanSighting] = []
            for log in orphans {
                guard let id = key(for: log.persistentModelID) else { continue }
                if let firstSeen = seen[id], now.timeIntervalSince(firstSeen) >= orphanGracePeriod {
                    context.delete(log)
                    summary.removedLogs += 1
                } else {
                    // Artık sahipsiz olmayanlar listeye yeniden girmez, kendiliğinden düşer.
                    pending.append(OrphanSighting(id: id, firstSeen: seen[id] ?? now))
                }
            }

            if summary.changed { try context.save() }
            saveSightings(pending, to: defaults)
        } catch {
            SharedStore.logger.error("Depo bakımı yapılamadı: \(String(describing: error), privacy: .public)")
        }
        return summary
    }

    private static func loadSightings(_ defaults: UserDefaults) -> [OrphanSighting] {
        guard let data = defaults.data(forKey: orphanDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([OrphanSighting].self, from: data)) ?? []
    }

    private static func saveSightings(_ sightings: [OrphanSighting], to defaults: UserDefaults) {
        if sightings.isEmpty {
            defaults.removeObject(forKey: orphanDefaultsKey)
        } else if let data = try? JSONEncoder().encode(sightings) {
            defaults.set(data, forKey: orphanDefaultsKey)
        }
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
    private static func merge(_ group: [Word], now: Date) {
        guard let keeper = group.first else { return }
        let others = group.dropFirst()

        // Hafıza tabandan ve cevap kayıtlarından yeniden hesaplanır (SPEC-MOTOR2 §6). Taban: dolu tabanlar
        // (`baseAt` gerçek bir an) arasından `baseAt`i en eski olan (daha geniş bir cevap aralığını kapsar);
        // eşitse sıradaki ilk kayıt. Boş taban (`.distantPast`, hiç cevaplanmamış kopya) yalnızca dolu taban
        // yoksa seçilir; yoksa eski sürümde çalışılmış kopyanın saklı hafızası kaybolurdu. Hiçbiri göç
        // kontrolünden geçmediyse (`nil`) kalan kayıt bir sonraki göçte ele alınır.
        let filled = group.filter { $0.baseAt.map { $0 != .distantPast } ?? false }
        let baseSource = filled.reduce(nil as Word?) { best, word in
            guard let best, let bestAt = best.baseAt else { return word }
            return word.baseAt! < bestAt ? word : best
        } ?? group.first { $0.baseAt == .distantPast }
        if let baseSource, baseSource !== keeper {
            copyBase(from: baseSource, to: keeper)
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
        MemoryCache.refresh(keeper, now: now)
    }

    @MainActor
    private static func copyBase(from source: Word, to target: Word) {
        target.baseStability = source.baseStability
        target.baseDifficulty = source.baseDifficulty
        target.baseDueDate = source.baseDueDate
        target.baseLapsedAt = source.baseLapsedAt
        target.baseAnchorAt = source.baseAnchorAt
        target.baseLearnedAt = source.baseLearnedAt
        target.baseAt = source.baseAt
    }
}
