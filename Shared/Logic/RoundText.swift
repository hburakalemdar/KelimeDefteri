import Foundation

/// Oyun merkezi ve tur özetindeki kısa metinler.
nonisolated enum RoundText {
    /// Kelime başına ortalama süre (saniye); tahmini tur süresi için.
    static let secondsPerWord = 25.0

    /// "yaklaşık 3 dk" — kelime başına ortalama süreyle.
    static func estimate(wordCount: Int) -> String {
        estimate(seconds: Double(wordCount) * secondsPerWord)
    }

    /// "yaklaşık 3 dk" — yukarı yuvarlanır, en az 1 dk.
    static func estimate(seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return "yaklaşık \(minutes) dk"
    }

    /// "42 sn", "1 dk 5 sn", "3 dk".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (minutes, rest) = (total / 60, total % 60)
        if minutes == 0 { return "\(rest) sn" }
        return rest == 0 ? "\(minutes) dk" : "\(minutes) dk \(rest) sn"
    }

    /// "4/5 doğru · 42 sn"
    static func summary(correct: Int, total: Int, seconds: TimeInterval) -> String {
        "\(correct)/\(total) doğru · \(duration(seconds))"
    }

    /// Günlük Tekrar kartının alt satırı: "5 kelime zayıfladı · 2 yeni · yaklaşık 3 dk". `seconds`: turun
    /// soru türlerine göre tahmini süresi (`StudySession.dailySeconds`); verilmezse kelime başına ortalama.
    /// `pending`: `weak`in içinden, yarıda bırakılan ısınmadan üretimi kalan kelimeler ("1 kelime tekrar bekliyor");
    /// bunlar zayıflamış sayılmaz.
    static func daily(weak: Int, new: Int, pending: Int = 0, seconds: Double? = nil) -> String {
        var parts: [String] = []
        let pending = min(pending, weak)
        let weakened = weak - pending
        if weakened > 0 { parts.append("\(weakened) kelime zayıfladı") }
        if pending > 0 { parts.append("\(pending) kelime tekrar bekliyor") }
        if new > 0 { parts.append(weak > 0 ? "\(new) yeni" : "\(new) yeni kelime") }
        parts.append(estimate(seconds: seconds ?? Double(weak + new) * secondsPerWord))
        return parts.joined(separator: " · ")
    }

    /// Günlük Tekrar kartındaki Yeni Eklenenler satırı: "12 yeni kelime sırada".
    static func recentWaiting(_ count: Int) -> String {
        "\(count) yeni kelime sırada"
    }
}
