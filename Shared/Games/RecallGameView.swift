import SwiftData
import SwiftUI

/// Hatırlama oyunu: Günlük Tekrar, Yeni Eklenenler ve Ters Yön. Kart ve cevap çubuğu eski Çalış ekranıyla aynı;
/// Günlük Tekrar'da yeni ve zayıf kelimeler önce Çoktan Seçmeli, sonra Harfleri Diz ile de sorulur (`DailyMix`).
/// Tur bitince özet gösterilir. Oyun merkezinden tam ekran açılır.
struct RecallGameView: View {
    let plan: StudySession.Plan
    let mode: GameMode
    /// Mac'te oyun menü penceresinin içinde açılır; kapatınca oyun merkezine dönülür. iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil
    /// Mac: "Bir Tur Daha" Günlük Tekrar'a (ya da "Yine de Çalış"a) geçecekse turu menü penceresinin
    /// kalıcı Günlük Tekrar oturumuna devreder. `nil` ise tur burada başlar.
    var onDailyHandoff: ((StudySession.Plan) -> Void)? = nil

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session = StudySession()
    @State private var didStart = false

    var body: some View {
        GameScaffold(showsBar: session.current != nil, onClose: close) {
            GameProgressHeader(done: session.finishedWordCount, total: session.wordCount)
        } content: {
            content
        }
        .sensoryFeedback(.selection, trigger: session.reviewedCount)
        .pausesClock {
            session.pauseClock()
            // Uygulama arka planda kapatılabilir; açık cevap kaybolmasın.
            session.commitPendingAnswer()
            context.saveLogging()
        } resume: {
            session.resumeClock()
        }
        .onAppear {
            if !didStart { startRound() }
        }
        // Kelime eklenince ya da silinince (ör. başka cihazdan) sıra güncellenir; silinen kelime atlanır.
        .onChange(of: words.aliveIDs) {
            session.sync(with: words)
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.current != nil {
            DailyStepView(session: session, words: words)
        } else if didStart {
            let next = nextPlan
            RoundSummaryView(
                entries: session.roundEntries.map(RoundSummaryView.Entry.init),
                duration: session.finishedAt.timeIntervalSince(session.startedAt),
                roundStartedAt: session.roundBeganAt,
                againTitle: StudySession.againTitle(after: session.plan, next: next),
                onAgain: { again(with: next) },
                onDone: close
            )
        }
    }

    /// "Bir Tur Daha"nın açacağı tur (bekleyen yeni kelime kalmadıysa Günlük Tekrar, iş kalmadıysa en zayıflar).
    private var nextPlan: StudySession.Plan {
        StudySession.againPlan(after: plan, words: words)
    }

    private func again(with next: StudySession.Plan) {
        // Mac'te Günlük Tekrar menü penceresinin kalıcı turunda sürer; ikinci bir tur açılmaz.
        if next != session.plan, next == .daily || next == .extraPractice, let onDailyHandoff {
            onDailyHandoff(next)
        } else {
            startRound(plan: next)
        }
    }

    private func startRound() {
        startRound(plan: plan)
    }

    private func startRound(plan: StudySession.Plan) {
        session.mode = mode
        session.start(with: words, plan: plan)
        // Soracak kelime kalmadıysa (ör. açılışta) aynı sırayla bir sonraki akışa geçilir.
        let next = StudySession.againPlan(after: plan, words: words)
        if session.current == nil && next != plan {
            session.start(with: words, plan: next)
            if session.current == nil && next == .daily {
                session.start(with: words, plan: .extraPractice)
            }
        }
        didStart = true
    }

    private func close() {
        session.gradePendingAnswer()
        context.saveLogging()
        if let onClose { onClose() } else { dismiss() }
    }
}



/// Tek bir hatırlama sorusu: kart ve altta cevap çubuğu (Göster / ↑, sonra not düğmeleri).
/// Günlük Tekrar, Hızlı Tur, Ters Yön ve karışık Hızlı Tur kullanır; cevabı `session` değerlendirir ve kaydeder.
/// Mac'te klavyeyle oynanır: Return kontrol eder (boşken gösterir), sonra Return öne çıkan notu,
/// ← Bilemedim, → Bildim seçer.
struct RecallQuestionView: View {
    let session: StudySession
    /// İlişkili kelimeleri bulmak için bütün defter.
    let words: [Word]
    /// Not düğmesine basılınca (cevap kaydedildikten sonra) çağrılır.
    var onGraded: () -> Void = {}

    @State private var answer = ""
    @FocusState private var answerFocused: Bool
    #if os(iOS)
    /// Klavyenin en son kapandığı an; karta dokunuş klavyeyi kapatmak için miydi, anlamak için.
    @State private var keyboardHiddenAt = Date.distantPast
    @Namespace private var glassNamespace
    #endif

    private var hasAnswer: Bool { !answer.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Silinmiş kelime çizilmez; oyun kimlik kümesi değişince onu atlar.
        if let word = session.current, !word.isGone(from: words.aliveIDs) {
            ScrollView {
                card(for: word)
                    .gamePagePadding()
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #else
            .scrollBounceBehavior(.basedOnSize)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .gameBarPadding()
            }
            .animation(.snappy, value: session.phase)
            // Yazarak cevaplamak asıl yol: klavye her kartta açık gelir. Bakmak isteyen "Göster"e basar.
            .onAppear { answerFocused = true }
            // Kelime silinip sıra kendiliğinden ilerlerse önceki kelimeye yazılan cevap yeni kartta kalmasın.
            .onChange(of: session.currentStep?.id) { answer = "" }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHiddenAt = .now
            }
            #endif
            .sensoryFeedback(trigger: session.phase) { _, phase in
                guard case .revealed(let verdict) = phase else { return nil }
                return switch verdict {
                case .correct, .almost, .synonymOf: .success
                case .incorrect: .warning
                case .peeked: nil
                }
            }
        }
    }

    // MARK: - Kart

    private func card(for word: Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Soru kartında yüzde gösterilmez (yalnızca ayrıntı ve ilerleme ekranlarında).
            HStack(spacing: 6) {
                Spacer(minLength: 12)
                MemoryRing(memory: word.memory(), size: 12, isLapsed: word.isLapsed)
                if word.isNew { Text("Yeni") }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if session.isReverse {
                // Ters Yön: Türkçesi sorulur; İngilizce kelime, telaffuz ve cümle cevapla birlikte açılır.
                Text(word.turkish)
                    .font(.largeTitle.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                englishHeadline(word, font: GameStyle.headline)
                exampleSentence(word)
            }

            if case .revealed(let verdict) = session.phase {
                answerReveal(for: word, verdict: verdict)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .gameCard()
        // Mac'te kart tıklamayla açılmaz (yanlışlıkla tıklayınca cevap görünüyordu); Göster düğmesi ya da ↩.
        #if os(iOS)
        .contentShape(.rect(cornerRadius: GameStyle.cardRadius, style: .continuous))
        .onTapGesture {
            guard session.phase == .asking else { return }
            // Klavye açıkken karta dokunmak yalnızca klavyeyi kapatır. Pencerenin genel dokunuşu
            // (`dismissesKeyboardOnTap`) klavyeyi bu dokunuştan önce kapatmış olabilir; ona da bakılır.
            if answerFocused || Date.now.timeIntervalSince(keyboardHiddenAt) < 0.4 {
                answerFocused = false
            } else {
                reveal(withAnswer: false)
            }
        }
        .accessibilityAddTraits(session.phase == .asking ? .isButton : [])
        .accessibilityHint(session.phase == .asking ? (session.isReverse ? "İngilizcesini göster" : "Türkçesini göster") : "")
        #endif
    }

    private func englishHeadline(_ word: Word, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(word.english)
                .font(font)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Spacer(minLength: 12)
            Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                Speaker.shared.speak(word.english)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            #if os(macOS)
            .help("Telaffuzu dinle")
            #endif
        }
    }

    @ViewBuilder
    private func exampleSentence(_ word: Word) -> some View {
        if !word.example.isEmpty {
            Text(AttributedString(quoting: word.example, highlighting: word.english))
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answerReveal(for word: Word, verdict: StudySession.Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.bottom, 4)
            verdictLabel(verdict, word: word)
            if session.isReverse {
                englishHeadline(word, font: .system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(.tint)
                exampleSentence(word)
            } else {
                Text(word.turkish)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch verdict {
            case .incorrect:
                Text(session.isReverse
                     ? "Senin cevabın: “\(answer)”. Eşanlamlıysa Doğru Say'a bas."
                     : "Senin cevabın: “\(answer)”. Anlamca aynıysa Doğru Say'a bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .almost:
                Text("Senin cevabın: “\(answer)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .synonymOf(let other):
                Text("“\(other)” de aynı anlamda; doğru sayıldı.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .correct, .peeked:
                EmptyView()
            }
            let related = word.related(in: words)
            if !related.isEmpty {
                Label {
                    Text("İlişkili: ") + Text(related.prefix(3).map(\.english).joined(separator: ", ")).fontWeight(.medium)
                } icon: {
                    Image(systemName: "link")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func verdictLabel(_ verdict: StudySession.Verdict, word: Word) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru", "checkmark.circle.fill", .green)
        case .almost: ("Neredeyse", "checkmark.circle.fill", .orange)
        case .synonymOf: ("Doğru, ama bu kartta aranan: \(word.english)", "checkmark.circle.fill", .orange)
        case .incorrect: ("Tam tutmadı", "xmark.circle.fill", .red)
        case .peeked: ("Cevaba baktın. Biliyor muydun?", "eye.fill", .secondary)
        }
        return Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    // MARK: - Alt çubuk

    @ViewBuilder
    private var bottomBar: some View {
        switch session.phase {
        case .asking:
            askBar
        case .revealed(let verdict):
            HStack(spacing: 12) {
                ForEach(verdict.gradeOptions) { gradeButton($0) }
            }
        }
    }

    #if os(iOS)
    /// Mesajlar'daki gibi tek eylem düğmesi: alan boşken "Göster", yazınca "Kontrol et".
    private var askBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField(session.isReverse ? "İngilizcesi" : "Türkçesi", text: $answer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($answerFocused)
                    // Alan boşken "Bitti" yalnızca klavyeyi kapatır; bakmak için "Göster" var.
                    .onSubmit {
                        if hasAnswer { reveal(withAnswer: true) } else { answerFocused = false }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)

                if hasAnswer {
                    Button("Kontrol et", systemImage: "arrow.up") { reveal(withAnswer: true) }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                        .glassEffectID("action", in: glassNamespace)
                } else {
                    Button("Göster") { reveal(withAnswer: false) }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("action", in: glassNamespace)
                        .accessibilityHint(session.isReverse ? "İngilizcesini gösterir" : "Türkçesini gösterir")
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: hasAnswer)
    }
    #else
    /// Tek eylem düğmesi: alan boşken "Göster", yazınca "Kontrol et". Return ikisini de yapar.
    private var askBar: some View {
        HStack(spacing: 8) {
            TextField(session.isReverse ? "İngilizcesi" : "Türkçesi", text: $answer)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($answerFocused)
                .onSubmit { reveal(withAnswer: hasAnswer) }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
            if hasAnswer {
                Button("Kontrol et", systemImage: "arrow.up") { reveal(withAnswer: true) }
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .help("Kontrol et (↩)")
            } else {
                Button("Göster") { reveal(withAnswer: false) }
                    .buttonStyle(.glass)
                    // Yazı alanı odakta olmasa da ↩ cevabı gösterir (kart artık tıklamayla açılmıyor).
                    .keyboardShortcut(.defaultAction)
                    .help(session.isReverse ? "İngilizcesini göster (↩)" : "Türkçesini göster (↩)")
            }
        }
        .controlSize(.large)
        .animation(.snappy(duration: 0.2), value: hasAnswer)
    }
    #endif

    @ViewBuilder
    private func gradeButton(_ option: GradeOption) -> some View {
        let button = Button {
            session.grade(known: option.known)
            answer = ""
            onGraded()
            if session.current != nil { answerFocused = true }
        } label: {
            Label(option.title, systemImage: option.systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                #if os(iOS)
                .padding(.vertical, 6)
                #endif
        }
        .controlSize(.large)
        #if os(macOS)
        // Öne çıkan düğme Return ile, diğerleri ← (bilemedim) / → (bildim) ile basılır.
        .keyboardShortcut(option.isPrimary ? .defaultAction : KeyboardShortcut(option.known ? .rightArrow : .leftArrow, modifiers: []))
        .help(option.isPrimary ? "\(option.title) (↩)" : "\(option.title) (\(option.known ? "→" : "←"))")
        #endif
        // Mac'te renk verilen cam düğme de dolu görünüyor; öne çıkmayanın yalnızca yazısı renkli.
        if option.isPrimary {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(option.known ? .green : .red)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        #if os(iOS)
        answerFocused = false
        #endif
        session.reveal(answer: withAnswer ? answer : nil)
    }
}
