import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case study, add, list
}

struct ContentView: View {
    @State private var selection: AppTab = .study
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView(selection: $selection) {
            Tab("Çalış", systemImage: "rectangle.on.rectangle.angled", value: AppTab.study) {
                StudyView(onAddTapped: { selection = .add })
            }
            Tab("Ekle", systemImage: "plus.circle", value: AppTab.add) {
                NavigationStack {
                    WordFormView(mode: .add)
                }
            }
            Tab("Kelimelerim", systemImage: "books.vertical", value: AppTab.list) {
                WordListView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Bildirim içerikleri planlandıkları anda sabitlenir; en güncel sayılarla yeniden kur.
            if phase == .background || phase == .active {
                try? context.save()
                Task { await ReminderScheduler.refresh(context: context) }
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
#endif
