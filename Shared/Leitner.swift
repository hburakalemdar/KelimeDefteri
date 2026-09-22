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

extension Leitner {
    /// Sıradaki tekrarın kısa, gün bazlı anlatımı: "Şimdi", "Yarın", "3 gün sonra".
    static func dueDescription(for due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        guard due > now else { return "Şimdi" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)
        ).day ?? 0
        return switch days {
        case ...0: "Bugün"
        case 1: "Yarın"
        default: "\(days) gün sonra"
        }
    }

    /// Kutunun anlamı: 0 yeni, en üst kutu öğrenildi, aradakiler tekrar aralığı.
    static func boxDescription(_ box: Int) -> String {
        switch box {
        case ...0: "Yeni"
        case maxBox...: "Öğrenildi"
        default: "\(intervalsInDays[box]) günde bir"
        }
    }
}
