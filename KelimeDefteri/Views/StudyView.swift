import SwiftData
import SwiftUI

struct StudyView: View {
    var onAddTapped: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @State private var session = StudySession()
    @State private var answer = ""
    @State private var showSettings = false
    @AppStorage(ReminderSettings.enabledKey) private var reminderEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var answerFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Çalış")
                .navigationSubtitle(subtitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ayarlar", systemImage: "gearshape") { showSettings = true }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack { SettingsView() }
                }
                .sensoryFeedback(.selection, trigger: session.reviewedCount)
        }
        .onAppear {
            if session.current == nil { session.start(with: words, practiceAll: false) }
        }
        .onChange(of: words.count) {
            session.sync(with: words)
        }
        // Gece yarısı geçince ya da uygulamaya dönülünce zamanı gelen kelimeler de sıraya girsin.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.sync(with: words) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if words.isEmpty {
            emptyDeck
        } else if let word = session.current {
            ScrollView {
                VStack(spacing: 16) {
                    ProgressView(value: progress)
                        .accessibilityLabel("Tur ilerlemesi")
                    card(for: word)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .animation(.snappy, value: session.phase)
        } else {
            finished
        }
    }

    private var subtitle: String {
        if words.isEmpty { return "" }
        if session.current != nil {
            return "\(session.remaining + 1) kelime kaldı"
        }
        return DeckSummary.text(for: words)
    }

    /// Turda cevaplanan kartların oranı. Bilinmeyen kelime sıraya yeniden girdiği için
    /// toplam da onunla büyür.
    private var progress: Double {
        let total = session.reviewedCount + session.remaining + 1
        return Double(session.reviewedCount) / Double(total)
    }

    // MARK: - Kart

    private func card(for word: Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                if !word.source.isEmpty {
                    Image(systemName: "book.closed")
                    Text(word.source)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                BoxRing(box: word.box, size: 12)
                Text("Kutu \(word.box)/\(Leitner.maxBox)")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(word.english)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
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

            if !word.example.isEmpty {
                Text(AttributedString(quoting: word.example, highlighting: word.english))
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            if session.phase == .asking { reveal(withAnswer: false) }
        }
        .accessibilityAddTraits(session.phase == .asking ? .isButton : [])
        .accessibilityHint(session.phase == .asking ? "Türkçesini göster" : "")
    }

    private func answerReveal(for word: Word, verdict: StudySession.Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.bottom, 4)
            verdictLabel(verdict)
            Text(word.turkish)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .fixedSize(horizontal: false, vertical: true)
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verdict == .incorrect {
                Text("Senin cevabın: “\(answer)”. Anlamca aynıysa Bildim'e bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func verdictLabel(_ verdict: StudySession.Verdict) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru", "checkmark.circle.fill", .green)
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
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Cevabı göster", systemImage: "eye") { reveal(withAnswer: false) }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)

                    TextField("Türkçesi", text: $answer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($answerFocused)
                        .onSubmit { reveal(withAnswer: true) }
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive(), in: .capsule)

                    Button("Kontrol et", systemImage: "checkmark") { reveal(withAnswer: true) }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.white)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                }
            }
        case .revealed(let verdict):
            HStack(spacing: 12) {
                gradeButton("Bilemedim", systemImage: "xmark", known: false, color: .red, prominent: verdict != .correct)
                gradeButton("Bildim", systemImage: "checkmark", known: true, color: .green, prominent: verdict == .correct)
            }
            .sensoryFeedback(verdict == .correct ? .success : .warning, trigger: verdict)
        }
    }

    @ViewBuilder
    private func gradeButton(_ title: String, systemImage: String, known: Bool, color: Color, prominent: Bool) -> some View {
        let button = Button {
            session.grade(known: known)
            answer = ""
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        .tint(color)
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        answerFocused = false
        session.reveal(answer: withAnswer ? answer : nil)
    }

    // MARK: - Boş ve bitti ekranları

    private var emptyDeck: some View {
        ContentUnavailableView {
            Label("Defterin Boş", systemImage: "book.closed")
        } description: {
            Text("Okurken takıldığın ilk kelimeyi ekle, burada sana sorayım.")
        } actions: {
            Button("Kelime Ekle", action: onAddTapped)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }

    private var finished: some View {
        ContentUnavailableView {
            Label(session.isPracticeAll ? "Tur Bitti" : "Bugünlük Bu Kadar", systemImage: "checkmark.circle")
        } description: {
            Text(finishedDescription)
        } actions: {
            VStack(spacing: 12) {
                Button {
                    session.start(with: words, practiceAll: true)
                } label: {
                    Text("Hepsini Çalış").frame(minWidth: 160)
                }
                .buttonStyle(.glassProminent)
                Button(action: onAddTapped) {
                    Text("Kelime Ekle").frame(minWidth: 160)
                }
                .buttonStyle(.glass)
                if !reminderEnabled {
                    Button("Her Gün Hatırlat", systemImage: "bell") { showSettings = true }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                }
            }
            .controlSize(.large)
        }
    }

    private var finishedDescription: String {
        var lines: [String] = []
        if session.reviewedCount > 0 {
            lines.append("Bu turda \(session.reviewedCount) cevap verdin.")
        }
        if let next = words.map(\.dueDate).filter({ $0 > .now }).min() {
            let when = Leitner.dueDescription(for: next)
            lines.append("Sıradaki tekrar: \(when.lowercased(with: Locale(identifier: "tr_TR"))).")
        }
        return lines.joined(separator: "\n")
    }
}

#if DEBUG
#Preview {
    StudyView(onAddTapped: {})
        .modelContainer(PreviewData.container)
}
#endif
