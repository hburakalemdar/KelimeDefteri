#if os(iOS)
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Paylaş (KelimeEkle) ve eylem (KelimeEylem) eklentilerinin ortak penceresi.
///
/// Gelen metni okur, taslağa çevirir ve uygulamadaki ekleme formunu gösterir.
/// Kaydedilen kelime ortak depoya yazılır; uygulama açılınca listede görünür.
class AddWordExtensionController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        guard let container = SharedStore.container else {
            // Depo açılamadı (hata günlüğe yazıldı); formu göstermeden isteği hatayla kapat.
            if case .failure(let error) = SharedStore.result {
                extensionContext?.cancelRequest(withError: error)
            }
            return
        }
        Task {
            let draft = SharedTextParser.draft(from: await sharedText())
            show(draft, container: container)
        }
    }

    private func show(_ draft: SharedTextParser.Draft, container: ModelContainer) {
        let root = NavigationStack {
            WordFormView(mode: .add, draft: draft) { [weak self] saved in
                self?.finish(saved: saved)
            }
        }
        .modelContainer(container)
        .dismissesKeyboardOnTap()

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish(saved: Bool) {
        if saved {
            // Widget sorusu ve kilit ekranı özeti yeni kelimeyi hesaba katsın.
            Glance.reloadWidgets()
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }

    /// Gelen ilk düz metni döndürür (Books, Safari, PDF okuyucular seçimi böyle gönderir).
    private func sharedText() async -> String {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if let text = await Self.loadText(from: provider), !text.isEmpty {
                    return text
                }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty {
                return text
            }
        }
        return ""
    }

    /// Önce `NSString` olarak dener. Eylem eklentisinde (ve bazen Paylaş'ta) bu başarısız olur ve
    /// `attributedContentText` de gelmez; o zaman düz metin öğesi doğrudan istenir.
    private nonisolated static func loadText(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: NSString.self), let text = await loadString(from: provider), !text.isEmpty {
            return text
        }
        let type = UTType.plainText.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { item, _ in
                continuation.resume(returning: text(from: item))
            }
        }
    }

    private nonisolated static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { String($0) })
            }
        }
    }

    /// `loadItem`'ın verdiği öğe: metin, zengin metin ya da UTF-8 veri.
    private nonisolated static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let string as String: string
        case let attributed as NSAttributedString: attributed.string
        case let data as Data: String(data: data, encoding: .utf8)
        default: nil
        }
    }
}
#endif
