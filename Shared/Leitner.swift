import Foundation

/// Eski Leitner kutu sisteminden kalanlar: kutu aralıkları (yalnızca hafıza değerlerine
/// tek seferlik geçişte okunur) ve sıradaki tekrarın gün bazlı anlatımı.
nonisolated enum Leitner {
    /// Kutu başına bekleme süresi (gün). İndeks = eski kutu numarası.
    static let intervalsInDays = [0, 1, 3, 7, 16, 35]

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
}
