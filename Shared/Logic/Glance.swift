import Foundation
#if os(iOS)
import AppIntents
import Observation
import WidgetKit
#endif

/// Widget'lar ve uygulama arasındaki ortak adlar, bağlantılar ve tazeleme.
enum Glance {
    /// Kilit ekranı widget'ının açtığı bağlantı: Hızlı Tur.
    static let quickRoundURL = URL(string: "kelimedefteri://quick")!
    static let urlScheme = "kelimedefteri"

    static let quizKind = "KelimeSoru"
    static let summaryKind = "KelimeHafiza"
    static let controlKind = "com.burakalemdar.KelimeDefteri.HizliTur"

    /// Bağlantı Hızlı Tur'u mu istiyor.
    static func isQuickRound(_ url: URL) -> Bool {
        url.scheme == urlScheme && url.host() == "quick"
    }

    /// Kelime eklenince ya da cevaplanınca widget'lar yeni sayıları göstersin.
    static func reloadWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

#if os(iOS)
/// Uygulama dışından gelen "Hızlı Tur'u aç" isteği (Denetim Merkezi, Eylem düğmesi, kilit ekranı).
/// Uygulama henüz açılmamışsa istek bekler; ana ekran görünce karşılar.
@Observable
final class GlanceRouter {
    static let shared = GlanceRouter()
    var quickRoundRequested = false
}

/// Denetim Merkezi ve Eylem düğmesi: uygulamayı açıp Hızlı Tur'u başlatır.
/// Uygulamada da derlenir; `openAppWhenRun` olduğu için uygulama sürecinde çalışır.
struct OpenQuickRoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Hızlı Tur"
    static let description = IntentDescription("Kelime Defteri'ni açıp 5 kelimelik Hızlı Tur'u başlatır.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        GlanceRouter.shared.quickRoundRequested = true
        return .result()
    }
}
#endif
