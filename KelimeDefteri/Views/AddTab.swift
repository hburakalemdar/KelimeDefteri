import SwiftUI
import UIKit

/// Ekle sekmesi. "Panodaki Kelimeyi Ekle" kısayolu gelince formu o metinle yeniden açar.
struct AddTab: View {
    private let router = AddRouter.shared
    @State private var draft = SharedTextParser.Draft()
    /// Değişince form sıfırdan kurulur (taslak yalnızca ilk açılışta okunur).
    @State private var formID = UUID()

    var body: some View {
        NavigationStack {
            WordFormView(mode: .add, draft: draft)
        }
        .id(formID)
        .onChange(of: router.pending, initial: true) { _, request in
            guard let request else { return }
            router.pending = nil
            // Pano yalnızca metin varsa okunur; iOS o anda "Yapıştırmaya izin ver" sorabilir.
            draft = ClipboardAdd.draft(text: request.text) {
                UIPasteboard.general.hasStrings ? UIPasteboard.general.string : nil
            }
            formID = UUID()
        }
    }
}
