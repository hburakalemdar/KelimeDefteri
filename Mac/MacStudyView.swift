import SwiftData
import SwiftUI

/// Menü çubuğu penceresindeki Günlük Tekrar; oyun merkezinden (`MacGamesView`) açılır.
/// Kart ve cevap çubuğu iOS ile ortak (`RecallQuestionView`); klavyeyle oynanır: Return kontrol eder
/// (boşken gösterir) ve sonra devam eder; ← Bilemedim, → Bildim, Esc oyunlara döner.
struct MacStudyView: View {
    /// Tur `MenuBarView`'de yaşar; sayfa değişince ya da oyunlara dönünce kaybolmaz.
    let session: StudySession
    var onAddTapped: () -> Void
    var onClose: () -> Void

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if let word = session.current {
                    // Silinmiş kelime (ör. başka cihazdan) çizilmez; kimlik kümesi değişince tur onu atlar.
                    if word.isGone(from: words.aliveIDs) {
                        Color.clear
                    } else {
                        RecallQuestionView(session: session, words: words)
                    }
                } else {
                    finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Pencere günlerce açık kalmış olabilir: dünkü turun açık cevabı kaydedilir, bugünün turu başlar.
            // Yoksa aynı turda bugün verilen cevaplar hafızayı değiştirmezdi.
            if session.began(onAnotherDayThan: .now) {
                session.gradePendingAnswer()
                session.start(with: words, plan: .daily)
            }
            session.resumeClock()
            // Pencere her açıldığında gün dönmüş olabilir; zamanı gelenleri sıraya al.
            refresh()
        }
        .onDisappear { saveOpenAnswer() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveOpenAnswer()
        }
        // Sayı değil kimlik kümesi: aynı anda biri silinip biri eklenince de sıra güncellensin.
        .onChange(of: words.aliveIDs) { refresh() }
        .onChange(of: session.current == nil) { _, ended in
            // iOS'taki Günlük Tekrar gibi tur en fazla 20 kelime (5'i yeni). Tur bitince yeni tur yalnızca
            // çalışılmış zayıf kelime kaldıysa kendiliğinden başlar; yalnızca yeni kelime kaldıysa "Hepsi Güçlü"
            // görünür. Bu turda sorulup zayıf kalan kelime (hemen arkasından doğru bilinen) sayılmaz, yoksa
            // az önce gördüğü kart hemen yeniden gelirdi.
            if ended && session.plan == .daily { continueDailyIfWeakRemain() }
        }
    }

    /// Üstte oyunlara dönüş (Esc) ve tur ilerlemesi.
    private var header: some View {
        HStack(spacing: 10) {
            MacBackButton(action: onClose)
            Spacer(minLength: 8)
            if session.current != nil {
                ProgressView(value: progress)
                    .frame(width: 120)
                    .accessibilityLabel("Tur ilerlemesi")
                Text("\(session.remaining + 1) kaldı")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    /// Pencere kapanınca ya da uygulamadan çıkılınca açık cevap kaydedilir; kart olduğu gibi kalır.
    private func saveOpenAnswer() {
        session.pauseClock()
        session.commitPendingAnswer()
        context.saveLogging()
    }

    private func refresh() {
        if session.current == nil && !session.isPracticeAll {
            startDailyIfNeeded()
        } else {
            session.sync(with: words)
        }
    }

    private func continueDailyIfWeakRemain() {
        let asked = session.roundEntries.map(\.word)
        let remaining = words.filter { word in !asked.contains { $0 === word } }
        guard StudySession.dailyCount(remaining).weak > 0 else { return }
        session.start(with: words, plan: .daily)
    }

    private func startDailyIfNeeded() {
        let count = StudySession.dailyCount(words)
        guard count.weak + count.new > 0 else { return }
        session.start(with: words, plan: .daily)
    }

    /// Turda cevaplanan kartların oranı; bilinmeyen kelime sıraya yeniden girdiği için
    /// toplam da onunla büyür.
    private var progress: Double {
        let total = session.reviewedCount + session.remaining + 1
        return Double(session.reviewedCount) / Double(total)
    }

    // MARK: - Bitti

    private var finished: some View {
        ContentUnavailableView {
            Label(session.isPracticeAll ? "Tur Bitti" : "Hepsi Güçlü", systemImage: "checkmark.circle")
        } description: {
            Text(finishedDescription)
        } actions: {
            VStack(spacing: 10) {
                Button {
                    session.start(with: words, practiceAll: true)
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
