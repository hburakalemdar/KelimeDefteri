import SwiftData
import SwiftUI
@preconcurrency import Translation

/// Yeni kelime ekleme ve var olanı düzenleme formu.
///
/// Hem uygulamada hem paylaşım eklentisinde kullanılır. Eklentide `draft` paylaşılan
/// metinle dolu gelir ve `onFinish` pencereyi kapatır.
struct WordFormView: View {
    enum Mode {
        case add
        case edit(Word)
    }

    let mode: Mode
    var draft = SharedTextParser.Draft()
    /// Verilirse kaydedince (true) ya da vazgeçince (false) çağrılır; form sıfırlanıp açık kalmaz.
    var onFinish: ((_ saved: Bool) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWords: [Word]
    @AppStorage("lastSource", store: SharedStore.defaults) private var lastSource = ""

    @State private var english = ""
    @State private var turkish = ""
    @State private var definition = ""
    @State private var example = ""
    @State private var source = ""
    @State private var message: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var showDictionary = false
    @State private var didLoad = false
    @FocusState private var focusedField: Field?

    private enum Field { case english, turkish }

    private var editingWord: Word? {
        if case .edit(let word) = mode { word } else { nil }
    }

    private var trimmedEnglish: String { english.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTurkish: String { turkish.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedEnglish.isEmpty && !trimmedTurkish.isEmpty }

    /// Cümle yapıştırıldıysa kelimelerini seçilebilir düğmeler olarak göster.
    private var sentenceWords: [String] {
        editingWord == nil ? SharedTextParser.words(in: example) : []
    }

    var body: some View {
        Form {
            if let message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }

            if sentenceWords.count > 1 {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(sentenceWords, id: \.self) { word in
                            let isSelected = AnswerChecker.fold(word) == AnswerChecker.fold(english)
                            Button(word) {
                                english = word.lowercased()
                                focusedField = .turkish
                            }
                            .font(.system(.body, design: .serif))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(isSelected ? .accentColor : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Bilmediğin kelimeye dokun")
                }
            }

            Section("İngilizce kelime") {
                TextField("ör. idempotent", text: $english)
                    .font(.system(.title3, design: .serif))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .english)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .turkish }
                HStack {
                    Button {
                        translate()
                    } label: {
                        Label(isTranslating ? "Çevriliyor…" : "Türkçesini bul", systemImage: "character.book.closed")
                    }
                    .disabled(trimmedEnglish.isEmpty || isTranslating)
                    Spacer()
                    Button {
                        showDictionary = true
                    } label: {
                        Label("Sözlük", systemImage: "book")
                    }
                    .disabled(trimmedEnglish.isEmpty)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }

            Section {
                TextField("ör. tekrarlanabilir, etkisi değişmeyen", text: $turkish)
                    .focused($focusedField, equals: .turkish)
            } header: {
                Text("Türkçesi")
            } footer: {
                Text("Birden fazla anlamı virgülle ayır; çalışırken herhangi birini yazman yeterli.")
            }

            Section("İngilizce anlamı (isteğe bağlı)") {
                TextField("ör. same result no matter how many times it runs", text: $definition, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("Kitaptaki cümle (isteğe bağlı)") {
                TextField("Kelimeyi gördüğün cümle", text: $example, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Kaynak (isteğe bağlı)") {
                TextField("ör. Designing Data-Intensive Applications", text: $source)
            }
        }
        .navigationTitle(editingWord == nil ? "Kelime ekle" : "Düzenle")
        .navigationBarTitleDisplayMode(editingWord == nil ? .large : .inline)
        .toolbar {
            if editingWord != nil || onFinish != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if let onFinish { onFinish(false) } else { dismiss() }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingWord == nil ? "Kaydet" : "Güncelle", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
        .onChange(of: english) { message = nil }
        .translationTask(translationConfig) { session in
            let term = trimmedEnglish
            do {
                applyTranslation(try await session.translate(term).targetText)
            } catch {
                applyTranslation(nil)
            }
        }
        .sheet(isPresented: $showDictionary) {
            DictionaryView(term: trimmedEnglish)
                .ignoresSafeArea()
        }
    }

    // MARK: - İşlemler

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let word = editingWord {
            english = word.english
            turkish = word.turkish
            definition = word.definition
            example = word.example
            source = word.source
        } else {
            english = draft.english
            example = draft.example
            source = draft.source ?? lastSource
            focusedField = english.isEmpty && sentenceWords.count <= 1 ? .english : (english.isEmpty ? nil : .turkish)
        }
    }

    private func save() {
        guard canSave else { return }
        let key = AnswerChecker.fold(trimmedEnglish)
        let duplicate = allWords.first {
            AnswerChecker.fold($0.english) == key && $0.persistentModelID != editingWord?.persistentModelID
        }
        if duplicate != nil {
            message = "“\(trimmedEnglish)” zaten defterinde."
            return
        }

        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSource = cleanSource

        if let word = editingWord {
            word.english = trimmedEnglish
            word.turkish = trimmedTurkish
            word.definition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
            word.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
            word.source = cleanSource
            try? context.save()
            dismiss()
        } else {
            context.insert(Word(
                english: trimmedEnglish,
                turkish: trimmedTurkish,
                definition: definition.trimmingCharacters(in: .whitespacesAndNewlines),
                example: example.trimmingCharacters(in: .whitespacesAndNewlines),
                source: cleanSource
            ))
            // Eklenti hemen kapanabilir; otomatik kaydı beklemeden diske yaz.
            try? context.save()
            if let onFinish {
                onFinish(true)
                return
            }
            let added = trimmedEnglish
            english = ""
            turkish = ""
            definition = ""
            example = ""
            message = "“\(added)” eklendi. Sıradaki kelime?"
            focusedField = .english
        }
    }

    private func translate() {
        isTranslating = true
        if translationConfig == nil {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "tr")
            )
        } else {
            translationConfig?.invalidate()
        }
    }

    private func applyTranslation(_ text: String?) {
        isTranslating = false
        guard let text else {
            message = "Çeviri yapılamadı. İnternet bağlantını ya da Ayarlar › Uygulamalar › Çeviri'deki dilleri kontrol et."
            return
        }
        let suggestion = text.lowercased(with: Locale(identifier: "tr_TR"))
        if trimmedTurkish.isEmpty {
            turkish = suggestion
            message = "Çeviri önerisi eklendi; teknik anlamı farklıysa düzelt."
        } else {
            message = "Çeviri önerisi: \(suggestion)"
        }
    }
}

#if DEBUG
#Preview("Ekle") {
    NavigationStack {
        WordFormView(mode: .add)
    }
    .modelContainer(PreviewData.container)
}
#endif
