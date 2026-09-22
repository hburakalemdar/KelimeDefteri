import SwiftData
import SwiftUI

struct StudyView: View {
    var onAddTapped: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @State private var session = StudySession()
    @State private var answer = ""
    @State private var showSettings = false
    @AppStorage(ReminderSettings.enabledKey) private var reminderEnabled = false
    @FocusState private var answerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if words.isEmpty {
                        emptyDeck
                    } else if let word = session.current {
                        studyCard(for: word)
                    } else {
                        finished
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Çalış")
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
            if session.current == nil && !session.isPracticeAll {
                session.start(with: words, practiceAll: false)
            }
        }
    }

    // MARK: - Kart

    private func studyCard(for word: Word) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(word.source)
                        .lineLimit(1)
                    Spacer()
                    Text("kutu \(word.box)/\(Leitner.maxBox) · \(session.remaining) kaldı")
                        .monospacedDigit()
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(word.english)
                        .font(.system(size: 38, weight: .semibold, design: .serif))
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Button {
                        Speaker.shared.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Telaffuzu dinle")
                }

                if !word.example.isEmpty {
                    Text(Self.highlight(word.english, in: word.example))
                        .font(.system(.body, design: .serif).italic())
                        .foregroundStyle(.secondary)
                }

                revealArea(for: word)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
            .onTapGesture {
                if session.phase == .asking { reveal(withAnswer: false) }
            }
            .accessibilityAddTraits(session.phase == .asking ? .isButton : [])
            .accessibilityHint(session.phase == .asking ? "Türkçesini göster" : "")

            answerArea
        }
        .animation(.snappy, value: session.phase)
    }

    @ViewBuilder
    private func revealArea(for word: Word) -> some View {
        if session.phase == .asking {
            Text("Bilmiyorsan karta dokun, Türkçesini göreyim.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(word.turkish)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color("HighlightText"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color("Highlight"), in: .rect(cornerRadius: 4))
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                if !word.definition.isEmpty {
                    Text(word.definition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !answer.isEmpty {
                    Text("Senin cevabın: \(answer)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Cevap

    @ViewBuilder
    private var answerArea: some View {
        switch session.phase {
        case .asking:
            HStack {
                TextField("Hatırladığın Türkçesi", text: $answer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($answerFocused)
                    .onSubmit { reveal(withAnswer: true) }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                Button("Kontrol et") { reveal(withAnswer: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .revealed(let verdict):
            VStack(spacing: 12) {
                verdictBanner(verdict)
                HStack(spacing: 12) {
                    gradeButton("Bilemedim", known: false, color: .red, prominent: verdict != .correct)
                    gradeButton("Bildim", known: true, color: .green, prominent: verdict == .correct)
                }
            }
            .sensoryFeedback(verdict == .correct ? .success : .warning, trigger: verdict)
        }
    }

    private func verdictBanner(_ verdict: StudySession.Verdict) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru!", "checkmark.circle.fill", .green)
        case .incorrect: ("Tam tutmadı. Anlamca aynıysa “Bildim”i seç.", "xmark.circle.fill", .red)
        case .peeked: ("Türkçesine baktın. Biliyor muydun?", "eye.fill", .secondary)
        }
        return Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func gradeButton(_ title: String, known: Bool, color: Color, prominent: Bool) -> some View {
        let button = Button {
            session.grade(known: known)
            answer = ""
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .tint(color)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
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
            Label("Defterin boş", systemImage: "book.closed")
        } description: {
            Text("Okurken takıldığın ilk kelimeyi ekle, burada sana sorayım.")
        } actions: {
            Button("Kelime ekle", action: onAddTapped)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    private var finished: some View {
        ContentUnavailableView {
            Label(session.isPracticeAll ? "Tur bitti" : "Bugünlük bu kadar", systemImage: "checkmark.seal")
        } description: {
            VStack(spacing: 6) {
                if session.reviewedCount > 0 {
                    Text("Bu turda \(session.reviewedCount) cevap verdin.")
                }
                if let next = words.map(\.dueDate).filter({ $0 > .now }).min() {
                    Text("Sıradaki tekrar \(next.formatted(.relative(presentation: .named)))")
                }
                StatsLine(words: words)
                    .padding(.top, 6)
            }
        } actions: {
            Button("Yine de hepsini çalış") {
                session.start(with: words, practiceAll: true)
            }
            .buttonStyle(.borderedProminent)
            Button("Kelime ekle", action: onAddTapped)
            if !reminderEnabled {
                Button("Her gün hatırlat", systemImage: "bell") { showSettings = true }
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Yardımcı

    static func highlight(_ word: String, in sentence: String) -> AttributedString {
        var text = AttributedString("“\(sentence)”")
        if let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
            text[range].foregroundColor = .primary
        }
        return text
    }
}

#Preview {
    StudyView(onAddTapped: {})
        .modelContainer(PreviewData.container)
}
