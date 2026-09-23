import AppIntents
import SwiftUI
import WidgetKit

/// Denetim Merkezi, kilit ekranı düğmesi ve Eylem düğmesi: tek basışla Hızlı Tur.
struct QuickRoundControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Glance.controlKind) {
            ControlWidgetButton(action: OpenQuickRoundIntent()) {
                Label("Hızlı Tur", systemImage: "bolt.fill")
            }
        }
        .displayName("Hızlı Tur")
        .description("5 kelimelik Hızlı Tur'u başlatır.")
    }
}
