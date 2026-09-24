import Foundation

/// Günlük hedefin iCloud anahtar-değer deposu (`NSUbiquitousKeyValueStore`) ile tutulan tek kopyası.
///
/// Hedef bütün cihazlarda tek sayıdır; seri de hedefe göre hesaplandığı için böylece her yerde aynı çıkar.
/// iCloud'daki değer geçerlidir; yerel depo (`DailyGoal.defaults`) onun aynasıdır. Widget ve eklentiler
/// iCloud'a bakmaz, yalnızca aynayı okur. Geçersiz değerler (`DailyGoal.options` dışı) yok sayılır.
///
/// Mantık `GoalCloudStore` üstünden yazıldı; testler sahte depo kullanır.
nonisolated enum GoalSync {
    /// Açılışta ve uygulama öne gelince: iCloud'da geçerli bir hedef varsa yerele al; yoksa yereldeki
    /// (kullanıcının seçtiği) hedefi iCloud'a yükle. Yerel değer değiştiyse `true`.
    ///
    /// Yerelde hiç seçilmemiş hedef yüklenmez: yeni cihazda iCloud değeri henüz inmemişken varsayılanı
    /// yüklemek, öbür cihazlarda seçilmiş hedefi ezerdi. İnince dış değişiklik bildirimi gelir.
    @discardableResult
    static func reconcile(cloud: some GoalCloudStore, local: UserDefaults) -> Bool {
        if let remote = cloudTarget(cloud) {
            return store(remote, in: local)
        }
        if let chosen = localTarget(local) {
            cloud.set(chosen, forKey: DailyGoal.key)
            cloud.synchronize()
        }
        return false
    }

    /// Başka bir cihaz hedefi değiştirdi (ya da ilk eşitleme indi). `changedKeys` bildirimdeki
    /// `NSUbiquitousKeyValueStoreChangedKeysKey`; `nil` ise hepsi değişmiş sayılır. Yerel değiştiyse `true`.
    @discardableResult
    static func applyExternalChange(changedKeys: [String]?, cloud: some GoalCloudStore, local: UserDefaults) -> Bool {
        if let changedKeys, !changedKeys.contains(DailyGoal.key) { return false }
        guard let remote = cloudTarget(cloud) else { return false }
        return store(remote, in: local)
    }

    /// Kullanıcı bu cihazda hedefi seçti: yerele ve iCloud'a yaz.
    static func setTarget(_ target: Int, cloud: some GoalCloudStore, local: UserDefaults) {
        guard DailyGoal.isValid(target) else { return }
        store(target, in: local)
        guard cloudTarget(cloud) != target else { return }
        cloud.set(target, forKey: DailyGoal.key)
        cloud.synchronize()
    }

    static func cloudTarget(_ cloud: some GoalCloudStore) -> Int? {
        guard let value = (cloud.object(forKey: DailyGoal.key) as? NSNumber)?.intValue,
              DailyGoal.isValid(value) else { return nil }
        return value
    }

    private static func localTarget(_ local: UserDefaults) -> Int? {
        let value = local.integer(forKey: DailyGoal.key)
        return DailyGoal.isValid(value) ? value : nil
    }

    @discardableResult
    private static func store(_ target: Int, in local: UserDefaults) -> Bool {
        guard local.object(forKey: DailyGoal.key) as? Int != target else { return false }
        local.set(target, forKey: DailyGoal.key)
        return true
    }
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
/// Hatırlatmalar hedefe bağlı değil; yeniden planlamak gerekmez.
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
        if GoalSync.reconcile(cloud: cloud, local: DailyGoal.defaults) { Glance.reloadWidgets() }
    }

    /// Ayarlar'da seçilen hedef.
    static func userChose(_ target: Int) {
        GoalSync.setTarget(target, cloud: NSUbiquitousKeyValueStore.default, local: DailyGoal.defaults)
    }

    private static func externalChange(keys: [String]?) {
        if GoalSync.applyExternalChange(changedKeys: keys, cloud: NSUbiquitousKeyValueStore.default, local: DailyGoal.defaults) {
            Glance.reloadWidgets()
        }
    }
}
