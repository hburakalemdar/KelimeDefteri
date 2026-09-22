import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case study, add, list
}

struct ContentView: View {
    @State private var selection: AppTab = .study
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    /// `kelimedefteri://add?text=…` ile gelen metnin taslağı (Mac'te ⇧⌘E servisi bunu açar);
    /// yeni taslakta form yeniden kurulur.
    @State private var quickAddDraft = SharedTextParser.Draft()
    @State private var quickAddID = UUID()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Çalış", systemImage: "rectangle.on.rectangle.angled", value: AppTab.study) {
                StudyView(onAddTapped: { selection = .add })
            }
            Tab("Ekle", systemImage: "plus.circle", value: AppTab.add) {
                NavigationStack {
                    WordFormView(mode: .add, draft: quickAddDraft)
                        .id(quickAddID)
                }
            }
            Tab("Kelimelerim", systemImage: "books.vertical", value: AppTab.list) {
                WordListView()
            }
        }
        .onOpenURL(perform: openQuickAdd)
        .onChange(of: scenePhase) { _, phase in
            // Bildirim içerikleri planlandıkları anda sabitlenir; en güncel sayılarla yeniden kur.
            if phase == .background || phase == .active {
                try? context.save()
                Task { await ReminderScheduler.refresh(context: context) }
            }
        }
    }

    private func openQuickAdd(_ url: URL) {
        guard url.scheme == "kelimedefteri", url.host() == "add",
              let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "text" })?.value
        else { return }
        quickAddDraft = SharedTextParser.draft(from: text)
        quickAddID = UUID()
        selection = .add
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
#endif
