import Foundation
import SwiftData

/// Günlük hedefin ve günlük yeni hakkının (`SyncedSetting`) iCloud anahtar-değer deposu
/// (`NSUbiquitousKeyValueStore`) ile tutulan tek kopyası.
///
/// Hedef bütün cihazlarda tek sayıdır; seri de hedefe göre hesaplandığı için böylece her yerde aynı çıkar.
/// iCloud'daki değer geçerlidir; yerel depo (`DailyGoal.defaults`) onun aynasıdır. Widget ve eklentiler
/// iCloud'a bakmaz, yalnızca aynayı okur. Geçersiz değerler (ayarın seçenekleri dışı) yok sayılır.
///
/// Mantık `GoalCloudStore` üstünden yazıldı; testler sahte depo kullanır.
nonisolated enum GoalSync {
    /// Açılışta ve uygulama öne gelince: iCloud'da geçerli bir değer varsa yerele al; yoksa yereldeki
    /// (kullanıcının seçtiği) değeri iCloud'a yükle. Yerel değer değiştiyse `true`.
    ///
    /// Yerelde hiç seçilmemiş değer yüklenmez: yeni cihazda iCloud değeri henüz inmemişken varsayılanı
    /// yüklemek, öbür cihazlarda seçilmiş değeri ezerdi. İnince dış değişiklik bildirimi gelir.
    @discardableResult
    static func reconcile(cloud: some GoalCloudStore, local: UserDefaults, setting: SyncedSetting = .dailyGoal) -> Bool {
        if let remote = cloudTarget(cloud, setting: setting) {
            return store(remote, in: local, setting: setting)
        }
        if let chosen = localTarget(local, setting: setting) {
            cloud.set(chosen, forKey: setting.key)
            cloud.synchronize()
        }
        return false
    }

    /// Başka bir cihaz değeri değiştirdi (ya da ilk eşitleme indi). `changedKeys` bildirimdeki
    /// `NSUbiquitousKeyValueStoreChangedKeysKey`; `nil` ise hepsi değişmiş sayılır. Yerel değiştiyse `true`.
    @discardableResult
    static func applyExternalChange(
        changedKeys: [String]?, cloud: some GoalCloudStore, local: UserDefaults, setting: SyncedSetting = .dailyGoal
    ) -> Bool {
        if let changedKeys, !changedKeys.contains(setting.key) { return false }
        guard let remote = cloudTarget(cloud, setting: setting) else { return false }
        return store(remote, in: local, setting: setting)
    }

    /// Kullanıcı bu cihazda değeri seçti: yerele ve iCloud'a yaz.
    static func setTarget(_ target: Int, cloud: some GoalCloudStore, local: UserDefaults, setting: SyncedSetting = .dailyGoal) {
        guard setting.isValid(target) else { return }
        store(target, in: local, setting: setting)
        guard cloudTarget(cloud, setting: setting) != target else { return }
        cloud.set(target, forKey: setting.key)
        cloud.synchronize()
    }

    static func cloudTarget(_ cloud: some GoalCloudStore, setting: SyncedSetting = .dailyGoal) -> Int? {
        guard let value = (cloud.object(forKey: setting.key) as? NSNumber)?.intValue,
              setting.isValid(value) else { return nil }
        return value
    }

    private static func localTarget(_ local: UserDefaults, setting: SyncedSetting) -> Int? {
        let value = local.integer(forKey: setting.key)
        return setting.isValid(value) ? value : nil
    }

    @discardableResult
    private static func store(_ target: Int, in local: UserDefaults, setting: SyncedSetting) -> Bool {
        guard local.object(forKey: setting.key) as? Int != target else { return false }
        local.set(target, forKey: setting.key)
        return true
    }
}

/// iCloud'da tek değer olarak tutulan ayar: anahtarı ve geçerli seçenekleri.
nonisolated struct SyncedSetting: Sendable, Equatable {
    let key: String
    let options: [Int]

    func isValid(_ value: Int) -> Bool { options.contains(value) }

    static let dailyGoal = SyncedSetting(key: DailyGoal.key, options: DailyGoal.options)
    static let dailyNew = SyncedSetting(key: DailyNewAllowance.key, options: DailyNewAllowance.options)
    static let all: [SyncedSetting] = [.dailyGoal, .dailyNew]
}

/// `NSUbiquitousKeyValueStore`'un GoalSync'in kullandığı kısmı.
nonisolated protocol GoalCloudStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: GoalCloudStore {}

/// Uygulamadaki canlı eşitleme: iCloud deposunu dinler, değişince aynayı günceller, widget'ları tazeler.
/// Yalnızca iOS ve Mac uygulaması başlatır (eklentilerde iCloud anahtar-değer yetkisi yok).
/// Hatırlatmalar hedefe bağlı değil; yeni hakkı değişince rozet ve hatırlatmalar yeniden kurulur.
enum GoalCloudSync {
    private static var observer: NSObjectProtocol?

    /// Açılışta bir kez: dinlemeye başla ve eşle.
    static func start() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                queue: .main
            ) { notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                MainActor.assumeIsolated { externalChange(keys: keys) }
            }
        }
        refresh()
    }

    /// Açılışta ve uygulama öne gelince.
    static func refresh() {
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        let changed = SyncedSetting.all.filter { GoalSync.reconcile(cloud: cloud, local: DailyGoal.defaults, setting: $0) }
        applied(changed)
    }

    /// Ayarlar'da seçilen değer (günlük hedef ya da yeni hakkı).
    static func userChose(_ target: Int, setting: SyncedSetting = .dailyGoal) {
        GoalSync.setTarget(target, cloud: NSUbiquitousKeyValueStore.default, local: DailyGoal.defaults, setting: setting)
    }

    private static func externalChange(keys: [String]?) {
        let changed = SyncedSetting.all.filter {
            GoalSync.applyExternalChange(changedKeys: keys, cloud: NSUbiquitousKeyValueStore.default, local: DailyGoal.defaults, setting: $0)
        }
        applied(changed)
    }

    /// Yerel ayna değişti: widget'lar tazelenir; yeni hakkı rozet ve bildirimdeki sayıyı da değiştirir.
    private static func applied(_ changed: [SyncedSetting]) {
        guard !changed.isEmpty else { return }
        Glance.reloadWidgets()
        if changed.contains(.dailyNew), let context = SharedStore.container?.mainContext {
            Task { await ReminderScheduler.refresh(context: context) }
        }
    }
}
