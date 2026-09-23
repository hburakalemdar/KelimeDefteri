#if DEBUG
import Foundation
import SwiftData

/// Xcode önizlemeleri ve `-demo` ile açılan ekran görüntüsü oturumu için geçici örnek veri.
/// Uygulamanın yayın sürümüne dahil edilmez.
enum PreviewData {
    static let container: ModelContainer = {
        // Bellek içi depo, uygulama ön plana gelirken yapılan otomatik kayıtta çöküyordu;
        // her açılışta yeni bir geçici dosya kullan.
        let url = URL.temporaryDirectory.appending(path: "demo-\(UUID().uuidString).store")
        let container = try! ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

        // (kelime, eski kutu, sıradaki tekrar, eklenme, tekrar, doğru); hafıza değerleri geçişle hesaplanır.
        let samples: [(Word, Int, Date, Date, Int, Int)] = [
            (Word(english: "idempotent", turkish: "tekrarlanabilir, etkisi değişmeyen",
                  example: "Retries are safe only if the operation is idempotent."),
             1, day(-1), day(-6), 4, 2),
            (Word(english: "throughput", turkish: "iş hacmi, verim",
                  example: "Batching requests increased throughput but also latency."),
             0, .distantPast, now, 0, 0),
            (Word(english: "stale", turkish: "eskimiş, güncel olmayan",
                  example: "A follower replica may return stale data."),
             2, day(-20), day(-30), 5, 4),
            (Word(english: "quorum", turkish: "yeter sayı, çoğunluk",
                  example: "Writes must be acknowledged by a quorum of nodes."),
             3, day(4), day(-20), 6, 5),
            (Word(english: "coalesce", turkish: "birleştirmek, kaynaştırmak",
                  example: "The scheduler coalesces adjacent timers to save power."),
             5, day(30), day(-60), 9, 8),
            (Word(english: "backpressure", turkish: "geri basınç, akış kısıtlama",
                  example: "Without backpressure, a fast producer overwhelms the consumer."),
             1, day(1), day(-2), 1, 1),
            (Word(english: "tombstone", turkish: "silinme işareti",
                  example: "Deletions are recorded as tombstones until compaction."),
             4, day(12), day(-30), 7, 6),
            (Word(english: "linearizable", turkish: "doğrusallaştırılabilir",
                  example: "A linearizable register behaves as if there were a single copy."),
             0, .distantPast, now.addingTimeInterval(-600), 0, 0),
        ]
        for (word, box, due, created, reviews, correct) in samples {
            word.box = box
            word.dueDate = due
            word.createdAt = created
            word.reviewCount = reviews
            word.correctCount = correct
            container.mainContext.insert(word)
        }
        MemoryMigration.migrateIfNeeded(context: container.mainContext)

        // Ayrıntı sayfasındaki geçmiş için örnek cevaplar: önce yanlışlar, sonra doğrular.
        let modes: [GameMode] = [.dailyReview, .dailyReview, .match, .multipleChoice, .dailyReview, .quickRound]
        for (word, _, _, _, reviews, correct) in samples where reviews > 0 {
            let last = word.lastReviewedAt ?? now
            for index in 0..<reviews {
                let mode = modes[index % modes.count]
                let log = ReviewLog(
                    date: last.addingTimeInterval(-Double(reviews - 1 - index) * 2 * 86_400),
                    mode: mode.rawValue,
                    correct: index >= reviews - correct,
                    grade: index >= reviews - correct ? 3 : 1,
                    responseTime: mode == .match ? 0 : Double(3 + index % 5)
                )
                container.mainContext.insert(log)
                log.word = word
            }
        }
        return container
    }()
}
#endif
