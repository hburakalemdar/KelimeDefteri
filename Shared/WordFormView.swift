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
    #if os(macOS)
    @Environment(\.openURL) private var openURL
    #endif
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
                    #if os(macOS)
                    Text("Bilmediğin kelimeye tıkla")
                    #else
                    Text("Bilmediğin kelimeye dokun")
                    #endif
                }
            }

            #if os(macOS)
            macFields
            #else
            iosFields
            #endif
        }
        .navigationTitle(editingWord == nil ? "Kelime ekle" : "Düzenle")
        #if os(iOS)
        .navigationBarTitleDisplayMode(editingWord == nil ? .large : .inline)
        #else
        .formStyle(.grouped)
        #endif
        #if os(iOS)
        .toolbar {
            if editingWord != nil || onFinish != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", action: cancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingWord == nil ? "Kaydet" : "Güncelle", action: save)
                    .disabled(!canSave)
            }
        }
        // Kaydettikten sonra odak yeni kelimeye geçer ve klavye sekme çubuğunu örter;
        // aşağı kaydırınca kapansın.
        .scrollDismissesKeyboard(.interactively)
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) { macActionBar }
        #endif
        .onAppear(perform: load)
        // Kullanıcı yeni kelime yazmaya başlayınca eski mesajı kaldır; kaydettikten sonra
        // alanın temizlenmesi "eklendi" mesajını silmesin.
        .onChange(of: english) { _, newValue in
            if !newValue.isEmpty { message = nil }
        }
        .translationTask(translationConfig) { session in
            let term = trimmedEnglish
            do {
                applyTranslation(try await session.translate(term).targetText)
            } catch {
                applyTranslation(nil)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDictionary) {
            DictionaryView(term: trimmedEnglish)
                .ignoresSafeArea()
        }
        #endif
    }

    // MARK: - Alanlar

    #if os(iOS)
    @ViewBuilder
    private var iosFields: some View {
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

                // Araç çubuğundaki düğmenin yanında formun sonunda da kaydet düğmesi (⌘S).
                Section {
                    Button(action: save) {
                        Text(editingWord == nil ? "Kaydet" : "Güncelle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
    }
    #else
    /// Mac'te Ayarlar tarzı düzen: solda etiket, sağda alan; araçlar alanın yanında.
    @ViewBuilder
    private var macFields: some View {
        Section {
            LabeledContent("İngilizce") {
                HStack(spacing: 6) {
                    TextField("İngilizce", text: $english, prompt: Text("idempotent"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .english)
                        .onSubmit { focusedField = .turkish }
                    Button(action: translate) {
                        Image(systemName: isTranslating ? "ellipsis" : "character.book.closed")
                    }
                    .help("Türkçesini bul")
                    .disabled(trimmedEnglish.isEmpty || isTranslating)
                    Button(action: lookUpInDictionary) {
                        Image(systemName: "book")
                    }
                    .help("Sözlük'te aç")
                    .disabled(trimmedEnglish.isEmpty)
                }
                .buttonStyle(.borderless)
            }
            TextField("Türkçesi", text: $turkish, prompt: Text("tekrarlanabilir, etkisi değişmeyen"))
                .focused($focusedField, equals: .turkish)
                .onSubmit(save)
        } footer: {
            Text("Birden fazla anlamı virgülle ayır; çalışırken herhangi birini yazman yeterli.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("İsteğe bağlı") {
            TextField("Anlamı", text: $definition, prompt: Text("same result however many times it runs"), axis: .vertical)
                .lineLimit(1...3)
            TextField("Cümle", text: $example, prompt: Text("Kelimeyi gördüğün cümle"), axis: .vertical)
                .lineLimit(1...4)
            TextField("Kaynak", text: $source, prompt: Text("Kitap adı"))
        }
    }

    /// Mac'te pencerenin sağ altında Vazgeç / Kaydet.
    private var macActionBar: some View {
        HStack {
            Spacer()
            if editingWord != nil || onFinish != nil {
                Button("Vazgeç", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            Button(editingWord == nil ? "Kaydet" : "Güncelle", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .help("⌘S")
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Mac'te Sözlük uygulamasında açar.
    private func lookUpInDictionary() {
        let term = trimmedEnglish.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "dict://" + term) { openURL(url) }
    }
    #endif

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

    private func cancel() {
        if let onFinish { onFinish(false) } else { dismiss() }
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
