import SwiftUI

/// Günlük hedef halkası: bugünkü cevaplar oranında dolar, dolunca ortasında onay işareti çıkar.
/// Renk sistemin vurgu rengi (Fitness'taki gibi tek halka).
struct GoalRing: View {
    let progress: DailyGoal.Progress
    var size: CGFloat = 56
    /// Ortada sayı yazsın mı (hafta şeridindeki küçük halkalarda yazmaz).
    var showsCount = true

    private var lineWidth: CGFloat { max(3, size / 7) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.answered > 0 ? max(progress.fraction, 0.02) : 0)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsCount {
                if progress.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(.tint)
                        .symbolEffect(.bounce, value: progress.isComplete)
                } else {
                    Text("\(progress.answered)")
                        .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .padding(size / 6)
                }
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(.snappy, value: progress.fraction)
        .accessibilityElement()
        .accessibilityLabel(progress.isComplete
            ? "Günlük hedef tamamlandı, \(progress.answered) cevap"
            : "Günlük hedef: \(progress.answered) / \(progress.target) cevap")
    }
}

/// "Öğrenildi" işareti: uzun süre akılda kalan kelimenin yanında küçük mühür (`Word.isLearned`).
struct LearnedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(.tint)
            .accessibilityLabel("Öğrenildi")
    }
}
