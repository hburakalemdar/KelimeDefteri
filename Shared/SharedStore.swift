import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Uygulama ile paylaşım eklentisinin (Kelime Ekle) ortak kullandığı veri deposu.
///
/// Veritabanı App Group klasöründe durur; böylece kitaptan paylaşılan kelime,
/// uygulama açılınca listede görünür. iCloud eşitlemesini yalnızca ana uygulama yapar:
/// eklenti kısa ömürlü olduğundan sadece yerel depoya yazar, uygulama o değişikliği
/// kalıcı geçmişten görüp iCloud'a gönderir.
enum SharedStore {
    nonisolated static let appGroupID = "group.com.burakalemdar.KelimeDefteri"
    static let cloudKitContainerID = "iCloud.com.burakalemdar.KelimeDefteri"

    static var isExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }
    private static let storeName = "default.store"

    /// Depodaki bütün modeller; uygulama, eklenti, örnek veri ve testler aynı şemayı kullanır.
    nonisolated static let schema = Schema([Word.self, ReviewLog.self, WordSentence.self])

    static let logger = Logger(subsystem: "com.burakalemdar.KelimeDefteri", category: "store")

    /// Ortak depo ya da açılamadıysa hatası. Açılamazsa uygulama çökmez; "Veritabanı açılamadı"
    /// ekranı (`StoreGate`) gösterilir, eklenti isteği hatayla kapatır.
    static let result: Result<ModelContainer, Error> = {
        do {
            let container: ModelContainer
            if let storeURL = sharedStoreURL() {
                migrateLegacyStore(to: storeURL)
                let configuration = ModelConfiguration(
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: isExtension ? .none : .private(cloudKitContainerID)
                )
                container = try openSerialized(at: storeURL) {
                    try ModelContainer(for: schema, configurations: configuration)
                }
            } else {
                // App Group yetkisi yoksa (olmamalı) uygulamanın kendi klasörüne düş.
                container = try ModelContainer(for: schema)
            }
            // Eklenti yalnızca yeni kelime ekler; eski kayıtların geçişini uygulamalar yapar.
            // Widget de bir eklenti paketidir; iCloud'dan gelen değişiklikleri yalnızca uygulamalar dinler.
            if !isExtension {
                MemoryMigration.migrateIfNeeded(context: container.mainContext)
                MemoryCache.observeRemoteChanges(context: container.mainContext)
            }
            return .success(container)
        } catch {
            logger.error("Kelime veritabanı açılamadı: \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }()

    /// Açılabildiyse ortak depo; açılamadıysa `nil` (hata `result` içinde).
    static var container: ModelContainer? { try? result.get() }

    /// Depoyu başka süreçlerle sırayla açar; açılamazsa kısa bir beklemeden sonra bir kez daha dener.
    ///
    /// Model yeni alan kazanınca ilk açılış depo dosyasını yerinde göç ettirir (hafif göç: yeni sütunlar ve
    /// sürüm bilgisi). Yeni sürüm kurulunca sistem widget'ı da hemen yeniden çalıştırır; uygulama ile widget
    /// (ya da paylaşım eklentisi) aynı anda açarsa ikisi birden göçe girer ve geride kalan "Incompatible
    /// metadata after migration" (Cocoa 134100/134110) hatasıyla düşer; uygulamada "Veritabanı açılamadı"
    /// ekranı çıkar, ikinci açılış normaldir. Açılış bu yüzden App Group'taki bir kilit dosyasıyla sıraya
    /// konur: sonra gelen süreç depoyu göçü bitmiş hâlde bulur. Kilit yalnızca açılış süresince tutulur
    /// (askıya alınan süreç paylaşılan klasörde kilit tutarsa iOS onu kapatır).
    private static func openSerialized(
        at storeURL: URL,
        _ open: () throws -> ModelContainer
    ) throws -> ModelContainer {
        let lockPath = storeURL.path(percentEncoded: false) + ".lock"
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        var locked = false
        if descriptor >= 0 {
            // Öteki süreç göçü birkaç saniyede bitirir; takılırsa (olmamalı) kilitsiz devam edilir.
            let deadline = Date.now.addingTimeInterval(5)
            while true {
                locked = flock(descriptor, LOCK_EX | LOCK_NB) == 0
                if locked || Date.now >= deadline { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if !locked { logger.error("Depo kilidi alınamadı; kilitsiz açılıyor") }
        }
        defer {
            if locked { flock(descriptor, LOCK_UN) }
            if descriptor >= 0 { close(descriptor) }
        }
        do {
            return try open()
        } catch {
            // Kilidi tutmayan (eski sürüm) bir süreçle çakışma ya da geçici bir sorun: bir kez daha dene.
            logger.error("Depo ilk denemede açılamadı, yeniden deneniyor: \(String(describing: error), privacy: .public)")
            Thread.sleep(forTimeInterval: 0.5)
            return try open()
        }
    }

    private static func sharedStoreURL() -> URL? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directory = group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: storeName)
    }

    /// İlk sürüm veriyi uygulamanın kendi klasöründe tutuyordu. Ortak depo henüz yoksa
    /// eski dosyaları (ana dosya + SQLite yan dosyaları) oraya taşır; kelimeler kaybolmaz.
    private static func migrateLegacyStore(to storeURL: URL) {
        let fileManager = FileManager.default
        let legacyURL = URL.applicationSupportDirectory.appending(path: storeName)
        // path() yüzde kodlu döner ("Application%20Support"); dosya sistemi için kodsuz yol gerekir.
        func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path(percentEncoded: false)) }
        guard legacyURL != storeURL, exists(legacyURL), !exists(storeURL) else { return }

        let legacyDirectory = legacyURL.deletingLastPathComponent()
        let sharedDirectory = storeURL.deletingLastPathComponent()
        for suffix in ["", "-shm", "-wal"] {
            let source = legacyDirectory.appending(path: storeName + suffix)
            if exists(source) {
                try? fileManager.moveItem(at: source, to: sharedDirectory.appending(path: storeName + suffix))
            }
        }
    }
}

/// Depo açıldıysa içeriği o depoyla gösterir; açılamadıysa hatayı anlatan ekranı.
struct StoreGate<Content: View>: View {
    var result: Result<ModelContainer, Error> = SharedStore.result
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch result {
        case .success(let container):
            content().modelContainer(container)
        case .failure(let error):
            ContentUnavailableView(
                "Veritabanı açılamadı",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
            #if os(macOS)
            .frame(minWidth: 320, minHeight: 220)
            #endif
        }
    }
}
