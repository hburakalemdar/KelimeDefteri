import SwiftData
import SwiftUI

/// Menü çubuğu penceresindeki Günlük Tekrar; oyun merkezinden (`MacGamesView`) açılır.
/// Sorular iOS ile ortak (`DailyStepView`); klavyeyle oynanır: yazarak cevapta Return kontrol eder
/// (boşken gösterir) ve sonra devam eder; ← Bilemedim, → Bildim. Çoktan Seçmeli 1–4, Harfleri Diz klavyeden
/// yazılır. Esc oyunlara döner.
/// Tur bitince iPhone'daki tur özeti (`RoundSummaryView`) gösterilir; yeni tur yalnızca "Bir Tur Daha" ile başlar.
struct MacStudyView: View {
    /// Tur `MenuBarView`'de yaşar; sayfa değişince ya da oyunlara dönünce kaybolmaz.
    let session: StudySession
    var onAddTapped: () -> Void
    var onClose: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Environment(\.modelContext) private var context

    var body: some View {
        // Tur özetinde üst çubuk gizlenir (iPhone'daki oyunlar gibi); Esc yine oyunlara döner.
        GameScaffold(showsBar: session.current != nil || !session.hasRound, onClose: onClose) {
            if session.current != nil {
                GameProgressHeader(done: session.finishedWordCount, total: session.wordCount)
            }
        } content: {
            Group {
                if let word = session.current {
                    // Silinmiş kelime (ör. başka cihazdan) çizilmez; kimlik kümesi değişince tur onu atlar.
                    if word.isGone(from: words.aliveIDs) {
                        Color.clear
                    } else {
                        DailyStepView(session: session, words: words)
                    }
                } else if session.hasRound {
                    summary
                } else {
                    finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Pencere günlerce açık kalmış olabilir: dünkü yarım turun açık cevabı kaydedilir, bugünün turu
            // başlar. Biten turun özeti ise kullanıcı "Bir Tur Daha"ya basana kadar ekranda kalır.
            if session.current != nil && session.began(onAnotherDayThan: .now) {
                session.gradePendingAnswer()
                session.start(with: words, plan: .daily)
            }
            // Cevabı kaydedilmiş seçmeli/harf sorusu (pencere cevaptan hemen sonra kapandıysa) yeniden sorulmaz.
            session.skipAnsweredStep()
            session.resumeClock()
            syncRound()
        }
        .onDisappear { saveOpenAnswer() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveOpenAnswer()
        }
        // Sayı değil kimlik kümesi: aynı anda biri silinip biri eklenince de sıra güncellensin.
        .onChange(of: words.aliveIDs) { syncRound() }
    }

    /// Silinen kelimeler turdan çıkar. Tur hiç başlamadıysa dokunulmaz (boş oturumun planı `.weak`tır ve
    /// eşitleme onu kendiliğinden başlatırdı); turu oyun merkezi ya da "Bir Tur Daha" başlatır.
    private func syncRound() {
        if session.hasRound { session.sync(with: words) }
    }

    /// Pencere kapanınca ya da uygulamadan çıkılınca açık cevap kaydedilir; kart olduğu gibi kalır.
    private func saveOpenAnswer() {
        session.pauseClock()
        session.commitPendingAnswer()
        context.saveLogging()
    }

    // MARK: - Tur özeti

    /// iPhone'daki özetin aynısı; yeni tur kendiliğinden başlamaz. Düğme açacağı akışı adıyla söyler.
    private var summary: some View {
        let next = StudySession.againPlan(after: session.plan, words: words)
        return RoundSummaryView(
            entries: session.roundEntries.map(RoundSummaryView.Entry.init),
            duration: session.finishedAt.timeIntervalSince(session.startedAt),
            roundStartedAt: session.roundBeganAt,
            againTitle: StudySession.againTitle(after: session.plan, next: next),
            onAgain: { session.start(with: words, plan: next) },
            onDone: onClose
        )
    }

    // MARK: - Soracak kelime yok

    /// Tur hiç başlamadıysa (soracak kelime yoktu): gerçekten iş kalmadıysa "Hepsi Güçlü"; yeni kelimeler
    /// bugünün sınırı dolduğu için bekliyorsa ayrı metin.
    private var finished: some View {
        let waiting = StudySession.recentWaitingCount(words)
        let allStrong = waiting == 0 && DeckSummary.repeatingCount(words) == 0
        return ContentUnavailableView {
            Label(allStrong ? "Hepsi Güçlü" : "Bugünlük Bu Kadar", systemImage: "checkmark.circle")
        } description: {
            Text(finishedDescription(waiting: waiting))
        } actions: {
            VStack(spacing: 10) {
                Button {
                    session.start(with: words, plan: .extraPractice)
                } label: {
                    Text("Yine de Çalış").frame(minWidth: 140)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                Button(action: onAddTapped) {
                    Text("Kelime Ekle").frame(minWidth: 140)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }

    private func finishedDescription(waiting: Int) -> String {
        var lines: [String] = []
        if waiting > 0 {
            lines.append("Bugünkü yeni kelimeler tamam; \(RoundText.recentWaiting(waiting)). Oyunlar'daki Tanış ile hemen başlayabilirsin.")
        }
        if let next = words.filter({ !$0.isNew }).map(\.dueDate).filter({ $0 > .now }).min() {
            let when = Leitner.dueDescription(for: next)
            lines.append("Sıradaki tekrar: \(when.lowercased(with: Locale(identifier: "tr_TR"))).")
        }
        lines.append(DeckSummary.text(for: words))
        return lines.joined(separator: "\n")
    }
}
