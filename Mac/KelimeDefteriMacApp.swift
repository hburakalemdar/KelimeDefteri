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
            StoreGate(result: Self.store) {
                MenuBarView()
            }
        } label: {
            if let container = try? Self.store.get() {
                MenuBarLabel()
                    .modelContainer(container)
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Kelimelerim", id: WindowID.words) {
            StoreGate(result: Self.store) {
                WordsWindow()
            }
        }
        .defaultSize(width: 760, height: 480)

        Settings {
            StoreGate(result: Self.store) {
                settingsTabs
            }
        }
        .windowResizability(.contentSize)
    }

    /// Ekran görüntüsü ve deneme için (yalnızca DEBUG): `-demo` ile açılınca gerçek defter yerine örnek kelimeler.
    /// ⇧⌘E servisi ve hatırlatmalar her zaman gerçek defteri kullanır.
    static let store: Result<ModelContainer, Error> = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") { return .success(PreviewData.container) }
        #endif
        return SharedStore.result
    }()

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
    @AppStorage(DailyNewAllowance.key, store: DailyGoal.defaults) private var newAllowance = DailyNewAllowance.defaultValue

    var body: some View {
        let due = ReminderScheduler.dailyTotal(words, newAllowance: DailyNewAllowance.validated(newAllowance))
        if due > 0 {
            Label("\(due)", systemImage: "character.book.closed")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "character.book.closed")
        }
    }
}
