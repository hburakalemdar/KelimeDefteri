import SwiftUI
import WidgetKit

/// Kelime Defteri widget'ları: ana ekranda soru, kilit ekranında hafıza özeti, Denetim Merkezi'nde Hızlı Tur.
@main
struct KelimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuizWidget()
        SummaryWidget()
        QuickRoundControl()
    }
}
