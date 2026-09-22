import Foundation
import SwiftData

/// Uygulama ile paylaşım eklentisinin (Kelime Ekle) ortak kullandığı veri deposu.
///
/// Veritabanı App Group klasöründe durur; böylece kitaptan paylaşılan kelime,
/// uygulama açılınca listede görünür.
enum SharedStore {
    static let appGroupID = "group.com.burakalemdar.KelimeDefteri"
    private static let storeName = "default.store"

    /// Uygulama ve eklenti arasında paylaşılan küçük ayarlar (ör. son kaynak kitap).
    static let defaults = UserDefaults(suiteName: appGroupID) ?? .standard

    static let container: ModelContainer = {
        do {
            guard let storeURL = sharedStoreURL() else {
                // App Group yetkisi yoksa (olmamalı) uygulamanın kendi klasörüne düş.
                return try ModelContainer(for: Word.self)
            }
            migrateLegacyStore(to: storeURL)
            return try ModelContainer(for: Word.self, configurations: ModelConfiguration(url: storeURL))
        } catch {
            fatalError("Kelime veritabanı açılamadı: \(error)")
        }
    }()

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
