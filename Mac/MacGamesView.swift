import SwiftData
import SwiftUI

/// Menü penceresinde açık olan sayfa: oyun merkezi (`nil`), Günlük Tekrar, bir oyun ya da Bu Hafta.
enum MacGamePage: Hashable {
    case daily
    /// Yeni Eklenenler: Günlük Tekrar'ın bugün almadığı yeni kelimelerle ayrı tur.
    case recent
    case game(GameMode)
    case weekly
}

/// Menü çubuğu penceresinin Çalış sayfası: iOS'taki oyun merkezinin kompakt Mac karşılığı.
/// Üstte Günlük Tekrar (↩), altında günlük hedef halkası ve seri (tıklayınca Bu Hafta), en altta oyunlar (1–6).
/// Oyunlar pencerenin içinde açılır; Esc oyun merkezine döner.
struct MacGamesView: View {
    /// Günlük Tekrar turu `MenuBarView`'de yaşar; oyunlar arasında gidip gelince kaybolmaz.
    let session: StudySession
    @Binding var page: MacGamePage?
    var onAddTapped: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Query private var logs: [ReviewLog]
    @Environment(\.modelContext) private var context
    @AppStorage(DailyGoal.key, store: DailyGoal.defaults) private var goalTarget = DailyGoal.defaultTarget
    /// Hafıza zamanla azaldığı için sayılar her dakika tazelenir.
    @State private var now = Date.now

    var body: some View {
        Group {
            switch page {
            case nil:
                hub
            case .daily:
                MacStudyView(session: session, onAddTapped: onAddTapped, onClose: backToHub)
            case .recent:
                RecallGameView(plan: .recent, mode: .dailyReview, onClose: backToHub, onDailyHandoff: openDaily)
            case .weekly:
                WeeklySummaryView(onClose: backToHub)
            case .game(let mode):
                gameView(mode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Uygulama açıkken iCloud'dan eski biçimli kelime gelmiş olabilir.
            MemoryMigration.migrateIfNeeded(context: context)
            // Hafıza alanları cevap kayıtlarından yeniden hesaplanır (başka cihazdan gelen cevaplar, geçen zaman).
            MemoryCache.refreshAll(in: context)
            // İki cihazda eşitlenmeden eklenen aynı kelimeyi birleştir, sahipsiz cevap kayıtlarını temizle.
            StoreMaintenance.run(in: context)
            now = .now
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func backToHub() {
        now = .now
        page = nil
    }

    /// Günlük Tekrar sayfasını açar. Yarım bir tur (bugün başlamış) varsa onunla sürer; yoksa — ilk açılış,
    /// biten turun özetinden dönülmüş ya da tur dün başlamış — verilen tur doğrudan başlar. Tanış'tan
    /// geçilen Günlük Tekrar da buraya gelir: tur her zaman bu kalıcı oturumda, ikinci bir tur açılmaz.
    private func openDaily(_ plan: StudySession.Plan) {
        if session.current == nil || session.began(onAnotherDayThan: .now) {
            session.gradePendingAnswer()
            session.start(with: words, plan: plan)
        }
        page = .daily
    }

    @ViewBuilder
    private func gameView(_ mode: GameMode) -> some View {
        switch mode {
        case .multipleChoice: ChoiceGameView(onClose: backToHub)
        case .match: MatchGameView(onClose: backToHub)
        case .fillBlank: FillBlankGameView(onClose: backToHub)
        case .letters: LettersGameView(onClose: backToHub)
        case .reverse: RecallGameView(plan: .reverse, mode: .reverse, onClose: backToHub)
        default: QuickMixGameView(onClose: backToHub)
        }
    }

    // MARK: - Oyun merkezi

    @ViewBuilder
    private var hub: some View {
        if words.isEmpty {
            ContentUnavailableView {
                Label("Defterin Boş", systemImage: "book.closed")
            } description: {
                Text("Okurken takıldığın ilk kelimeyi ekle, burada sana sorayım.")
            } actions: {
                Button("Kelime Ekle", action: onAddTapped)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    dailyCard
                    goalRow
                    Text("Oyunlar")
                        .font(.headline)
                        .padding(.top, 6)
                        .padding(.horizontal, 2)
                    gameGrid
                }
                .padding(14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Günlük Tekrar

    private var dailyCount: (weak: Int, new: Int) { StudySession.dailyCount(words, now: now) }

    /// Tur yarıda bırakıldıysa (bugün başlamışsa) "Devam Et".
    private var dailyInProgress: Bool {
        session.current != nil && !session.began(onAnotherDayThan: now)
    }

    private var dailyCard: some View {
        let count = dailyCount
        let hasWork = count.weak + count.new > 0
        let average = MemoryStats.average(words.map { $0.memory(at: now) })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Günlük Tekrar")
                        .font(.title3.bold())
                    Text(hasWork ? RoundText.daily(
                        weak: count.weak, new: count.new, pending: StudySession.pendingProductionCount(words, now: now),
                        seconds: StudySession.dailySeconds(words, now: now, count: count)
                    ) : allStrongText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                MemoryRing(memory: average, size: 44, text: .center)
                    .help("Defterin ortalama hafızası")
            }
            Button {
                // Zayıf kelime yoksa en zayıflarla ek tur (eski Mac kartındaki "Yine de Çalış").
                openDaily(hasWork ? .daily : .extraPractice)
            } label: {
                Text(dailyInProgress ? "Devam Et" : hasWork ? "Başla" : "Yine de Çalış")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .help("Günlük Tekrar (↩)")
            recentRow
        }
        .gameCard()
    }

    /// Günlük Tekrar'ın bugün almadığı yeni kelimeler varsa onlarla ayrı tur; yoksa satır hiç görünmez.
    @ViewBuilder
    private var recentRow: some View {
        let waiting = StudySession.recentWaitingCount(words, now: now)
        if waiting > 0 {
            HStack(spacing: 8) {
                Text(RoundText.recentWaiting(waiting))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Tanış") { page = .recent }
                    .buttonStyle(.glass)
                    .help("En son eklenen yeni kelimelerle kısa bir tur")
            }
        }
    }

    private var allStrongText: String { DeckSummary.allDoneText(for: words, now: now) }

    // MARK: Günlük hedef

    /// Yalnızca kelimesi olan cevaplar sayılır (haftalık özetle aynı kural).
    private var goalProgress: DailyGoal.Progress {
        DailyGoal.progress(dates: logs.filter { $0.word != nil }.map(\.date), target: goalTarget, now: now)
    }

    private var goalRow: some View {
        let progress = goalProgress
        return Button {
            page = .weekly
        } label: {
            HStack(spacing: 12) {
                GoalRing(progress: progress, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Günlük Hedef")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(DailyGoal.text(progress))
                            .monospacedDigit()
                        if let streak = DailyGoal.streakText(progress.streak) {
                            Label {
                                Text(streak)
                            } icon: {
                                Image(systemName: "flame.fill").foregroundStyle(.orange)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GameStyle.cardFill, in: .rect(cornerRadius: GameStyle.cardRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: GameStyle.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Bu haftanın özeti")
    }

    // MARK: Oyunlar

    private var gameGrid: some View {
        let deck = GameDeck(entries: words.map { ($0.english, $0.example, $0.turkish) })
        let games = Array(GameMode.hubGames.enumerated())
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: games.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(games[start ..< min(start + 2, games.count)], id: \.element) { index, mode in
                        MacGameTile(mode: mode, number: index + 1, unavailableReason: mode.unavailableReason(for: deck)) {
                            page = .game(mode)
                        }
                    }
                }
            }
        }
    }
}

/// Oyun merkezindeki küçük kart: renkli simge, ad ve kısa açıklama; köşede kısayol tuşu.
/// Oynanamıyorsa soluk ve nedenini yazar.
private struct MacGameTile: View {
    let mode: GameMode
    let number: Int
    let unavailableReason: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIcon(systemName: mode.systemImage, color: mode.color, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(unavailableReason ?? mode.cardDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("\(number)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GameStyle.cardFill, in: .rect(cornerRadius: GameStyle.tileRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: GameStyle.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [])
        .help("\(mode.title) (\(number))")
        .disabled(unavailableReason != nil)
        .opacity(unavailableReason == nil ? 1 : 0.5)
    }
}
