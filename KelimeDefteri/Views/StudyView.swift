import SwiftData
import SwiftUI

/// Çalış sekmesi: oyun merkezi. Üstte Günlük Tekrar kartı, altında oyunlar.
/// Her oyun tam ekran açılır; kapatınca buraya dönülür.
struct StudyView: View {
    var onAddTapped: () -> Void

    /// Oyun merkezinden açılan tur.
    enum Game: Identifiable {
        case daily, extraPractice, recent, mode(GameMode)

        var id: String {
            switch self {
            case .daily: "daily"
            case .extraPractice: "extra"
            case .recent: "recent"
            case .mode(let mode): mode.rawValue
            }
        }
    }

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Query private var logs: [ReviewLog]
    @AppStorage(DailyGoal.key, store: DailyGoal.defaults) private var goalTarget = DailyGoal.defaultTarget
    /// Son turdan önce hedef tamamlanmış mıydı; tur hedefi kapatınca hafif bir titreşim verilir.
    @State private var goalWasComplete = false
    @State private var celebration = 0
    @State private var showSettings = false
    @State private var activeGame: Game?
    /// Hafıza zamanla azaldığı için sayılar her dakika tazelenir.
    @State private var now = Date.now

    var body: some View {
        NavigationStack {
            content
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
                // Bu Hafta'daki zorlanılan kelimeler buradan açılır (Bu Hafta, eklentilerle ortak `Shared`'da).
                .navigationDestination(for: Word.self) { word in
                    WordDetailView(word: word)
                }
                .fullScreenCover(item: $activeGame, onDismiss: gameDismissed) { game in
                    gameView(game)
                }
                .sensoryFeedback(.success, trigger: celebration)
                .onAppear { goalWasComplete = goalProgress.isComplete }
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
                    goalCard
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Oyunlar")
                            .font(.title3.bold())
                            .padding(.horizontal, 4)
                        // Grid: bir satırdaki iki kart, açıklaması iki satıra inse de aynı boyda kalır.
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            ForEach(Array(stride(from: 0, to: GameMode.hubGames.count, by: 2)), id: \.self) { start in
                                GridRow {
                                    ForEach(GameMode.hubGames[start ..< min(start + 2, GameMode.hubGames.count)], id: \.self) { mode in
                                        GameCard(mode: mode, unavailableReason: mode.unavailableReason(for: deck)) {
                                            activeGame = .mode(mode)
                                        }
                                    }
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
        case .recent: RecallGameView(plan: .recent, mode: .dailyReview)
        case .mode(let mode):
            switch mode {
            case .multipleChoice: ChoiceGameView()
            case .match: MatchGameView()
            case .fillBlank: FillBlankGameView()
            case .letters: LettersGameView()
            case .reverse: RecallGameView(plan: .reverse, mode: .reverse)
            default: QuickMixGameView()
            }
        }
    }

    // MARK: - Özet

    private var averageMemory: Double? { MemoryStats.average(words.map { $0.memory(at: now) }) }
    private var dailyCount: (weak: Int, new: Int) { StudySession.dailyCount(words, now: now) }

    private var deck: GameDeck {
        GameDeck(entries: words.map { ($0.english, $0.example) })
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
            recentRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }

    /// Günlük Tekrar'ın bugün almadığı yeni kelimeler varsa onlarla ayrı tur; yoksa satır hiç görünmez.
    @ViewBuilder
    private var recentRow: some View {
        let waiting = StudySession.recentWaitingCount(words, now: now)
        if waiting > 0 {
            HStack(spacing: 12) {
                Text(RoundText.recentWaiting(waiting))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Tanış") { activeGame = .recent }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
                    .accessibilityHint("En son eklenen yeni kelimelerle kısa bir tur açar")
            }
        }
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

    // MARK: - Günlük hedef

    /// Yalnızca kelimesi olan cevaplar sayılır (haftalık özetle aynı kural).
    private var goalProgress: DailyGoal.Progress {
        DailyGoal.progress(dates: logs.filter { $0.word != nil }.map(\.date), target: goalTarget, now: now)
    }

    private func gameDismissed() {
        now = .now
        let complete = goalProgress.isComplete
        if complete && !goalWasComplete { celebration += 1 }
        goalWasComplete = complete
    }

    private var goalCard: some View {
        let progress = goalProgress
        return NavigationLink {
            WeeklySummaryView()
        } label: {
            HStack(spacing: 16) {
                GoalRing(progress: progress, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Günlük Hedef")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(DailyGoal.text(progress))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let streak = DailyGoal.streakText(progress.streak) {
                        Label(streak, systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .labelStyle(StreakLabelStyle())
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
            .contentShape(.rect(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Haftalık özeti açar")
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

/// Seri satırı: alev simgesi turuncu, yazı çevresinin renginde.
private struct StreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.orange)
            configuration.title
        }
    }
}

/// Oyun merkezindeki kart: renkli simge, ad ve kısa açıklama. Oynanamıyorsa soluk ve nedenini yazar.
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
                        // Büyük yazıda kesilmesin, iki satıra insin; yazı küçültülmez.
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(unavailableReason != nil)
        .opacity(unavailableReason == nil ? 1 : 0.5)
    }
}

#if DEBUG
#Preview {
    StudyView(onAddTapped: {})
        .modelContainer(PreviewData.container)
}
#endif
