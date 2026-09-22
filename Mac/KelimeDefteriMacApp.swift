import SwiftData
import SwiftUI

/// Mac sürümü: Dock'ta görünmez (LSUIElement), menü çubuğunda yaşar.
///
/// Menü çubuğu simgesine tıklayınca Çalış / Ekle penceresi açılır; kelime listesi ve
/// ayarlar ayrı Mac pencerelerindedir. ⇧⌘E servisi `AppDelegate`te karşılanır.
@main
struct KelimeDefteriMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .modelContainer(SharedStore.container)
        } label: {
            MenuBarLabel()
                .modelContainer(SharedStore.container)
        }
        .menuBarExtraStyle(.window)

        Window("Kelimelerim", id: WindowID.words) {
            WordsWindow()
        }
        .modelContainer(SharedStore.container)
        .defaultSize(width: 760, height: 480)

        Settings {
            TabView {
                Tab("Genel", systemImage: "gearshape") {
                    MacSettingsView()
                }
                Tab("İlerleme", systemImage: "chart.bar") {
                    ProgressChartView()
                        .frame(width: 460, height: 640)
                }
            }
        }
        .modelContainer(SharedStore.container)
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let words = "words"
}

/// Menü çubuğundaki simge; sırada kelime varsa sayısını da gösterir.
private struct MenuBarLabel: View {
    @Query private var words: [Word]

    var body: some View {
        let due = words.count { $0.isDue() }
        if due > 0 {
            Label("\(due)", systemImage: "character.book.closed")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "character.book.closed")
        }
    }
}
