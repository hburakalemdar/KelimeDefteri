import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Oyun ekranı düzeltmelerinin testleri: tur ortasında silinen kelimenin tanınması, oyun kartı açıklamaları.
struct GameViewFixesTests {
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func deletedWordIsRecognizedAsGone() throws {
        let context = try makeContext()
        let kept = Word(english: "idempotent", turkish: "eşgüçlü")
        let deleted = Word(english: "stale", turkish: "bayat")
        context.insert(kept)
        context.insert(deleted)
        try context.save()

        let before = [kept, deleted].aliveIDs
        #expect(!kept.isGone(from: before))
        #expect(!deleted.isGone(from: before))

        context.delete(deleted)
        try context.save()
        let words = try context.fetch(FetchDescriptor<Word>())
        let after = words.aliveIDs
        #expect(words.count == 1)
        #expect(!kept.isGone(from: after))
        #expect(deleted.isGone(from: after))
    }

    /// Başka cihazdan silinen kelime bu bağlamda silinmiş görünmeyebilir; defterde yoksa yine de atlanır.
    @Test func wordMissingFromDeckIsGone() throws {
        let context = try makeContext()
        let word = Word(english: "shard", turkish: "parça")
        context.insert(word)
        try context.save()
        #expect(word.isGone(from: []))
    }

    /// Oyun kartı açıklamaları dar kartta tek satıra sığacak kadar kısa (yazı küçültülmüyor).
    @Test func gameCardDetailsAreShort() {
        for mode in GameMode.hubGames {
            #expect(mode.cardDetail.count <= 24, "\(mode.title): \(mode.cardDetail)")
        }
        #expect(GameMode.match.cardDetail == "Anlamıyla eşle")
        #expect(GameMode.fillBlank.cardDetail == "Cümleyi tamamla")
    }
}
