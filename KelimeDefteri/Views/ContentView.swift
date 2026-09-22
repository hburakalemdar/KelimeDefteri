import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case study, add, list
}

struct ContentView: View {
    @State private var selection: AppTab = .study
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]

    var body: some View {
        TabView(selection: $selection) {
            Tab("Çalış", systemImage: "rectangle.stack", value: AppTab.study) {
                StudyView(onAddTapped: { selection = .add })
            }
            .badge(words.count { $0.isDue() })
            Tab("Ekle", systemImage: "plus.circle", value: AppTab.add) {
                NavigationStack {
                    WordFormView(mode: .add)
                }
            }
            Tab("Kelimelerim", systemImage: "books.vertical", value: AppTab.list) {
                WordListView()
            }
        }
        .dismissesKeyboardOnTap()
        #if DEBUG
        // Ekran görüntüsü için: `-shareDemo` ile Paylaş eklentisindeki formu aç.
        .sheet(isPresented: .constant(ProcessInfo.processInfo.arguments.contains("-shareDemo"))) {
            NavigationStack {
                WordFormView(
                    mode: .add,
                    draft: SharedTextParser.draft(from: "“Retries are safe only if the operation is idempotent.”\n\nExcerpt From\nDesigning Data-Intensive Applications\nMartin Kleppmann"),
                    onFinish: { _ in }
                )
            }
        }
        #endif
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
