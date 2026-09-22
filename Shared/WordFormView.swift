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
    /// Aynı kelime zaten defterdeyse onun adı; kaydetmeyi durdurur.
    @State private var duplicate: String?
    /// Türkçe alanı doluyken gelen çeviri önerisi; "Kullan" ile alana yazılır.
    @State private var suggestion: String?
    /// Türkçe alanı çeviriyle dolduruldu; kullanıcıya kontrol etmesi hatırlatılır.
    @State private var didAutofill = false
    @State private var translationFailed = false
    /// Uygulamadaki Ekle sekmesinde kaydedince artar (titreşim ve "eklendi" satırı için).
    @State private var savedCount = 0
    @State private var lastAdded: String?
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
            #if os(macOS)
            if let macMessage {
                Section {
                    Label(macMessage, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
            #endif

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
                            .buttonBorderShape(.capsule)
                            .modifier(ChipStyle(isSelected: isSelected))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    #if os(macOS)
                    Text("Bilmediğin kelimeye tıkla")
                    #else
                    Text("Bilmediğin Kelimeye Dokun")
                    #endif
                } footer: {
                    if !source.isEmpty && onFinish != nil {
                        Label(source, systemImage: "book.closed")
                    }
                }
            }

            #if os(macOS)
            macFields
            #else
            iosFields
            #endif
        }
        #if os(iOS)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(editingWord == nil && onFinish == nil ? .large : .inline)
        .toolbar {
            if editingWord != nil || onFinish != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", systemImage: "xmark", role: .cancel, action: cancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editingWord == nil ? "Kaydet" : "Güncelle", systemImage: "checkmark", role: .confirm, action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        // Kaydettikten sonra odak yeni kelimeye geçer ve klavye sekme çubuğunu örter;
        // aşağı kaydırınca kapansın.
        .scrollDismissesKeyboard(.interactively)
        #else
        .navigationTitle(editingWord == nil ? "Kelime ekle" : "Düzenle")
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { macActionBar }
        #endif
        .onAppear(perform: load)
        // Kelime değişince ona ait uyarı ve öneriler geçersizleşir. Kaydettikten sonra
        // alanın temizlenmesi "eklendi" satırını silmesin.
        .onChange(of: english) { _, newValue in
            duplicate = nil
            suggestion = nil
            translationFailed = false
            if !newValue.isEmpty { lastAdded = nil }
        }
        .onChange(of: turkish) { _, newValue in
            if newValue.isEmpty { didAutofill = false }
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
    private var title: String {
        if editingWord != nil { return "Düzenle" }
        return onFinish == nil ? "Yeni Kelime" : "Kelime Defteri"
    }

    @ViewBuilder
    private var iosFields: some View {
        if let lastAdded, onFinish == nil {
            Section {
                Label {
                    Text("“\(lastAdded)” eklendi")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline.weight(.medium))
            }
        }

        Section {
            TextField("İngilizce kelime", text: $english)
                .font(.system(.title3, design: .serif, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .english)
                .submitLabel(.next)
                .onSubmit { focusedField = .turkish }
            TextField("Türkçesi", text: $turkish)
                .focused($focusedField, equals: .turkish)
            if let suggestion {
                HStack {
                    Label {
                        Text("Öneri: ") + Text(suggestion).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(.tint)
                    }
                    Spacer()
                    Button("Kullan") {
                        turkish = suggestion
                        self.suggestion = nil
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                .font(.subheadline)
            }
        } footer: {
            if let duplicate {
                Text("“\(duplicate)” zaten defterinde.")
                    .foregroundStyle(.red)
            } else if didAutofill {
                Text("Türkçesi makine çevirisinden geldi; teknik anlamı farklıysa düzelt.")
            } else {
                Text("Birden fazla anlamı virgülle ayır; çalışırken herhangi birini yazman yeterli.")
            }
        }

        Section {
            Button(action: translate) {
                HStack {
                    Label("Türkçesini Bul", systemImage: "translate")
                        .foregroundStyle(actionStyle)
                    Spacer()
                    if isTranslating { ProgressView() }
                }
            }
            .disabled(trimmedEnglish.isEmpty || isTranslating)
            Button {
                showDictionary = true
            } label: {
                Label("Sözlükte Bak", systemImage: "character.book.closed")
                    .foregroundStyle(actionStyle)
            }
            .disabled(trimmedEnglish.isEmpty)
        } footer: {
            if translationFailed {
                Text("Çeviri yapılamadı. İnternet bağlantını ya da Ayarlar › Uygulamalar › Çeviri'deki dilleri kontrol et.")
            }
        }

        Section("Ayrıntılar") {
            TextField("İngilizce anlamı", text: $definition, axis: .vertical)
                .lineLimit(1...3)
            TextField("Kitaptaki cümle", text: $example, axis: .vertical)
                .lineLimit(1...5)
            HStack {
                TextField("Kaynak kitap", text: $source)
                if !recentSources.isEmpty {
                    Menu {
                        ForEach(recentSources, id: \.self) { title in
                            Button(title) { source = title }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Önceki kitaplar")
                }
            }
        }

        if onFinish == nil && editingWord == nil && !addedToday.isEmpty {
            Section("Bugün Eklenenler") {
                ForEach(addedToday.prefix(5)) { word in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.english)
                            .font(.system(.body, design: .serif, weight: .semibold))
                        Text(word.turkish)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// Form düğmeleri pasifken iOS 26'da siyah kalıyor; boş kelimede soluk göster.
    private var actionStyle: AnyShapeStyle {
        trimmedEnglish.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint)
    }

    /// En son kullanılan kitaplar, yeniden yazmamak için.
    private var recentSources: [String] {
        var seen = Set<String>()
        return allWords
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.source)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    private var addedToday: [Word] {
        let start = Calendar.current.startOfDay(for: .now)
        return allWords.filter { $0.createdAt >= start }.sorted { $0.createdAt > $1.createdAt }
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

    private var macMessage: String? {
        if let duplicate { return "“\(duplicate)” zaten defterinde." }
        if translationFailed { return "Çeviri yapılamadı. İnternet bağlantını ya da Sistem Ayarları › Genel › Dil ve Bölge › Çeviri Dilleri'ni kontrol et." }
        if let suggestion { return "Çeviri önerisi: \(suggestion)" }
        if didAutofill { return "Çeviri önerisi eklendi; teknik anlamı farklıysa düzelt." }
        if let lastAdded { return "“\(lastAdded)” eklendi. Sıradaki kelime?" }
        return nil
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
            if !english.isEmpty {
                // Paylaşılan kelime geldi; sıra Türkçesinde.
                focusedField = .turkish
            } else if sentenceWords.count <= 1 {
                // iPhone'da Ekle sekmesine geçmek klavyeyi açmasın; alana dokununca açılır.
                // Mac'te yazmaya hemen başlanabilsin.
                #if os(macOS)
                focusedField = .english
                #endif
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let key = AnswerChecker.fold(trimmedEnglish)
        let duplicate = allWords.first {
            AnswerChecker.fold($0.english) == key && $0.persistentModelID != editingWord?.persistentModelID
        }
        if duplicate != nil {
            self.duplicate = trimmedEnglish
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
            lastAdded = added
            savedCount += 1
            focusedField = .english
        }
    }

    private func cancel() {
        if let onFinish { onFinish(false) } else { dismiss() }
    }

    private func translate() {
        isTranslating = true
        translationFailed = false
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
            translationFailed = true
            return
        }
        let suggestion = text.lowercased(with: Locale(identifier: "tr_TR"))
        if trimmedTurkish.isEmpty {
            turkish = suggestion
            didAutofill = true
        } else if AnswerChecker.fold(suggestion) != AnswerChecker.fold(trimmedTurkish) {
            self.suggestion = suggestion
        }
    }
}

/// Cümledeki kelime düğmeleri: seçili olan vurgu renginde dolu, diğerleri sade.
private struct ChipStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered).tint(.secondary)
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
