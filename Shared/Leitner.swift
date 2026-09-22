import Foundation

/// Aralıklı tekrar için Leitner kutu sistemi.
///
/// Bilinen kelime bir üst kutuya çıkar ve kutunun aralığı kadar gün sonra
/// tekrar sorulur; bilinmeyen kelime 0. kutuya döner ve hemen tekrar sorulur.
nonisolated enum Leitner {
    /// Kutu başına bekleme süresi (gün). İndeks = kutu numarası.
    static let intervalsInDays = [0, 1, 3, 7, 16, 35]
    static var maxBox: Int { intervalsInDays.count - 1 }

    static func review(
        box: Int,
        known: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> (box: Int, due: Date) {
        let newBox = known ? min(max(box, 0) + 1, maxBox) : 0
        let days = intervalsInDays[newBox]
        guard days > 0,
              let later = calendar.date(byAdding: .day, value: days, to: now)
        else { return (newBox, now) }
        // Günün başına yuvarla: "yarın" demek yarın sabah demek, bu saatte değil.
        return (newBox, calendar.startOfDay(for: later))
    }
}
