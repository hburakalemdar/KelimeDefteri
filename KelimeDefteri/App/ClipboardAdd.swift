import AppIntents
import Foundation
import Observation

/// Panodaki (ya da Kısayollar'dan verilen) metinden Ekle sekmesinin taslağını çıkarır.
nonisolated enum ClipboardAdd {
    /// Verilen metin doluysa o, değilse pano okunur. Bağlantı ya da boş metin boş taslak verir.
    static func draft(text: String?, clipboard: () -> String?) -> SharedTextParser.Draft {
        let given = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = given.isEmpty ? (clipboard() ?? "") : given
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // Panoda kalmış bir bağlantı kelimeye çevrilmesin ("https example com").
        if let url = URL(string: trimmed), url.scheme != nil, url.host() != nil { return .init() }
        return SharedTextParser.draft(from: trimmed)
    }
}

/// Kısayoldan gelen "panodaki kelimeyi ekle" isteği. Uygulama yeni açılıyorsa istek bekler;
/// Ekle sekmesi görünce karşılar.
@Observable
final class AddRouter {
    static let shared = AddRouter()

    struct Request: Equatable {
        let id = UUID()
        /// Kısayoldan verilen metin; yoksa pano okunur.
        var text: String?
    }

    /// Ekle sekmesinin karşılayacağı istek.
    var pending: Request?
    /// Her istekte artar; ana ekran bununla Ekle sekmesine geçer.
    private(set) var requestCount = 0

    func open(text: String?) {
        pending = Request(text: text)
        requestCount += 1
    }
}

/// Kısayollar, Arkaya Vurma ve Eylem düğmesi: uygulamayı açıp panodaki kelimeyle Ekle formunu doldurur.
struct AddFromClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Panodaki Kelimeyi Ekle"
    static let description = IntentDescription(
        "Kelime Defteri'ni açıp kopyalanan kelimeyi ya da cümleyi Ekle formuna yerleştirir."
    )
    static let openAppWhenRun = true

    /// Kısayollar'da "Panoyu Al" gibi bir eylemle bağlanabilir; boşsa uygulama panoyu okur.
    @Parameter(title: "Metin")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        AddRouter.shared.open(text: text)
        return .result()
    }
}

/// Kısayollar uygulamasında ve Siri'de kendiliğinden görünen kısayollar.
struct KelimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFromClipboardIntent(),
            phrases: [
                "\(.applicationName) ile panodaki kelimeyi ekle",
                "Panodaki kelimeyi \(.applicationName)'ne ekle",
            ],
            shortTitle: "Panodaki Kelimeyi Ekle",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: OpenQuickRoundIntent(),
            phrases: ["\(.applicationName) ile hızlı tur"],
            shortTitle: "Hızlı Tur",
            systemImageName: "bolt.fill"
        )
    }
}
