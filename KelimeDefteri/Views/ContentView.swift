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
    /// Hafıza zamanla azaldığı için rozet her dakika tazelenir (Çalış ekranı gibi).
    @State private var now = Date.now
    /// Kilit ekranı widget'ı ya da Denetim Merkezi'nden istenen Hızlı Tur.
    @State private var showQuickRound = false
    private let router = GlanceRouter.shared

    /// Rozet: Günlük Tekrar'ın soracağı kelime sayısı.
    private var badgeCount: Int {
        let count = StudySession.dailyCount(words, now: now)
        return count.weak + count.new
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Çalış", systemImage: "rectangle.stack", value: AppTab.study) {
                StudyView(onAddTapped: { selection = .add })
            }
            .badge(badgeCount)
            Tab("Ekle", systemImage: "plus.circle", value: AppTab.add) {
                AddTab()
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
        .fullScreenCover(isPresented: $showQuickRound) {
            QuickMixGameView()
        }
        .onOpenURL { url in
            if Glance.isQuickRound(url) { openQuickRound() }
        }
        .onChange(of: router.quickRoundRequested, initial: true) { _, requested in
            guard requested else { return }
            router.quickRoundRequested = false
            openQuickRound()
        }
        // "Panodaki Kelimeyi Ekle" kısayolu: formu AddTab doldurur.
        .onChange(of: AddRouter.shared.requestCount, initial: true) { _, count in
            if count > 0 { selection = .add }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            // Bildirim içerikleri planlandıkları anda sabitlenir; en güncel sayılarla yeniden kur.
            if phase == .active {
                MemoryMigration.migrateIfNeeded(context: context)
                // İki cihazda eşitlenmeden eklenen aynı kelimeyi birleştir, sahipsiz cevap kayıtlarını temizle.
                StoreMaintenance.run(in: context)
                now = .now
            }
            if phase == .background || phase == .active {
                context.saveLogging()
                Task { await ReminderScheduler.refresh(context: context) }
            }
            // Uygulamada verilen cevaplar ve eklenen kelimeler widget'lara yansısın.
            if phase == .background { Glance.reloadWidgets() }
        }
    }

    /// Çalış sekmesine geçip Hızlı Tur'u açar; defter boşsa yalnızca Çalış sekmesi görünür.
    /// Hızlı Tur zaten açıksa olduğu gibi kalır. Başka bir ekran (oyun, Ayarlar, düzenleme) açıksa
    /// SwiftUI üstüne ikinci tam ekranı açamaz; önce o kapatılır (cevaplar zaten anında kaydedilir).
    private func openQuickRound() {
        selection = .study
        guard !words.isEmpty, !showQuickRound else { return }
        guard let root = Self.rootController, root.presentedViewController != nil else {
            showQuickRound = true
            return
        }
        Task {
            await root.dismiss(animated: true)
            showQuickRound = true
        }
    }

    /// Ön plandaki pencerenin kök denetleyicisi (açık ekranları kapatmak için).
    private static var rootController: UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
#endif
