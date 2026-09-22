import AppKit
import SwiftData
import SwiftUI

/// "Kelime Defteri'ne Ekle" servisini (⇧⌘E) karşılar ve açılışta hatırlatmaları kurar.
///
/// Servis seçili metni gönderir; uygulama kapalıysa macOS onu açar. Metin, ayrı bir
/// "Kelime ekle" penceresinde taslak olarak açılır.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickAddWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        Task { await ReminderScheduler.refresh(context: SharedStore.container.mainContext) }
    }

    @objc(addWord:userData:error:)
    func addWord(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error.pointee = "Seçili metin bulunamadı." as NSString
            return
        }
        showQuickAdd(draft: SharedTextParser.draft(from: text))
    }

    private func showQuickAdd(draft: SharedTextParser.Draft) {
        quickAddWindow?.close()

        let form = NavigationStack {
            WordFormView(mode: .add, draft: draft) { [weak self] _ in
                self?.quickAddWindow?.close()
            }
        }
        .frame(width: 460, height: 560)
        .modelContainer(SharedStore.container)

        let window = NSWindow(contentViewController: NSHostingController(rootView: form))
        window.title = "Kelime Defteri'ne Ekle"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        quickAddWindow = window

        // Dock'ta görünmeyen uygulama; pencere öndeki uygulamanın üstüne gelsin.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
