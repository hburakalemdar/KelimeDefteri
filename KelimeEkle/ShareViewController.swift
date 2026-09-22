import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Paylaş menüsündeki "Kelime Defteri" penceresi.
///
/// Paylaşılan metni okur, taslağa çevirir ve uygulamadaki ekleme formunu gösterir.
/// Kaydedilen kelime ortak depoya yazılır; uygulama açılınca listede görünür.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        Task {
            let draft = SharedTextParser.draft(from: await sharedText())
            show(draft)
        }
    }

    private func show(_ draft: SharedTextParser.Draft) {
        let root = NavigationStack {
            WordFormView(mode: .add, draft: draft) { [weak self] saved in
                self?.finish(saved: saved)
            }
        }
        .modelContainer(SharedStore.container)
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
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }

    /// Paylaşılan ilk düz metni döndürür (Books, Safari, PDF okuyucular seçimi böyle gönderir).
    private func sharedText() async -> String {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.canLoadObject(ofClass: NSString.self) {
                if let text = await Self.loadString(from: provider), !text.isEmpty {
                    return text
                }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private nonisolated static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { String($0) })
            }
        }
    }
}
