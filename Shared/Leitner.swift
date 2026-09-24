import Foundation

/// Eski Leitner kutu sisteminden kalanlar: kutu aralıkları (yalnızca hafıza değerlerine
/// tek seferlik geçişte okunur) ve sıradaki tekrarın gün bazlı anlatımı.
nonisolated enum Leitner {
    /// Kutu başına bekleme süresi (gün). İndeks = eski kutu numarası.
    static let intervalsInDays = [0, 1, 3, 7, 16, 35]

    /// Sıradaki tekrarın kısa, gün bazlı anlatımı (gün 04:00'te döner): "3 gün gecikti", "Bugün",
    /// "Yarın", "3 gün sonra".
    static func dueDescription(for due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        // Hiç çalışılmamış kelimenin vadesi `.distantPast`.
        guard due > .distantPast else { return "Yeni" }
        let days = DayBoundary.days(from: now, to: due, calendar: calendar)
        return switch days {
        case ..<0: "\(-days) gün gecikti"
        case 0: "Bugün"
        case 1: "Yarın"
        default: "\(days) gün sonra"
        }
    }
}
