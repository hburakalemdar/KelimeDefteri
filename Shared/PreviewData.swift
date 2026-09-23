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
        let ddia = "Designing Data-Intensive Applications"
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

        // (kelime, eski kutu, sıradaki tekrar, eklenme, tekrar, doğru); hafıza değerleri geçişle hesaplanır.
        let samples: [(Word, Int, Date, Date, Int, Int)] = [
            (Word(english: "idempotent", turkish: "tekrarlanabilir, etkisi değişmeyen",
                  definition: "gives the same result no matter how many times it is applied",
                  example: "Retries are safe only if the operation is idempotent.", source: ddia),
             1, day(-1), day(-6), 4, 2),
            (Word(english: "throughput", turkish: "iş hacmi, verim",
                  example: "Batching requests increased throughput but also latency.", source: ddia),
             0, .distantPast, now, 0, 0),
            (Word(english: "stale", turkish: "eskimiş, güncel olmayan",
                  definition: "no longer fresh or up to date",
                  example: "A follower replica may return stale data.", source: ddia),
             2, day(-20), day(-30), 5, 4),
            (Word(english: "quorum", turkish: "yeter sayı, çoğunluk",
                  example: "Writes must be acknowledged by a quorum of nodes.", source: ddia),
             3, day(4), day(-20), 6, 5),
            (Word(english: "coalesce", turkish: "birleştirmek, kaynaştırmak",
                  example: "The scheduler coalesces adjacent timers to save power.", source: "The Linux Programming Interface"),
             5, day(30), day(-60), 9, 8),
            (Word(english: "backpressure", turkish: "geri basınç, akış kısıtlama",
                  example: "Without backpressure, a fast producer overwhelms the consumer.", source: "Reactive Design Patterns"),
             1, day(1), day(-2), 1, 1),
            (Word(english: "tombstone", turkish: "silinme işareti",
                  definition: "a marker indicating that a record was deleted",
                  example: "Deletions are recorded as tombstones until compaction.", source: ddia),
             4, day(12), day(-30), 7, 6),
            (Word(english: "linearizable", turkish: "doğrusallaştırılabilir",
                  example: "A linearizable register behaves as if there were a single copy.", source: ddia),
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
        return container
    }()
}
#endif
