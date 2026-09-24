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
    nonisolated static let schema = Schema([Word.self, ReviewLog.self])

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
                container = try ModelContainer(for: schema, configurations: configuration)
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
