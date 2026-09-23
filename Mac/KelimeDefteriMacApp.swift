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
            StoreGate {
                MenuBarView()
            }
        } label: {
            if let container = SharedStore.container {
                MenuBarLabel()
                    .modelContainer(container)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Kelimelerim", id: WindowID.words) {
            StoreGate {
                WordsWindow()
            }
        }
        .defaultSize(width: 760, height: 480)

        Settings {
            StoreGate {
                settingsTabs
            }
        }
        .windowResizability(.contentSize)
    }

    private var settingsTabs: some View {
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
}

enum WindowID {
    static let words = "words"
}

/// Menü çubuğundaki simge; Günlük Tekrar'ın soracağı kelime varsa sayısını da gösterir (bildirimle aynı sayı).
private struct MenuBarLabel: View {
    @Query private var words: [Word]

    var body: some View {
        let due = ReminderScheduler.dailyTotal(words)
        if due > 0 {
            Label("\(due)", systemImage: "character.book.closed")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "character.book.closed")
        }
    }
}
