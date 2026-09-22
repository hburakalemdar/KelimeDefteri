#if DEBUG
import SwiftData

/// Xcode önizlemeleri için bellek içi örnek veri. Uygulamaya dahil edilmez.
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Word.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let samples = [
            Word(english: "idempotent", turkish: "tekrarlanabilir, etkisi değişmeyen",
                 definition: "gives the same result no matter how many times it is applied",
                 example: "Retries are safe only if the operation is idempotent.",
                 source: "Designing Data-Intensive Applications"),
            Word(english: "throughput", turkish: "iş hacmi, verim",
                 example: "Batching requests increased throughput but also latency."),
            Word(english: "stale", turkish: "eskimiş, güncel olmayan",
                 example: "A follower replica may return stale data."),
        ]
        samples.forEach { container.mainContext.insert($0) }
        return container
    }()
}
#endif
