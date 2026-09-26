import Foundation

/// Günlük yeni hakkı: Günlük Tekrar'a her gün, vadesi gelen tekrarların üstüne eklenecek tanışma sayısı
/// (yeni kelime ya da yeni anlam). Ayarlar'dan seçilir; günlük hedef gibi bütün cihazlarda tek sayıdır:
/// asıl değer iCloud anahtar-değer deposunda (`GoalSync`, `SyncedSetting.dailyNew`), yerel aynası
/// `DailyGoal.defaults` (iOS'ta App Group; widget ve bildirim buradan okur).
nonisolated enum DailyNewAllowance {
    static let options = [5, 10, 15, 20]
    static let defaultValue = 10
    static let key = "dailyNewAllowance"

    static func isValid(_ value: Int) -> Bool { options.contains(value) }

    /// Kayıtlı hak; hiç seçilmemiş ya da geçersizse varsayılan.
    static func value(in defaults: UserDefaults = DailyGoal.defaults) -> Int {
        validated(defaults.integer(forKey: key))
    }

    /// Geçersiz değer (bozuk, eski sürümden kalma ya da hiç seçilmemiş) yerine varsayılan.
    static func validated(_ value: Int) -> Int { isValid(value) ? value : defaultValue }
}
