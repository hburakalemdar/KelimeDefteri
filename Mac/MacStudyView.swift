import SwiftData
import SwiftUI

/// Menü çubuğu penceresindeki çalışma kartı. Klavyeyle kullanılabilir:
/// Return kontrol eder, ← Bilemedim, → Bildim.
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
                    Label("Defterin boş", systemImage: "book.closed")
                } description: {
                    Text("Okurken takıldığın ilk kelimeyi ekle, burada sana sorayım.")
                } actions: {
                    Button("Kelime ekle", action: onAddTapped)
                }
            } else if let word = session.current {
                card(for: word)
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

    // MARK: - Kart

    private func card(for word: Word) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(word.source)
                    .lineLimit(1)
                Spacer()
                Text("kutu \(word.box)/\(Leitner.maxBox) · \(session.remaining) kaldı")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            // Kart: kelime ortada, altında cümle; cevap açılınca Türkçesi.
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.english)
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Button {
                        Speaker.shared.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .help("Telaffuzu dinle")
                }

                if !word.example.isEmpty {
                    Text(AttributedString(quoting: word.example, highlighting: word.english))
                        .font(.system(.body, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if session.phase != .asking {
                    answerReveal(for: word)
                        .padding(.top, 6)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 12)

            if session.phase == .asking {
                askArea
            } else {
                gradeArea
            }
        }
        .padding(16)
        .animation(.snappy(duration: 0.2), value: session.phase)
    }

    private var askArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Hatırladığın Türkçesi", text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .autocorrectionDisabled()
                    .focused($answerFocused)
                    .onSubmit { reveal(withAnswer: true) }
                Button("Kontrol et") { reveal(withAnswer: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Button("Bilmiyorum, göster") { reveal(withAnswer: false) }
                .buttonStyle(.link)
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .onAppear { answerFocused = true }
    }

    private func answerReveal(for word: Word) -> some View {
        VStack(spacing: 6) {
            Text(word.turkish)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("HighlightText"))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color("Highlight"), in: .rect(cornerRadius: 4))
                .textSelection(.enabled)
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !answer.isEmpty {
                Text("Senin cevabın: \(answer)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var gradeArea: some View {
        if case .revealed(let verdict) = session.phase {
            VStack(spacing: 10) {
                verdictLine(verdict)
                HStack(spacing: 10) {
                    gradeButton("Bilemedim", key: .leftArrow, known: false, prominent: verdict != .correct)
                    gradeButton("Bildim", key: .rightArrow, known: true, prominent: verdict == .correct)
                }
            }
        }
    }

    private func verdictLine(_ verdict: StudySession.Verdict) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru!", "checkmark.circle.fill", .green)
        case .incorrect: ("Tam tutmadı. Anlamca aynıysa “Bildim”i seç.", "xmark.circle.fill", .red)
        case .peeked: ("Türkçesine baktın. Biliyor muydun?", "eye.fill", .secondary)
        }
        return Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func gradeButton(_ title: String, key: KeyEquivalent, known: Bool, prominent: Bool) -> some View {
        let button = Button {
            session.grade(known: known)
            answer = ""
            answerFocused = true
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .tint(known ? .green : .red)
        .keyboardShortcut(key, modifiers: [])
        .help(known ? "→" : "←")
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        session.reveal(answer: withAnswer ? answer : nil)
    }

    // MARK: - Bitti

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
                    .padding(.top, 4)
            }
        } actions: {
            Button("Yine de hepsini çalış") {
                session.start(with: words, practiceAll: true)
            }
            .buttonStyle(.borderedProminent)
            Button("Kelime ekle", action: onAddTapped)
        }
    }
}
