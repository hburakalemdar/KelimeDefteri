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

    @State private var english = ""
    @State private var turkish = ""
    /// Formdaki cümleler; en az bir satır (boş olabilir). Kayıtlı cümlenin kimliği `sentenceID`'sidir.
    @State private var sentences = [SentenceDraft()]
    /// Düzenleme açılırken yüklenen cümleler (değişiklik denetimi için).
    @State private var loadedSentences: [SentenceDraft] = []
    /// Türkçe alanı doluyken gelen çeviri önerisi; "Kullan" ile alana yazılır.
    @State private var suggestion: String?
    /// Türkçe alanı çeviriyle dolduruldu; kullanıcıya kontrol etmesi hatırlatılır.
    @State private var didAutofill = false
    @State private var translationFailed = false
    /// Uygulamadaki Ekle sekmesinde kaydedince artar (titreşim ve "eklendi" satırı için).
    @State private var savedCount = 0
    /// Son kaydın sonucu: "“stale” eklendi", "“stale” güncellendi"…
    @State private var savedMessage: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    /// Süren çeviri isteğinin İngilizce terimi; kelime değişince geç gelen sonuç atılır.
    @State private var translatingTerm: String?
    @State private var confirmDiscard = false
    /// Son kaydetme diske yazılamadı; uyarı gösterilir, form açık kalır.
    @State private var saveFailed = false
    #if os(iOS)
    /// "Bugün Eklenenler"den dokunulup düzenlenen kelime.
    @State private var editingToday: Word?
    @State private var confirmDelete = false
    #endif
    @State private var showDictionary = false
    @State private var didLoad = false
    @State private var selection: ClosedRange<Int>?
    @FocusState private var focusedField: Field?

    private enum Field { case english, turkish }

    private var editingWord: Word? {
        if case .edit(let word) = mode { word } else { nil }
    }

    private var trimmedEnglish: String { english.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTurkish: String { turkish.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedEnglish.isEmpty && !trimmedTurkish.isEmpty && existingMatch == nil }

    /// Düzenlenen kelimenin alanları yüklenen değerlerden farklı; kapatmadan önce sorulur.
    private var hasChanges: Bool {
        guard let word = editingWord, didLoad else { return false }
        return english != word.english || turkish != word.turkish
            || Self.filled(sentences) != Self.filled(loadedSentences)
    }

    /// Yazılan kelime defterde zaten varsa o kayıt (düzenlenen kelimenin kendisi hariç).
    /// Düzenlemede İngilizce değişmediyse aranmaz: iki cihazda eşitlenmeden eklenen çift kayıt
    /// düzenlemeyi engellemesin (çiftler uygulama öne gelince birleştirilir).
    private var existingMatch: Word? {
        guard !trimmedEnglish.isEmpty else { return nil }
        if let editingWord, WordMatcher.isSame(editingWord.english, trimmedEnglish) { return nil }
        return allWords.first {
            $0.persistentModelID != editingWord?.persistentModelID && WordMatcher.isSame($0.english, trimmedEnglish)
        }
    }

    /// Yazılan kelimenin kalıbı olan ya da kalıbın içinde geçen kayıtlar.
    private var relatedWords: [Word] {
        guard !trimmedEnglish.isEmpty else { return [] }
        return allWords
            .filter { $0.persistentModelID != editingWord?.persistentModelID && WordMatcher.isRelated($0.english, trimmedEnglish) }
            .sorted { $0.english.count < $1.english.count }
    }

    /// Metni dolu cümleler, kırpılmış.
    private var filledSentences: [SentenceDraft] { Self.filled(sentences) }

    private static func filled(_ drafts: [SentenceDraft]) -> [SentenceDraft] {
        drafts.compactMap { draft in
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : SentenceDraft(id: draft.id, text: text, meaning: draft.meaning)
        }
    }

    /// Cümlenin bağlanabileceği anlamlar (Türkçe alanındaki); anlam seçici yalnızca iki ya da daha fazlası varsa görünür.
    private var meaningOptions: [String] { ChoiceQuiz.displayMeanings(turkish) }

    /// Cümle yapıştırıldıysa kelimelerini seçilebilir düğmeler olarak göster (sırasıyla, tekrarlar dahil).
    private var sentenceWords: [String] {
        editingWord == nil ? SharedTextParser.tokens(in: sentences.first?.text ?? "") : []
    }

    /// Düğmelerle seçilen kelimeler; İngilizce alanı elle değiştirildiyse geçersiz sayılır.
    private var validSelection: ClosedRange<Int>? {
        guard let selection, selection.upperBound < sentenceWords.count,
              AnswerChecker.fold(SharedTextParser.phrase(sentenceWords, selection)) == AnswerChecker.fold(english)
        else { return nil }
        return selection
    }

    var body: some View {
        #if os(macOS)
        // Mac'te düğmeler formun altında sade durur; form onların üstünde biter, altından geçmez.
        VStack(spacing: 0) {
            form
            macActionBar
        }
        #else
        form
        #endif
    }

    private var form: some View {
        Form {
            #if os(macOS)
            if let savedMessage, onFinish == nil {
                Section {
                    Label {
                        Text("\(savedMessage). Sıradaki kelime?")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            #endif

            if sentenceWords.count > 1 {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(sentenceWords.enumerated()), id: \.offset) { index, word in
                            Button(word) { tapWord(at: index) }
                                .font(.system(.body, design: .serif))
                                .buttonBorderShape(.capsule)
                                .modifier(ChipStyle(isSelected: validSelection?.contains(index) == true))
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
                    VStack(alignment: .leading, spacing: 6) {
                        #if os(macOS)
                        Text("İki ya da daha fazla kelimelik ifade için ilk ve son kelimesine tıkla.")
                        #else
                        Text("İki ya da daha fazla kelimelik ifade için ilk ve son kelimesine dokun.")
                        #endif
                    }
                    #if os(macOS)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    #endif
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
        // Değişiklik varken aşağı çekip kapatılamaz; Vazgeç onay ister.
        .interactiveDismissDisabled(hasChanges)
        // Kaydettikten sonra odak yeni kelimeye geçer ve klavye sekme çubuğunu örter;
        // aşağı kaydırınca kapansın.
        .scrollDismissesKeyboard(.interactively)
        #else
        .navigationTitle(editingWord == nil ? "Kelime ekle" : "Düzenle")
        .formStyle(.grouped)
        #endif
        // "Zaten Defterinde" bölümü kayarak açılıp kapansın.
        .animation(.snappy(duration: 0.3), value: existingMatch?.persistentModelID)
        #if os(iOS)
        .sensoryFeedback(trigger: existingMatch?.persistentModelID) { _, new in
            new != nil && editingWord == nil ? .warning : nil
        }
        #endif
        .onAppear(perform: load)
        // Kelime değişince ona ait uyarı ve öneriler geçersizleşir. Kaydettikten sonra
        // alanın temizlenmesi "eklendi" satırını silmesin.
        .onChange(of: english) { _, newValue in
            suggestion = nil
            translationFailed = false
            resetTranslation()
            if !newValue.isEmpty { savedMessage = nil }
        }
        .onChange(of: turkish) { _, newValue in
            if newValue.isEmpty { didAutofill = false }
        }
        .translationTask(translationConfig) { session in
            guard let term = translatingTerm else { return }
            do {
                applyTranslation(try await session.translate(term).targetText, for: term)
            } catch {
                applyTranslation(nil, for: term)
            }
        }
        .alert("Kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Kelime deftere yazılamadı. Biraz sonra tekrar dene.")
        }
        .confirmationDialog("Değişiklikleri at?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Değişiklikleri At", role: .destructive) { dismiss() }
            Button("Düzenlemeye Devam Et", role: .cancel) {}
        }
        #if os(iOS)
        .sheet(isPresented: $showDictionary) {
            DictionaryView(term: trimmedEnglish)
                .ignoresSafeArea()
        }
        .sheet(item: $editingToday) { word in
            NavigationStack {
                WordFormView(mode: .edit(word))
            }
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
        if let savedMessage, onFinish == nil {
            Section {
                Label {
                    Text(savedMessage)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline.weight(.medium))
            }
        }

        Section {
            HStack {
                TextField("İngilizce kelime", text: $english)
                    .font(.system(.title3, design: .serif, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .english)
                    .submitLabel(.next)
                    // Kelime zaten defterdeyse klavye kapanır; uyarı görünsün.
                    .onSubmit { focusedField = existingMatch == nil ? .turkish : nil }
                if editingWord == nil && existingMatch != nil {
                    existingIcon
                }
            }
            TextField("Türkçesi", text: $turkish)
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .turkish)
                .submitLabel(.done)
                .onSubmit { if canSave { save() } }
            if suggestion != nil {
                suggestionRow
                    .font(.subheadline)
            }
            if existingMatch == nil && !relatedWords.isEmpty {
                relatedRow
                    .font(.subheadline)
            }
        } footer: {
            fieldFooter
        }

        if editingWord == nil, let existingMatch {
            existingSection(existingMatch)
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
            if translationFailed && trimmedTurkish.isEmpty {
                Text("Çeviri yapılamadı. İnternet bağlantını ya da Ayarlar › Uygulamalar › Çeviri'deki dilleri kontrol et.")
            }
        }

        Section("Cümleler") {
            ForEach($sentences) { $sentence in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Kitaptaki cümle", text: $sentence.text, axis: .vertical)
                        .lineLimit(1...5)
                    if meaningOptions.count > 1 {
                        meaningPicker($sentence)
                            .font(.subheadline)
                    }
                }
            }
            .onDelete { offsets in
                sentences.remove(atOffsets: offsets)
                if sentences.isEmpty { sentences = [SentenceDraft()] }
            }
            // Boş satır varken yenisi eklenmez; pasif düğme iOS 26 formunda siyah kalmasın diye renk elle.
            Button {
                sentences.append(SentenceDraft())
            } label: {
                Label("Cümle Ekle", systemImage: "plus")
                    .foregroundStyle(canAddSentence ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .disabled(!canAddSentence)
        }

        if let editingWord {
            // Kişiler'deki gibi formun en altında; onay ister.
            Section {
                Button("Kelimeyi Sil", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
            }
            .confirmationDialog("“\(editingWord.english)” silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Kelimeyi Sil", role: .destructive) { delete(editingWord) }
            } message: {
                Text("Çalışma geçmişi de silinir.")
            }
        }

        if onFinish == nil && editingWord == nil && !addedToday.isEmpty {
            Section("Bugün Eklenenler") {
                ForEach(addedToday.prefix(5)) { word in
                    // Form düğme yazısını vurgu rengine boyuyor; Kelimelerim satırı gibi görünsün diye sabit renkler.
                    Button { editingToday = word } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.english)
                                .font(.system(.body, design: .serif, weight: .semibold))
                                .foregroundStyle(Color(.label))
                            Text(word.turkish)
                                .font(.subheadline)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// Form düğmeleri pasifken iOS 26'da siyah kalıyor; boş kelimede soluk göster.
    private var actionStyle: AnyShapeStyle {
        trimmedEnglish.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint)
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
                    if editingWord == nil && existingMatch != nil {
                        existingIcon
                    }
                    Button(action: translate) {
                        if isTranslating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "translate")
                        }
                    }
                    .help("Türkçesini bul")
                    .disabled(trimmedEnglish.isEmpty || isTranslating)
                    Button(action: lookUpInDictionary) {
                        Image(systemName: "character.book.closed")
                    }
                    .help("Sözlük'te aç")
                    .disabled(trimmedEnglish.isEmpty)
                }
                .buttonStyle(.borderless)
            }
            TextField("Türkçesi", text: $turkish, prompt: Text("tekrarlanabilir, etkisi değişmeyen"))
                .focused($focusedField, equals: .turkish)
                .onSubmit(save)
            if suggestion != nil {
                suggestionRow
            }
            if existingMatch == nil && !relatedWords.isEmpty {
                relatedRow
            }
        } footer: {
            Group {
                if translationFailed && trimmedTurkish.isEmpty {
                    Text("Çeviri yapılamadı. İnternet bağlantını ya da Sistem Ayarları › Genel › Dil ve Bölge › Çeviri Dilleri'ni kontrol et.")
                } else {
                    fieldFooter
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if editingWord == nil, let existingMatch {
            existingSection(existingMatch)
        }

        Section("Cümleler") {
            ForEach($sentences) { $sentence in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Cümle", text: $sentence.text, prompt: Text("Kelimeyi gördüğün cümle"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                    if meaningOptions.count > 1 {
                        meaningPicker($sentence)
                            .labelsHidden()
                            .fixedSize()
                    }
                    if sentences.count > 1 || !sentence.text.isEmpty {
                        Button("Cümleyi Sil", systemImage: "minus.circle") { removeSentence(sentence.id) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Cümleyi sil")
                    }
                }
            }
            Button("Cümle Ekle", systemImage: "plus") { sentences.append(SentenceDraft()) }
                .buttonStyle(.borderless)
                .disabled(!canAddSentence)
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
            // Kelime zaten defterdeyse kaydedilemez; o durumda ⌘S satırdaki mevcut kayda ekleme düğmesini çalıştırır.
            if existingMatch == nil || editingWord != nil {
                Button(editingWord == nil ? "Kaydet" : "Güncelle", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("⌘S")
                    .disabled(!canSave)
            } else {
                Button("Kaydet", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            }
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


    /// Son satır doluysa yeni cümle satırı eklenebilir.
    private var canAddSentence: Bool {
        !(sentences.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false)
    }

    /// Cümlenin anlamı: Türkçe alanındaki anlamlar ya da "Belirsiz". Etiket artık anlamlar arasında yoksa (anlam
    /// değişti) kendi seçeneği olarak "(anlamlarda yok)" notuyla görünür: kullanıcı ne olduğunu görür, "Belirsiz"
    /// seçerse etiket gerçekten temizlenir, dokunmazsa kayıttaki etiket değişmez.
    private func meaningPicker(_ sentence: Binding<SentenceDraft>) -> some View {
        let options = meaningOptions
        let label = sentence.wrappedValue.meaning.trimmingCharacters(in: .whitespaces)
        let key = AnswerChecker.fold(label)
        let current = options.first { !key.isEmpty && AnswerChecker.fold($0) == key }
        let stale = key.isEmpty || current != nil ? nil : label
        let selection = Binding<String> {
            current ?? stale ?? ""
        } set: {
            sentence.wrappedValue.meaning = $0
        }
        return Picker("Anlamı", selection: selection) {
            Text("Belirsiz").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
            if let stale {
                Text("\(stale) (anlamlarda yok)").tag(stale)
            }
        }
        .pickerStyle(.menu)
    }

    private func removeSentence(_ id: String) {
        sentences.removeAll { $0.id == id }
        if sentences.isEmpty { sentences = [SentenceDraft()] }
    }

    private var suggestionRow: some View {
        HStack {
            Label {
                Text("Öneri: ") + Text(suggestion ?? "").fontWeight(.semibold)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.tint)
            }
            Spacer()
            Button("Kullan") {
                turkish = suggestion ?? ""
                suggestion = nil
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var fieldFooter: some View {
        if editingWord != nil, let existingMatch {
            Text("“\(existingMatch.english)” adında başka bir kayıt zaten var.")
                .foregroundStyle(.red)
        } else if didAutofill {
            Text("Türkçesi makine çevirisinden geldi; teknik anlamı farklıysa düzelt.")
        } else {
            Text("Birden fazla anlamı virgülle ayır; çalışırken herhangi birini yazman yeterli.")
        }
    }

    /// Aynı kelime yeniden eklenirken mevcut kayıt ve ne yapılabileceği.
    /// iPhone'da seçenekler bu bölümde satır olarak, Mac'te pencerenin eylem çubuğundadır.
    private func existingSection(_ word: Word) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: word.persistentModelID)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bu kelime zaten defterinde")
                        .font(.headline)
                    Text(existingHint(for: word))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            #if os(macOS)
            // Mac formu satır zeminini desteklemiyor; uyarı satırına kendi zeminini ver.
            // Menü penceresinin camı zemini soldurduğu için rengi koyulaştır ve kenarlık ekle.
            .padding(10)
            .background(Color.orange.opacity(0.28), in: .rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.7), lineWidth: 1)
            }
            #endif
            .listRowBackground(Self.warningBackground)

            #if os(macOS)
            // Sistem Ayarları'ndaki gibi: satırda bilgi solda, eylem sağda standart düğme.
            HStack(alignment: .center, spacing: 10) {
                MemoryRing(memory: word.memory(), size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(word.english)
                        .font(.system(.body, design: .serif, weight: .semibold))
                    Text("\(word.turkish) · \(Leitner.dueDescription(for: word.dueDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(absorbTitle(for: word)) { absorb(into: word) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canAbsorb(into: word))
                    .help("\(absorbDetail(for: word)) (⌘S)")
            }
            .padding(.vertical, 2)
            #else
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(word.english)
                        .font(.system(.body, design: .serif, weight: .semibold))
                    Text(word.turkish)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                // Kelimelerim satırındaki gibi halka ve yüzde yan yana.
                MemoryRing(memory: word.memory(), size: 18, text: .trailing)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .listRowBackground(Self.warningBackground)
            #endif
            #if os(iOS)
            existingOption(
                absorbTitle(for: word), detail: absorbDetail(for: word),
                systemImage: "plus.circle.fill", enabled: canAbsorb(into: word)
            ) { absorb(into: word) }
            .listRowBackground(Self.warningBackground)
            #endif
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Uyarı bölümünün turuncu tonlu zemini.
    private static let warningBackground = Color.orange.opacity(0.18)

    /// Kelime zaten defterdeyse İngilizce alanının yanında beliren turuncu simge.
    private var existingIcon: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
            .symbolEffect(.bounce, value: existingMatch?.persistentModelID)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Bu kelime zaten defterinde")
    }

    private func canAbsorb(into word: Word) -> Bool {
        word.wouldAbsorb(turkish: trimmedTurkish, sentences: filledSentences.map(\.text))
    }

    /// Mevcut kayda eklenecek yeni cümle var mı (kayıtta zaten olan cümle yeniden eklenmez).
    private func addsSentences(to word: Word) -> Bool {
        filledSentences.contains { word.addsSentence($0.text) }
    }

    /// Uyarının altındaki kısa açıklama: gelen cümle kayıtta yoksa bunu söyler.
    private func existingHint(for word: Word) -> String {
        if addsSentences(to: word) {
            return "Yeni bir cümleyle geldi; kayıttaki cümlelerin yanına eklenir."
        }
        #if os(macOS)
        return "Türkçesi alanına yeni bir anlam yazıp mevcut kayda ekleyebilirsin."
        #else
        return "Yeni bir anlam yazarsan mevcut kayda ekleyebilirsin."
        #endif
    }

    /// Mevcut kayda ekleme eyleminin adı, neyi değiştireceğine göre.
    private func absorbTitle(for word: Word) -> String {
        let meanings = word.addsMeanings(trimmedTurkish)
        switch (meanings, addsSentences(to: word)) {
        case (true, true): return "Kaydı Güncelle"
        case (false, true): return "Cümleyi Ekle"
        default: return "Anlamları Ekle"
        }
    }

    private func absorbDetail(for word: Word) -> String {
        let meanings = word.addsMeanings(trimmedTurkish)
        switch (meanings, addsSentences(to: word)) {
        case (true, true): return "Yeni anlamlar ve cümle mevcut kayda eklenir; ilerleme korunur."
        case (false, true): return "Cümle mevcut kayda eklenir; ilerleme korunur."
        default: return "Yeni anlamlar mevcut kayda eklenir; ilerleme korunur."
        }
    }

    #if os(iOS)
    /// Ayarlar'daki gibi başlık ve kısa açıklamalı seçenek satırı.
    private func existingOption(
        _ title: String, detail: String, systemImage: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        // Form düğmenin içindeki .secondary'yi de vurgu rengine boyuyor; gri tonlar sabit renkle.
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(enabled ? Color.accentColor : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(enabled ? Color.accentColor : Color(.secondaryLabel))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(enabled ? Color(.secondaryLabel) : Color(.tertiaryLabel))
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(!enabled)
    }
    #endif

    /// Defterdeki ilişkili kelime ve kalıplar; kaydı engellemez, yalnızca hatırlatır.
    private var relatedRow: some View {
        Label {
            Text("Defterinde ilişkili: ")
                + Text(relatedWords.prefix(3).map { "\($0.english) (\(Self.firstMeaning($0.turkish)))" }.joined(separator: ", "))
                .fontWeight(.medium)
        } icon: {
            Image(systemName: "link").foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
    }

    private static func firstMeaning(_ turkish: String) -> String {
        turkish.split(whereSeparator: { ",;/".contains($0) }).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? turkish
    }

    // MARK: - İşlemler

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let word = editingWord {
            english = word.english
            turkish = word.turkish
            // Kayda alınmamış eski cümle önce kayda alınır (yalnız uygulamada; eklenti göç yapmaz).
            if !SharedStore.isExtension { word.importLegacyExample() }
            let loaded = word.exampleSentences.map { SentenceDraft(id: $0.id, text: $0.text, meaning: $0.meaning) }
            sentences = loaded.isEmpty ? [SentenceDraft()] : loaded
            loadedSentences = sentences
        } else {
            english = draft.english
            sentences = [SentenceDraft(text: draft.example)]
            if !english.isEmpty && existingMatch == nil {
                // Paylaşılan kelime geldi; sıra Türkçesinde. Zaten defterdeyse klavye "Zaten defterinde"
                // uyarısını örtmesin diye odak verilmez.
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

    private func tapWord(at index: Int) {
        selection = SharedTextParser.select(index, current: validSelection)
        english = selection.map { SharedTextParser.phrase(sentenceWords, $0) } ?? ""
        // Seçilen kelime zaten defterdeyse klavye kapanır; açık kalsa uyarıyı örterdi.
        if selection != nil { focusedField = existingMatch == nil ? .turkish : nil }
    }

    private func save() {
        guard canSave else { return }

        if let word = editingWord {
            word.english = trimmedEnglish
            word.turkish = trimmedTurkish
            applySentences(to: word)
            guard commit() else { return }
            dismiss()
        } else {
            let word = Word(english: trimmedEnglish, turkish: trimmedTurkish)
            context.insert(word)
            applySentences(to: word)
            finishAdding(message: "“\(trimmedEnglish)” eklendi")
        }
    }

    /// Formdaki cümleleri kayda yazar (bkz. `Word.applySentenceDrafts`): yalnız formda yüklenip kaldırılan kayıt silinir.
    private func applySentences(to word: Word) {
        word.applySentenceDrafts(filledSentences, loaded: Self.filled(loadedSentences))
    }

    /// Aynı kelime yeniden eklenirken yeni bilgileri mevcut kayda katar; yeni cümleler de tutulur.
    private func absorb(into word: Word) {
        word.absorb(turkish: trimmedTurkish, sentences: filledSentences.map { ($0.text, $0.meaning) })
        finishAdding(message: "“\(word.english)” güncellendi")
    }

    private func finishAdding(message: String) {
        // Eklenti hemen kapanabilir; otomatik kaydı beklemeden diske yaz.
        // Yazılamazsa kaydedilmiş sayılmaz: eklenti kapanmaz, form doluyken uyarı çıkar.
        guard commit() else { return }
        if let onFinish {
            onFinish(true)
            return
        }
        english = ""
        turkish = ""
        sentences = [SentenceDraft()]
        selection = nil
        resetTranslation()
        savedMessage = message
        savedCount += 1
        focusedField = .english
    }

    /// Değişiklikleri diske yazar. Olmazsa bekleyen değişiklikleri geri alır (yeniden denemede
    /// kelime iki kez eklenmesin, otomatik kayıt yarım işi sonra yazmasın) ve uyarı gösterir.
    private func commit() -> Bool {
        if context.saveLogging() { return true }
        context.rollback()
        saveFailed = true
        return false
    }

    #if os(iOS)
    private func delete(_ word: Word) {
        context.delete(word)
        guard commit() else { return }
        dismiss()
    }
    #endif

    private func cancel() {
        if hasChanges {
            confirmDiscard = true
        } else if let onFinish {
            onFinish(false)
        } else {
            dismiss()
        }
    }

    private func translate() {
        isTranslating = true
        translationFailed = false
        translatingTerm = trimmedEnglish
        if translationConfig == nil {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "tr")
            )
        } else {
            translationConfig?.invalidate()
        }
    }

    /// Süren isteği unutur; sonucu geç gelirse `applyTranslation` onu atar.
    private func resetTranslation() {
        isTranslating = false
        translatingTerm = nil
    }

    private func applyTranslation(_ text: String?, for term: String) {
        // İstek sürerken kelime değiştiyse (başka çip seçildi, kaydedildi, temizlendi) sonuç eskidir.
        guard Self.translationIsCurrent(requested: term, pending: translatingTerm, english: trimmedEnglish) else { return }
        resetTranslation()
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

extension WordFormView {
    /// Çeviri sonucu ancak istenen terim hâlâ süren istekse ve İngilizce alanı değişmediyse kullanılır.
    nonisolated static func translationIsCurrent(requested: String, pending: String?, english: String) -> Bool {
        pending == requested && requested == english
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
