import AppKit

/// Mac'te "Kelime Defteri'ne Ekle" servisini (⇧⌘E) sağlayan görünmez yardımcı uygulama.
///
/// macOS, servis için uygulamayı kendisi başlattığında Mac Catalyst uygulamalarını doğru
/// ortamla açamıyor; bu yüzden servisi saf AppKit ile yazılmış bu yardımcı karşılar.
/// Seçili metni `kelimedefteri://add?text=…` bağlantısıyla ana uygulamaya iletir;
/// ana uygulama kapalıysa macOS onu normal yoldan açar. İş bitince kendini kapatır.
@main
final class HelperApp: NSObject, NSApplicationDelegate {
    private static let idleLifetime: TimeInterval = 10
    private var quitTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = HelperApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        scheduleQuit()
    }

    @objc(addWord:userData:error:)
    func addWord(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        defer { scheduleQuit() }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error.pointee = "Seçili metin bulunamadı." as NSString
            return
        }
        var components = URLComponents()
        components.scheme = "kelimedefteri"
        components.host = "add"
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Yeni istek gelmezse birkaç saniye sonra kapan; bir sonraki kısayolda macOS yeniden açar.
    private func scheduleQuit() {
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: Self.idleLifetime, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }
}
