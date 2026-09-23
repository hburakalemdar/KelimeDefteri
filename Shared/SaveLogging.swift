import os
import SwiftData

/// Kaydetme hatalarının yazıldığı günlük (Konsol'da "store" kategorisi).
private let storeLog = Logger(subsystem: "com.burakalemdar.KelimeDefteri", category: "store")

extension ModelContext {
    /// Değişiklikleri diske yazar; hata olursa sessizce yutmak yerine günlüğe yazar.
    /// Başarılıysa `true`; kullanıcıya uyarı göstermesi gereken yer sonucu kullanır.
    @discardableResult
    func saveLogging(_ what: String = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            storeLog.error("Kaydedilemedi (\(what, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
