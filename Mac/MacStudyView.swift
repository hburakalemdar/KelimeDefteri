import SwiftData
import SwiftUI

/// Menü çubuğu penceresindeki çalışma kartı; iOS'taki Çalış ekranının Mac karşılığı.
/// Klavyeyle kullanılabilir: Return kontrol eder, ⌘Return gösterir, ← Bilemedim, → Bildim.
struct MacStudyView: View {
    var onAddTapped: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @State private var session = StudySession()
    @State private var answer = ""
    @FocusState private var answerFocused: Bool

    var body: some View {
        Group {
            if words.isEmpty {
                ContentUnavailableView {
                    Label("Defterin Boş", systemImage: "book.closed")
                } description: {
                    Text("Okurken takıldığın ilk kelimeyi ekle, burada sana sorayım.")
                } actions: {
                    Button("Kelime Ekle", action: onAddTapped)
                        .buttonStyle(.glassProminent)
                }
            } else if let word = session.current {
                studyPage(for: word)
            } else {
                finished
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Pencere her açıldığında gün dönmüş olabilir; zamanı gelenleri sıraya al.
            if session.current == nil && !session.isPracticeAll {
                session.start(with: words, practiceAll: false)
            } else {
                session.sync(with: words)
            }
        }
        .onChange(of: words.count) {
            session.sync(with: words)
        }
    }

    /// Turda cevaplanan kartların oranı; bilinmeyen kelime sıraya yeniden girdiği için
    /// toplam da onunla büyür.
    private var progress: Double {
        let total = session.reviewedCount + session.remaining + 1
        return Double(session.reviewedCount) / Double(total)
    }

    // MARK: - Kart

    private func studyPage(for word: Word) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .accessibilityLabel("Tur ilerlemesi")
                Text("\(session.remaining + 1) kaldı")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }

            ScrollView {
                card(for: word)
            }
            .scrollBounceBehavior(.basedOnSize)

            if session.phase == .asking {
                askBar
            } else {
                gradeBar
            }
        }
        .padding(14)
        .animation(.snappy(duration: 0.2), value: session.phase)
    }

    private func card(for word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                if !word.source.isEmpty {
                    Image(systemName: "book.closed")
                    Text(word.source)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                BoxRing(box: word.box, size: 10)
                Text("Kutu \(word.box)/\(Leitner.maxBox)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(word.english)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                    Speaker.shared.speak(word.english)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Telaffuzu dinle")
            }

            if !word.example.isEmpty {
                Text(AttributedString(quoting: word.example, highlighting: word.english))
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .revealed(let verdict) = session.phase {
                answerReveal(for: word, verdict: verdict)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func answerReveal(for word: Word, verdict: StudySession.Verdict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.bottom, 2)
            verdictLabel(verdict)
            Text(word.turkish)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verdict == .incorrect {
                Text("Senin cevabın: “\(answer)”. Anlamca aynıysa Bildim'e bas.")
                    .font(.caption)
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
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
    }

    // MARK: - Alt çubuk

    private var askBar: some View {
        HStack(spacing: 8) {
            Button("Cevabı göster", systemImage: "eye") { reveal(withAnswer: false) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Cevabı göster (⌘↩)")
            TextField("Türkçesi", text: $answer)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($answerFocused)
                .onSubmit { reveal(withAnswer: true) }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
            Button("Kontrol et", systemImage: "checkmark") { reveal(withAnswer: true) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .help("Kontrol et (↩)")
        }
        .controlSize(.large)
        .onAppear { answerFocused = true }
    }

    @ViewBuilder
    private var gradeBar: some View {
        if case .revealed(let verdict) = session.phase {
            HStack(spacing: 10) {
                gradeButton("Bilemedim", systemImage: "xmark", key: .leftArrow, known: false, prominent: verdict != .correct)
                gradeButton("Bildim", systemImage: "checkmark", key: .rightArrow, known: true, prominent: verdict == .correct)
            }
        }
    }

    @ViewBuilder
    private func gradeButton(_ title: String, systemImage: String, key: KeyEquivalent, known: Bool, prominent: Bool) -> some View {
        let button = Button {
            session.grade(known: known)
            answer = ""
            answerFocused = true
        } label: {
            Label(title, systemImage: systemImage)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .keyboardShortcut(key, modifiers: [])
        .help(known ? "Bildim (→)" : "Bilemedim (←)")
        // Mac'te renk verilen cam düğme de dolu görünüyor; öne çıkmayanın yalnızca yazısı renkli.
        if prominent {
            button.buttonStyle(.glassProminent).tint(known ? .green : .red)
        } else {
            button.buttonStyle(.glass).foregroundStyle(known ? .green : .red)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        session.reveal(answer: withAnswer ? answer : nil)
    }

    // MARK: - Bitti

    private var finished: some View {
        ContentUnavailableView {
            Label(session.isPracticeAll ? "Tur Bitti" : "Bugünlük Bu Kadar", systemImage: "checkmark.circle")
        } description: {
            Text(finishedDescription)
        } actions: {
            VStack(spacing: 10) {
                Button {
                    session.start(with: words, practiceAll: true)
                } label: {
                    Text("Hepsini Çalış").frame(minWidth: 140)
                }
                .buttonStyle(.glassProminent)
                Button(action: onAddTapped) {
                    Text("Kelime Ekle").frame(minWidth: 140)
                }
                .buttonStyle(.glass)
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
        lines.append(DeckSummary.text(for: words))
        return lines.joined(separator: "\n")
    }
}
