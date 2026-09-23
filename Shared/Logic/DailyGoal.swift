import Foundation

/// Günlük hedef halkası ve seri. Ayrı sayaç tutulmaz; hepsi cevap kayıtlarının (`ReviewLog.date`)
/// tarihlerinden, yerel takvim gününe göre hesaplanır. iCloud iki cihazın kayıtlarını birleştirdiği
/// için iPhone ve Mac'te verilen cevaplar birlikte sayılır.
///
/// Hedef sonradan değişirse geçmiş günler de yeni hedefe göre değerlendirilir (o günkü hedef saklanmaz):
/// hedefi düşürmek seriyi uzatabilir, yükseltmek kısaltabilir. Basit ve her cihazda aynı sonucu verir.
nonisolated enum DailyGoal {
    /// Ayarlar'daki seçenekler (cevap sayısı).
    static let options = [10, 20, 30, 50, 100]
    static let defaultTarget = 30
    static let key = "dailyGoal"

    /// Hedefin saklandığı yer. iOS'ta App Group, böylece widget da aynı hedefi okur. Mac'te widget yok ve
    /// App Group ayarları sistem izin uyarısı çıkarabilir; hedef uygulamanın kendi ayarlarında durur
    /// (Mac Ayarlar penceresinden seçilir).
    static var defaults: UserDefaults {
        #if os(macOS)
        .standard
        #else
        UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard
        #endif
    }

    /// Kayıtlı hedef; hiç seçilmemiş ya da geçersizse varsayılan.
    static func target(in defaults: UserDefaults = defaults) -> Int {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : defaultTarget
    }

    /// Halkanın o anki durumu.
    struct Progress: Equatable, Sendable {
        /// Bugün verilen cevap sayısı.
        let answered: Int
        let target: Int
        /// Kaç gündür üst üste halka kapandı. Bugün henüz kapanmadıysa dünden geriye sayılır.
        let streak: Int

        /// Halkanın doluluğu, 0…1.
        var fraction: Double { target > 0 ? min(Double(answered) / Double(target), 1) : 0 }
        var isComplete: Bool { answered >= target }
        var remaining: Int { max(target - answered, 0) }
    }

    static func progress(dates: some Sequence<Date>, target: Int, now: Date = .now, calendar: Calendar = .current) -> Progress {
        let counts = dayCounts(dates, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return Progress(
            answered: counts[today] ?? 0,
            target: target,
            streak: streak(counts: counts, target: target, now: now, calendar: calendar)
        )
    }

    /// Gün başlangıcına göre cevap sayıları.
    static func dayCounts(_ dates: some Sequence<Date>, calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for date in dates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        return counts
    }

    static func streak(dates: some Sequence<Date>, target: Int, now: Date = .now, calendar: Calendar = .current) -> Int {
        streak(counts: dayCounts(dates, calendar: calendar), target: target, now: now, calendar: calendar)
    }

    private static func streak(counts: [Date: Int], target: Int, now: Date, calendar: Calendar) -> Int {
        guard target > 0 else { return 0 }
        var day = calendar.startOfDay(for: now)
        // Bugün henüz kapanmadı: seri kopmuş sayılmaz, dünden geriye sayılır.
        if (counts[day] ?? 0) < target {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while (counts[day] ?? 0) >= target {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// "18 / 30 cevap" · "Hedef tamamlandı"
    static func text(_ progress: Progress) -> String {
        progress.isComplete ? "Hedef tamamlandı · \(progress.answered) cevap" : "\(progress.answered) / \(progress.target) cevap"
    }

    /// "5 günlük seri"; seri yoksa `nil`.
    static func streakText(_ streak: Int) -> String? {
        streak > 0 ? "\(streak) günlük seri" : nil
    }

    /// Kilit ekranı için kısa satır: "12/30 · 4 gün seri"; seri yoksa yalnızca "12/30".
    static func shortText(_ progress: Progress) -> String {
        let count = "\(progress.answered)/\(progress.target)"
        return progress.streak > 0 ? "\(count) · \(progress.streak) gün seri" : count
    }

    /// Widget zaman çizelgesinin anları: `now`'dan başlayıp `step` arayla `count` an, araya düşen
    /// gece yarıları da eklenir (halka yeni günde sıfırdan başlasın).
    static func timelineDates(from now: Date, step: TimeInterval, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        var dates = (0..<count).map { now.addingTimeInterval(Double($0) * step) }
        let end = dates[dates.count - 1]
        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= end {
            dates.append(next)
            day = next
        }
        return Array(Set(dates)).sorted()
    }
}
