import SwiftData
import SwiftUI

/// Hatırlama oyunu: Günlük Tekrar ve Hızlı Tur. Kart ve cevap çubuğu eski Çalış ekranıyla aynı;
/// tur bitince özet gösterilir. Oyun merkezinden tam ekran açılır.
struct RecallGameView: View {
    let plan: StudySession.Plan
    let mode: GameMode

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session = StudySession()
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if session.current != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { close() }
                                .accessibilityLabel("Kapat")
                        }
                        ToolbarItem(placement: .principal) {
                            GameProgressHeader(done: session.finishedWordCount, total: session.wordCount)
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: session.reviewedCount)
        }
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
            RecallQuestionView(session: session, words: words)
        } else if didStart {
            RoundSummaryView(
                entries: session.roundEntries.map {
                    RoundSummaryView.Entry(word: $0.word, before: $0.memoryBefore, correct: $0.firstCorrect)
                },
                duration: session.finishedAt.timeIntervalSince(session.startedAt),
                onAgain: startRound,
                onDone: close
            )
        }
    }

    private func startRound() {
        session.mode = mode
        session.start(with: words, plan: plan)
        // Günlük Tekrar'dan sonra zayıf kelime kalmadıysa "Bir Tur Daha" en zayıflarla devam eder.
        if session.current == nil && plan == .daily {
            session.start(with: words, plan: .extraPractice)
        }
        didStart = true
    }

    private func close() {
        session.gradePendingAnswer()
        context.saveLogging()
        dismiss()
    }
}


/// Tek bir hatırlama sorusu: kart ve altta cevap çubuğu (Göster / ↑, sonra not düğmeleri).
/// Günlük Tekrar, Hızlı Tur, Ters Yön ve karışık Hızlı Tur kullanır; cevabı `session` değerlendirir ve kaydeder.
struct RecallQuestionView: View {
    let session: StudySession
    /// İlişkili kelimeleri bulmak için bütün defter.
    let words: [Word]
    /// Not düğmesine basılınca (cevap kaydedildikten sonra) çağrılır.
    var onGraded: () -> Void = {}

    @State private var answer = ""
    @FocusState private var answerFocused: Bool
    /// Klavyenin en son kapandığı an; karta dokunuş klavyeyi kapatmak için miydi, anlamak için.
    @State private var keyboardHiddenAt = Date.distantPast
    @Namespace private var glassNamespace

    private var hasAnswer: Bool { !answer.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Silinmiş kelime çizilmez; oyun kimlik kümesi değişince onu atlar.
        if let word = session.current, !word.isGone(from: words.aliveIDs) {
            ScrollView {
                card(for: word)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .animation(.snappy, value: session.phase)
            // Yazarak cevaplamak asıl yol: klavye her kartta açık gelir. Bakmak isteyen "Göster"e basar.
            .onAppear { answerFocused = true }
            // Kelime silinip sıra kendiliğinden ilerlerse önceki kelimeye yazılan cevap yeni kartta kalmasın.
            .onChange(of: session.current.map(ObjectIdentifier.init)) { answer = "" }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHiddenAt = .now
            }
            .sensoryFeedback(trigger: session.phase) { _, phase in
                guard case .revealed(let verdict) = phase else { return nil }
                return switch verdict {
                case .correct, .almost: .success
                case .incorrect: .warning
                case .peeked: nil
                }
            }
        }
    }

    // MARK: - Kart

    private func card(for word: Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Spacer(minLength: 12)
                MemoryRing(memory: word.memory(), size: 12, text: .trailing)
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
                englishHeadline(word, font: .system(.largeTitle, design: .serif, weight: .semibold))
                exampleSentence(word)
            }

            if case .revealed(let verdict) = session.phase {
                answerReveal(for: word, verdict: verdict)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
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
            verdictLabel(verdict)
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
            if verdict == .incorrect {
                Text(session.isReverse
                     ? "Senin cevabın: “\(answer)”. Eşanlamlıysa Doğru Say'a bas."
                     : "Senin cevabın: “\(answer)”. Anlamca aynıysa Doğru Say'a bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    private func verdictLabel(_ verdict: StudySession.Verdict) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru", "checkmark.circle.fill", .green)
        case .almost: ("Neredeyse", "checkmark.circle.fill", .orange)
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
            // Mesajlar'daki gibi tek eylem düğmesi: alan boşken "Göster", yazınca "Kontrol et".
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
        case .revealed(let verdict):
            HStack(spacing: 12) {
                ForEach(verdict.gradeOptions) { gradeButton($0) }
            }
        }
    }

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
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        if option.isPrimary {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(option.known ? .green : .red)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        answerFocused = false
        session.reveal(answer: withAnswer ? answer : nil)
    }
}

extension View {
    /// Uygulama arka plana gidince cevap süresini durdurur, geri gelince sürdürür.
    func pausesClock(_ pause: @escaping () -> Void, resume: @escaping () -> Void) -> some View {
        modifier(ClockPauser(pause: pause, resume: resume))
    }
}

private struct ClockPauser: ViewModifier {
    let pause: () -> Void
    let resume: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { old, new in
            if new == .active { resume() } else if old == .active { pause() }
        }
    }
}

/// Oyunların üstündeki ince ilerleme çubuğu ve "3/10".
struct GameProgressHeader: View {
    let done: Int
    let total: Int
    /// Eşleştir gibi soru sırası olmayan oyunlarda yalnızca çubuk gösterilir.
    var showsCount = true

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(width: 150)
            if showsCount {
                Text("\(min(done + 1, total))/\(total)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) kelimeden \(min(done + 1, total)). kelime")
    }
}
