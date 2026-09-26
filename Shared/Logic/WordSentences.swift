import Foundation
import SwiftData

/// Formdaki bir cümle satırı. Kayıtlı cümlede `id` kaydın `sentenceID`'si, yeni satırda yeni bir kimlik.
nonisolated struct SentenceDraft: Identifiable, Equatable {
    var id = UUID().uuidString
    var text = ""
    var meaning = ""
}

/// Kelimenin bir cümlesi, ekranların ve soruların kullandığı değer hâliyle.
///
/// Kayıt (`WordSentence`) ya da henüz kayda alınmamış eski `example` (sanal, `record == nil`) olabilir.
nonisolated struct ExampleSentence: Identifiable, Equatable {
    /// Kaydın `sentenceID`'si; sanal cümlede `legacyID`.
    let id: String
    let text: String
    /// Kayıttaki anlam etiketi (güncel anlamlarla eşleşmeyebilir; bkz. `Word.currentMeaning(of:)`).
    let meaning: String
    let record: WordSentence?

    static let legacyID = "legacy"

    init(record: WordSentence) {
        id = record.sentenceID
        text = record.text
        meaning = record.meaning
        self.record = record
    }

    init(legacy text: String) {
        id = Self.legacyID
        self.text = text
        meaning = ""
        record = nil
    }

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.text == b.text && a.meaning == b.meaning
    }
}

extension WordSentence {
    /// Cümle sırası: eklenme zamanı, eşitse kalıcı kimlik (her cihazda aynı sıra).
    static func comesFirst(_ a: WordSentence, _ b: WordSentence) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.sentenceID < b.sentenceID
    }
}

// MARK: - Okuma

extension Word {
    /// Metni dolu, silinmemiş cümle kayıtları sırayla.
    var sentenceRecords: [WordSentence] {
        (sentences ?? [])
            .filter { !$0.isDeleted && !WordSentence.key($0.text).isEmpty }
            .sorted(by: WordSentence.comesFirst)
    }

    /// Cümle kaydına alınmamış eski `example`: dolu, yeni sürümün yazdığı ayna değil (hiç yazılmadı ya da eski
    /// bir sürüm değiştirdi) ve aynı metinli bir kayıt yok. Bkz. `docs/SPEC-CUMLE.md` §2 ve §4.
    var pendingLegacyExample: String? {
        let text = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, example != exampleMirror else { return nil }
        let key = WordSentence.key(text)
        guard !(sentences ?? []).contains(where: { !$0.isDeleted && WordSentence.key($0.text) == key }) else { return nil }
        return text
    }

    /// Kelimenin cümleleri sırayla. Kayda alınmamış eski `example` de (sanal) içindedir; böylece göçten önce ve
    /// eklenti/widget gibi göç yapmayan süreçlerde de cümle kaybolmuş görünmez. Yeri, kayda alınınca alacağı yer.
    var exampleSentences: [ExampleSentence] {
        let records = sentenceRecords.map { ExampleSentence(record: $0) }
        guard let legacy = pendingLegacyExample.map({ ExampleSentence(legacy: $0) }) else { return records }
        return exampleMirror == nil ? [legacy] + records : records + [legacy]
    }

    var sentenceTexts: [String] { exampleSentences.map(\.text) }

    /// Etiketin kelimenin güncel anlamları arasındaki yazılışı; boşsa ya da artık yoksa "" (belirsiz).
    func currentMeaning(of label: String) -> String {
        let key = AnswerChecker.fold(label)
        guard !key.isEmpty else { return "" }
        return ChoiceQuiz.displayMeanings(turkish).first { AnswerChecker.fold($0) == key } ?? ""
    }

    /// Sorulan anlamın ipucu cümlesi: o anlama bağlı ilk cümle; yoksa ilk belirsiz cümle; o da yoksa `nil`.
    /// Başka anlama bağlı cümle gösterilmez (sorulan anlamla çelişir).
    func hintSentence(for meaning: String) -> ExampleSentence? {
        let key = AnswerChecker.fold(meaning)
        let labeled = exampleSentences.map { ($0, AnswerChecker.fold(currentMeaning(of: $0.meaning))) }
        if !key.isEmpty, let match = labeled.first(where: { $0.1 == key }) { return match.0 }
        return labeled.first { $0.1.isEmpty }?.0
    }

    /// Boşluğu Doldur sorusu: boşluk açılabilen cümlelerden sorulan anlamınki, yoksa belirsiz, yoksa başka anlamınki.
    /// İpucu seçilen cümlenin anlamıdır (belirsizse sorulan anlam); cümle ile ipucu hep uyuşur.
    func cloze(for meaning: String) -> (cloze: ClozeSentence, hint: String)? {
        let key = AnswerChecker.fold(meaning)
        let candidates = exampleSentences.compactMap { sentence -> (ClozeSentence, String)? in
            ClozeSentence(sentence: sentence.text, word: english).map { ($0, currentMeaning(of: sentence.meaning)) }
        }
        let pick = candidates.first { !key.isEmpty && AnswerChecker.fold($0.1) == key }
            ?? candidates.first { $0.1.isEmpty }
            ?? candidates.first
        return pick.map { ($0.0, $0.1.isEmpty ? meaning : $0.1) }
    }

    /// Cümlelerinden birinde boşluk açılabiliyor mu (Boşluğu Doldur'a girebilir mi).
    var hasClozeSentence: Bool {
        exampleSentences.contains { ClozeSentence(sentence: $0.text, word: english) != nil }
    }

    /// Bu metin (boşluklar sadeleştirilerek) kelimenin cümleleri arasında var mı; anlamı ne olursa olsun.
    func hasSentence(_ text: String) -> Bool {
        let key = WordSentence.key(text)
        return !key.isEmpty && exampleSentences.contains { WordSentence.key($0.text) == key }
    }
}

// MARK: - Yazma

extension Word {
    /// Cümle kaydı ekler (kelime bir bağlamda olmalı). Metin boşsa `nil`. Tekrar denetimi çağırana aittir.
    @discardableResult
    func insertSentence(_ text: String, meaning: String = "", createdAt: Date = .now) -> WordSentence? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let context = modelContext else { return nil }
        let sentence = WordSentence(text: clean, meaning: meaning.trimmingCharacters(in: .whitespaces), createdAt: createdAt)
        sentence.wordKey = AnswerChecker.fold(english)
        context.insert(sentence)
        sentence.word = self
        return sentence
    }

    /// Formdaki (metni dolu, kırpılmış) cümleleri kayda yazar. Silinen yalnız formda yüklenmiş (`loaded`) olup
    /// kullanıcının kaldırdığı kayıttır: form açıkken eşitlemeyle ya da bakımla kelimeye katılan kayıtlara dokunulmaz.
    /// Değişen kayıt güncellenir, yeni satır eklenir (aynı metin + anlam iki kez oluşmaz). Ayna yalnız kullanıcı
    /// yüklenmiş cümlelerin hepsini sildiyse boşaltılır (cümle kaydı henüz gelmemişse boş açılan form aynayı silmesin).
    func applySentenceDrafts(_ drafts: [SentenceDraft], loaded: [SentenceDraft], now: Date = .now) {
        let records = Dictionary(sentenceRecords.map { ($0.sentenceID, $0) }, uniquingKeysWith: { first, _ in first })
        let keptIDs = Set(drafts.map(\.id))
        let loadedIDs = Set(loaded.map(\.id))
        for id in loadedIDs.subtracting(keptIDs) {
            if let record = records[id] { modelContext?.delete(record) }
        }
        func signature(_ text: String, _ meaning: String) -> String {
            WordSentence.key(text) + "\n" + AnswerChecker.fold(meaning)
        }
        // Formda görünmeyen (sonradan gelen) kayıtlar da tekrar denetimine girer.
        var seen = Set(records.values.filter { !loadedIDs.contains($0.sentenceID) }.map { signature($0.text, $0.meaning) })
        for (offset, draft) in drafts.enumerated() {
            let isNew = seen.insert(signature(draft.text, draft.meaning)).inserted
            if let record = records[draft.id] {
                guard isNew else {
                    modelContext?.delete(record)
                    continue
                }
                if record.text != draft.text { record.text = draft.text }
                if record.meaning != draft.meaning { record.meaning = draft.meaning }
            } else if isNew {
                // Yeni satırlar formdaki sırayla, kayıtlı cümlelerin arkasına.
                insertSentence(draft.text, meaning: draft.meaning, createdAt: now.addingTimeInterval(Double(offset) / 1000))
            }
        }
        // İngilizcesi değiştiyse cümlelerin kelime anahtarı da.
        let key = AnswerChecker.fold(english)
        for record in sentenceRecords where record.wordKey != key { record.wordKey = key }
        refreshExampleMirror(clearsWhenEmpty: !loaded.isEmpty && drafts.isEmpty)
    }

    /// `example`'ı (ve aynasını) ilk cümleye eşitler; yalnız değer farklıysa yazar (gereksiz iCloud yazımı olmasın).
    /// Kayda alınmamış eski `example` varsa dokunmaz: onu önce göç (`importLegacyExample`) almalı.
    ///
    /// Hiç cümle kaydı yokken dolu aynayı ancak `clearsWhenEmpty` ile boşaltır (kullanıcı son cümleyi sildi): iCloud
    /// kelimeyi cümlesinden önce getirebilir, bakım o arada aynayı silip yeniden yazmasın.
    @discardableResult
    func refreshExampleMirror(clearsWhenEmpty: Bool = false) -> Bool {
        guard pendingLegacyExample == nil else { return false }
        let records = sentenceRecords
        if records.isEmpty && !clearsWhenEmpty && !example.isEmpty { return false }
        let first = records.first?.text ?? ""
        var changed = false
        if example != first {
            example = first
            changed = true
        }
        if exampleMirror != first {
            exampleMirror = first
            changed = true
        }
        return changed
    }

    /// Eski `example`'ı bir kez "belirsiz" cümle kaydına alır ve aynayı günceller; tekrar çalışınca bir şey değişmez.
    /// Bölünmez: satır sonlu metin (eski birleştirme ya da çok satırlı alıntı) tek cümle olur. Yalnız ana uygulamalar
    /// çağırır (bakım, düzenleme formu); eklenti ve widget göç yapmaz. Bir şey değiştiyse true.
    @discardableResult
    func importLegacyExample(now: Date = .now) -> Bool {
        var changed = false
        if let text = pendingLegacyExample {
            // İlk göçte kelimenin eklenme anı: iki cihaz aynı kaydı üretir, temizlik birini bırakır. Eski sürümün
            // sonradan yazdığı metin sona eklenir.
            changed = insertSentence(text, createdAt: exampleMirror == nil ? createdAt : now) != nil
        }
        return refreshExampleMirror() || changed
    }

    /// Aynı metin + aynı anlam etiketli kopya cümleleri siler (iki cihazın aynı anda göç etmesi, eşzamanlı ekleme).
    /// Kalan: en eski, eşitse küçük kimlikli. Aynı metnin etiketli kopyası varsa belirsiz kopyası da gider; farklı
    /// dolu etiketlerle bağlı aynı metin korunur. Silinen kayıt sayısı döner.
    @discardableResult
    func removeDuplicateSentences() -> Int {
        let records = (sentences ?? []).filter { !$0.isDeleted }.sorted(by: WordSentence.comesFirst)
        let groups = Dictionary(grouping: records) { WordSentence.key($0.text) }
        var removed = 0
        for (key, group) in groups where !key.isEmpty && group.count > 1 {
            let hasLabeled = group.contains { !AnswerChecker.fold($0.meaning).isEmpty }
            var seen: Set<String> = []
            for sentence in group {
                let meaning = AnswerChecker.fold(sentence.meaning)
                if (meaning.isEmpty && hasLabeled) || !seen.insert(meaning).inserted {
                    modelContext?.delete(sentence)
                    removed += 1
                }
            }
        }
        return removed
    }
}
