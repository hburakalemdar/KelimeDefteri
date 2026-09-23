import SwiftData
import SwiftUI

/// Çalış sekmesi: oyun merkezi. Üstte Günlük Tekrar kartı, altında oyunlar.
/// Her oyun tam ekran açılır; kapatınca buraya dönülür.
struct StudyView: View {
    var onAddTapped: () -> Void

    /// Oyun merkezinden açılan tur.
    enum Game: Identifiable {
        case daily, extraPractice, mode(GameMode)

        var id: String {
            switch self {
            case .daily: "daily"
            case .extraPractice: "extra"
            case .mode(let mode): mode.rawValue
            }
        }
    }

    @Query(sort: \Word.dueDate) private var words: [Word]
    @State private var showSettings = false
    @State private var activeGame: Game?
    /// Hafıza zamanla azaldığı için sayılar her dakika tazelenir.
    @State private var now = Date.now

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
                .fullScreenCover(item: $activeGame, onDismiss: { now = .now }) { game in
                    gameView(game)
                }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if words.isEmpty {
            emptyDeck
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    dailyCard
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Oyunlar")
                            .font(.title3.bold())
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(GameMode.hubGames, id: \.self) { mode in
                                GameCard(mode: mode, unavailableReason: mode.unavailableReason(for: deck)) {
                                    activeGame = .mode(mode)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func gameView(_ game: Game) -> some View {
        switch game {
        case .daily: RecallGameView(plan: .daily, mode: .dailyReview)
        case .extraPractice: RecallGameView(plan: .extraPractice, mode: .dailyReview)
        case .mode(let mode):
            switch mode {
            case .multipleChoice: ChoiceGameView()
            default: RecallGameView(plan: .quick, mode: .quickRound)
            }
        }
    }

    // MARK: - Özet

    private var averageMemory: Double? { MemoryStats.average(words.map { $0.memory(at: now) }) }
    private var dailyCount: (weak: Int, new: Int) { StudySession.dailyCount(words, now: now) }

    private var deck: GameDeck {
        GameDeck(entries: words.map { ($0.english, $0.example) })
    }

    private var subtitle: String {
        guard !words.isEmpty else { return "" }
        guard let averageMemory else { return "\(words.count) yeni kelime" }
        let weak = dailyCount.weak
        return "Hafıza \(MemoryStats.text(averageMemory)) · " + (weak > 0 ? "\(weak) kelime zayıfladı" : "hepsi güçlü")
    }

    // MARK: - Günlük Tekrar

    private var dailyCard: some View {
        let count = dailyCount
        let hasWork = count.weak + count.new > 0
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Günlük Tekrar")
                        .font(.title2.bold())
                    Text(Self.keepingPartsTogether(hasWork ? RoundText.daily(weak: count.weak, new: count.new) : allStrongText))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                MemoryRing(memory: averageMemory, size: 56, text: .center)
                    .accessibilityLabel(averageMemory.map { "Defterin ortalama hafızası \(MemoryStats.text($0))" } ?? "Yeni defter")
            }
            Button {
                activeGame = hasWork ? .daily : .extraPractice
            } label: {
                Text(hasWork ? "Başla" : "Yine de Çalış")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }

    /// "yaklaşık 3 dk" gibi parçalar satır sonunda bölünmesin; satır yalnızca " · " aralarında kırılır.
    private static func keepingPartsTogether(_ text: String) -> String {
        text.components(separatedBy: " · ")
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " · ")
    }

    private var allStrongText: String {
        var text = "Bütün kelimeler güçlü"
        if let next = words.map(\.dueDate).filter({ $0 > now }).min() {
            text += " · sıradaki tekrar " + Leitner.dueDescription(for: next, now: now).lowercased(with: Locale(identifier: "tr_TR"))
        }
        return text
    }

    // MARK: - Boş defter

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
}

/// Oyun merkezindeki kart: renkli simge, ad ve tek satır açıklama. Oynanamıyorsa soluk ve nedenini yazar.
struct GameCard: View {
    let mode: GameMode
    let unavailableReason: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsIcon(systemName: mode.systemImage, color: mode.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(unavailableReason ?? mode.cardDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(unavailableReason != nil)
        .opacity(unavailableReason == nil ? 1 : 0.5)
    }
}

extension GameMode {
    var color: Color {
        switch self {
        case .dailyReview: .blue
        case .quickRound: .orange
        case .multipleChoice: .blue
        case .match: .green
        case .fillBlank: .purple
        case .letters: .pink
        case .reverse: .cyan
        }
    }
}

#if DEBUG
#Preview {
    StudyView(onAddTapped: {})
        .modelContainer(PreviewData.container)
}
#endif
