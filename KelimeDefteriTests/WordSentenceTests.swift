import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Çok cümleli kelimeler: göç, kopya temizliği, birleştirme, yeniden ekleme, ipucu (bkz. docs/SPEC-CUMLE.md).
final class WordSentenceTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let suiteName = "WordSentenceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Bellek içi depo iOS 27 simülatöründe kaydederken ara ara çöktüğü için geçici dosya kullanılır.
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func sentenceCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<WordSentence>())
    }

    /// Başka bir cihazın ürettiği kayıt gibi: kimliği ve zamanı elle verilir.
    @discardableResult
    private func insertRecord(
        _ text: String, meaning: String = "", id: String, at date: Date, to word: Word?, in context: ModelContext
    ) -> WordSentence {
        let sentence = WordSentence(text: text, meaning: meaning, createdAt: date)
        sentence.sentenceID = id
        context.insert(sentence)
        sentence.word = word
        return sentence
    }

    // MARK: - Göç

    @Test func legacyExampleIsImportedOnceAndStaysFirst() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
        context.insert(word)
        // Göçten önce de cümle görünür (sanal).
        #expect(word.exampleSentences.map(\.id) == [ExampleSentence.legacyID])
        #expect(word.sentenceTexts == ["A stale cache."])

        #expect(word.importLegacyExample(now: base.addingTimeInterval(500)))
        #expect(!word.importLegacyExample(now: base.addingTimeInterval(900)))
        try context.save()

        #expect(try sentenceCount(context) == 1)
        let record = try #require(word.sentenceRecords.first)
        #expect(record.text == "A stale cache.")
        #expect(record.meaning.isEmpty)
        #expect(record.createdAt == base)
        #expect(word.exampleMirror == "A stale cache.")
        #expect(word.example == "A stale cache.")

        // Bakım da tekrar çalışınca bir şey değiştirmez.
        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(!StoreMaintenance.run(in: context, defaults: defaults, now: base).changed)
        #expect(try sentenceCount(context) == 1)
    }

    @Test func emptyExampleOnlyMarksWordMigrated() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        #expect(word.importLegacyExample())
        #expect(word.exampleMirror == "")
        #expect(!word.importLegacyExample())
        #expect(try sentenceCount(context) == 0)
    }

    /// Satır sonlu metin (eski birleştirme ya da gerçek alıntı) bölünmez.
    @Test func multilineQuoteIsNotSplit() throws {
        let context = try makeContext()
        let quote = "“The log is the database,”\nhe wrote,\nand the cache is a stale subset."
        let word = Word(english: "stale", turkish: "eskimiş", example: quote)
        context.insert(word)
        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(word.sentenceTexts == [quote])
        #expect(try sentenceCount(context) == 1)
    }

    /// İki cihaz aynı anda göç etti: aynı metin, boş anlam, aynı zaman → kopyalar tek kayda iner ve her cihaz
    /// (kayıtları hangi sırayla görürse görsün) aynı kaydı bırakır.
    @Test func concurrentMigrationCopiesCollapseDeterministically() throws {
        for order in [["B", "A"], ["A", "B"]] {
            let context = try makeContext()
            let word = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
            word.exampleMirror = "A stale cache."
            context.insert(word)
            for id in order {
                insertRecord("A stale cache.", id: "\(id)-uuid", at: base, to: word, in: context)
            }
            try context.save()

            let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
            #expect(summary.sentenceChanges == 1)
            #expect(try sentenceCount(context) == 1)
            #expect(word.sentenceRecords.map(\.sentenceID) == ["A-uuid"])
        }
    }

    /// Aynı metin farklı anlamlara bağlıysa ikisi de kalır; etiketli kopyası olan belirsiz kopya gider.
    @Test func sameTextWithDifferentMeaningsIsKept() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş, bayat", createdAt: base)
        word.exampleMirror = ""
        context.insert(word)
        insertRecord("Stale bread.", meaning: "bayat", id: "1", at: base, to: word, in: context)
        insertRecord("Stale  bread.", meaning: "eskimiş", id: "2", at: base, to: word, in: context)
        insertRecord("Stale bread.", id: "3", at: base.addingTimeInterval(-10), to: word, in: context)
        insertRecord("Stale bread.", meaning: "Bayat", id: "4", at: base.addingTimeInterval(5), to: word, in: context)
        try context.save()

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(Set(word.sentenceRecords.map(\.sentenceID)) == ["1", "2"])
    }

    // MARK: - Eski sürümlerle uyum (example aynası)

    @Test func exampleMirrorsFirstSentence() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş")
        context.insert(word)
        word.insertSentence("Second.", createdAt: base.addingTimeInterval(10))
        word.insertSentence("First.", createdAt: base)
        #expect(word.refreshExampleMirror())
        #expect(word.example == "First.")
        #expect(word.exampleMirror == "First.")
        #expect(!word.refreshExampleMirror())

        // İlk cümle silinince ayna ikinciye geçer; son cümle de silinince boşalır.
        context.delete(try #require(word.sentenceRecords.first))
        word.refreshExampleMirror()
        #expect(word.example == "Second.")
        context.delete(try #require(word.sentenceRecords.first))
        // Bakım (kelime cümlesinden önce gelmiş olabilir) boşaltmaz; kullanıcının silmesi boşaltır.
        #expect(!word.refreshExampleMirror())
        #expect(word.example == "Second.")
        word.refreshExampleMirror(clearsWhenEmpty: true)
        #expect(word.example == "")
        #expect(word.exampleMirror == "")
    }

    /// Eski sürümün `example` düzenlemesi yeni cümle olarak sona eklenir; boşaltması yayılmaz.
    @Test func oldClientEditIsAddedAndClearIsIgnored() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", example: "Old.", createdAt: base)
        context.insert(word)
        word.importLegacyExample(now: base)

        word.example = "Edited on old device."
        #expect(word.exampleSentences.map(\.text) == ["Old.", "Edited on old device."])
        #expect(word.importLegacyExample(now: base.addingTimeInterval(100)))
        #expect(word.sentenceTexts == ["Old.", "Edited on old device."])
        #expect(word.example == "Old.")
        #expect(!word.importLegacyExample(now: base.addingTimeInterval(200)))

        word.example = ""
        #expect(word.pendingLegacyExample == nil)
        #expect(word.importLegacyExample(now: base.addingTimeInterval(300)))
        #expect(word.example == "Old.")
        #expect(word.sentenceRecords.count == 2)
    }

    /// Gecikmiş eşitleme: kelime (ayna ile) cümle kaydından önce gelirse içe alma tetiklenmez.
    @Test func wordArrivingBeforeItsSentenceIsNotReimported() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", example: "Edited.", createdAt: base)
        word.exampleMirror = "Edited."
        context.insert(word)
        #expect(word.pendingLegacyExample == nil)
        #expect(!word.importLegacyExample())
        #expect(try sentenceCount(context) == 0)
    }

    // MARK: - Birleştirme ve sahipsiz kayıtlar

    @Test func mergeImportsBothExamplesThenMovesSentences() throws {
        let context = try makeContext()
        let older = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
        let newer = Word(english: "Stale", turkish: "bayat", createdAt: base.addingTimeInterval(10))
        newer.exampleMirror = "Stale bread."
        newer.example = "Stale bread."
        context.insert(older)
        context.insert(newer)
        insertRecord("Stale bread.", meaning: "bayat", id: "n1", at: base.addingTimeInterval(10), to: newer, in: context)
        insertRecord("Stale reads.", id: "n2", at: base.addingTimeInterval(20), to: newer, in: context)
        try context.save()

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(summary.mergedWords == 1)
        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.count == 1)
        let kept = try #require(words.first)
        #expect(kept === older)
        #expect(kept.sentenceTexts == ["A stale cache.", "Stale bread.", "Stale reads."])
        #expect(kept.sentenceRecords[1].meaning == "bayat")
        #expect(kept.example == "A stale cache.")
        #expect(try sentenceCount(context) == 3)
    }

    @Test func orphanSentenceIsNeverDeleted() throws {
        let context = try makeContext()
        insertRecord("Lost sentence.", id: "o", at: base, to: nil, in: context)
        try context.save()
        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(7 * 86_400))
        #expect(try sentenceCount(context) == 1)
    }

    // MARK: - Yeniden ekleme

    @Test func absorbKeepsBothSentencesAndBindsSingleNewMeaning() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
        context.insert(word)
        word.importLegacyExample(now: base)
        word.box = 3
        let due = base.addingTimeInterval(86_400 * 5)
        word.dueDate = due

        #expect(word.wouldAbsorb(turkish: "eskimiş", sentences: ["Stale bread."]))
        #expect(!word.wouldAbsorb(turkish: "Eskimiş", sentences: [" A  stale cache. "]))

        word.absorb(turkish: "bayat", example: "Stale bread.", now: base.addingTimeInterval(60))
        #expect(word.turkish == "eskimiş, bayat")
        #expect(word.sentenceTexts == ["A stale cache.", "Stale bread."])
        #expect(word.sentenceRecords.last?.meaning == "bayat")
        #expect(word.example == "A stale cache.")
        #expect(word.box == 3)
        #expect(word.dueDate == due)

        // Aynı cümle yeniden oluşmaz; iki yeni anlamla gelen cümle belirsiz kalır.
        word.absorb(turkish: "bayat", example: "Stale bread.", now: base.addingTimeInterval(120))
        word.absorb(turkish: "güncel olmayan, köhne", example: "Stale docs.", now: base.addingTimeInterval(180))
        #expect(word.sentenceTexts == ["A stale cache.", "Stale bread.", "Stale docs."])
        #expect(word.sentenceRecords.last?.meaning == "")
        // Anlam eklemeden gelen cümle de belirsiz.
        word.absorb(turkish: "bayat", example: "Stale tokens.", now: base.addingTimeInterval(240))
        #expect(word.sentenceRecords.last?.meaning == "")
    }

    /// Göç yapmayan süreç (eklenti) içe alınmamış kelimeye cümle ekler: eski `example`'a ve aynaya dokunmaz; sonraki
    /// göç eski cümleyi ilk sıraya alır.
    @Test func absorbIntoUnmigratedWordLeavesLegacyForMigration() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
        context.insert(word)
        word.absorb(turkish: "eskimiş", example: "Stale bread.", now: base.addingTimeInterval(60))
        #expect(word.example == "A stale cache.")
        #expect(word.exampleMirror == nil)
        #expect(word.sentenceTexts == ["A stale cache.", "Stale bread."])

        word.importLegacyExample(now: base.addingTimeInterval(120))
        #expect(word.sentenceRecords.map(\.text) == ["A stale cache.", "Stale bread."])
        #expect(word.exampleMirror == "A stale cache.")
    }

    // MARK: - İpucu ve Boşluğu Doldur

    @Test func hintUsesAskedMeaningThenUnlabeled() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş, bayat, güncel olmayan")
        context.insert(word)
        word.insertSentence("Stale bread.", meaning: "bayat", createdAt: base)
        word.insertSentence("Stale reads.", createdAt: base.addingTimeInterval(1))

        #expect(word.hintSentence(for: "bayat")?.text == "Stale bread.")
        #expect(word.hintSentence(for: "Eskimiş")?.text == "Stale reads.")

        // Belirsiz cümle yoksa başka anlamın cümlesi gösterilmez.
        context.delete(try #require(word.sentenceRecords.last))
        #expect(word.hintSentence(for: "eskimiş") == nil)
        #expect(word.hintSentence(for: "bayat")?.text == "Stale bread.")
    }

    /// Anlam yeniden adlandırılınca cümle belirsize düşer, etiketi silinmez.
    @Test func renamedMeaningFallsBackToUnlabeled() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş, bayat")
        context.insert(word)
        let sentence = try #require(word.insertSentence("Stale bread.", meaning: "bayat"))
        word.turkish = "eskimiş, bayatlamış"
        #expect(word.currentMeaning(of: sentence.meaning) == "")
        #expect(word.hintSentence(for: "eskimiş")?.text == "Stale bread.")
        #expect(sentence.meaning == "bayat")
    }

    @Test func clozePrefersAskedMeaningAndHintMatchesSentence() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş, bayat")
        context.insert(word)
        word.insertSentence("No blank here.", meaning: "eskimiş", createdAt: base)
        word.insertSentence("Stale bread.", meaning: "bayat", createdAt: base.addingTimeInterval(1))
        word.insertSentence("Old and stale data.", createdAt: base.addingTimeInterval(2))

        let asked = try #require(word.cloze(for: "bayat"))
        #expect(asked.cloze.after == " bread.")
        #expect(asked.hint == "bayat")
        // Sorulan anlamın cümlesinde boşluk açılamıyor: belirsiz cümle, ipucu sorulan anlam.
        let unlabeled = try #require(word.cloze(for: "eskimiş"))
        #expect(unlabeled.cloze.before == "Old and ")
        #expect(unlabeled.hint == "eskimiş")
        #expect(word.hasClozeSentence)

        // Belirsiz de yoksa başka anlamın cümlesi; ipucu o cümlenin anlamı olur.
        context.delete(try #require(word.sentenceRecords.last))
        let other = try #require(word.cloze(for: "eskimiş"))
        #expect(other.cloze.match == "Stale")
        #expect(other.hint == "bayat")
    }

    // MARK: - Form kaydı

    private func drafts(_ word: Word) -> [SentenceDraft] {
        word.exampleSentences.map { SentenceDraft(id: $0.id, text: $0.text, meaning: $0.meaning) }
    }

    /// Form açıkken kelimeye katılan kayıt (eşitleme, bakımın birleştirmesi) kaydedince silinmez; yalnız kullanıcının
    /// kaldırdığı yüklenmiş kayıt silinir.
    @Test func formSaveKeepsSentencesArrivedWhileOpen() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş", createdAt: base)
        context.insert(word)
        word.insertSentence("First.", createdAt: base)
        word.insertSentence("Second.", createdAt: base.addingTimeInterval(1))
        word.refreshExampleMirror()
        let loaded = drafts(word)

        // Form açıkken başka cihazdan iki cümle geldi (biri formdaki yeni satırla aynı).
        insertRecord("Arrived.", id: "late", at: base.addingTimeInterval(5), to: word, in: context)
        insertRecord("Typed too.", id: "late2", at: base.addingTimeInterval(6), to: word, in: context)

        var edited = loaded
        edited[0].text = "First, edited."
        edited.remove(at: 1)
        edited.append(SentenceDraft(text: "Typed too."))
        word.applySentenceDrafts(edited, loaded: loaded, now: base.addingTimeInterval(10))

        #expect(word.sentenceTexts == ["First, edited.", "Arrived.", "Typed too."])
        #expect(word.example == "First, edited.")
        #expect(word.sentenceRecords.allSatisfy { $0.wordKey == "stale" })
    }

    /// Kelime cümle kaydından önce geldiyse form boş açılır; yalnız Türkçe değişip kaydedilince ayna silinmez.
    /// Kullanıcı yüklenmiş cümlelerin hepsini silerse boşalır.
    @Test func formSaveClearsMirrorOnlyWhenUserDeletedSentences() throws {
        let context = try makeContext()
        let waiting = Word(english: "stale", turkish: "eskimiş", example: "Pending.", createdAt: base)
        waiting.exampleMirror = "Pending."
        context.insert(waiting)
        waiting.applySentenceDrafts([], loaded: [])
        #expect(waiting.example == "Pending.")
        #expect(waiting.exampleMirror == "Pending.")

        let word = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        context.insert(word)
        word.insertSentence("Only.", createdAt: base)
        word.refreshExampleMirror()
        word.applySentenceDrafts([], loaded: drafts(word))
        #expect(word.sentenceRecords.isEmpty)
        #expect(word.example == "")
        #expect(word.exampleMirror == "")
    }

    /// Birleştirmede silinen kopyaya sonradan bağlı gelen cümle, kelime anahtarıyla kalan kayda bağlanır.
    @Test func orphanWithWordKeyIsAdoptedBySameWord() throws {
        let context = try makeContext()
        let word = Word(english: "Stale", turkish: "eskimiş", createdAt: base)
        word.exampleMirror = ""
        context.insert(word)
        let orphan = insertRecord("Late sentence.", id: "o", at: base, to: nil, in: context)
        orphan.wordKey = "stale"
        let unknown = insertRecord("Other.", id: "u", at: base, to: nil, in: context)
        unknown.wordKey = "quorum"
        try context.save()

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(summary.sentenceChanges >= 1)
        #expect(orphan.word === word)
        #expect(word.example == "Late sentence.")
        #expect(unknown.word == nil)
        #expect(try sentenceCount(context) == 2)
    }
}
