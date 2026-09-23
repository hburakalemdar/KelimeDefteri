import SwiftData
import SwiftUI

/// Menü çubuğu simgesine tıklayınca açılan pencere: üstte Çalış / Ekle seçimi, altta
/// kelime listesi, ayarlar ve çıkış.
struct MenuBarView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case study = "Çalış"
        case add = "Ekle"
        var id: Self { self }
    }

    @State private var page: Page = .study
    /// Çalışma turu burada tutulur: Çalış ↔ Ekle geçişinde çalışma sayfası yeniden kurulsa da tur sürer.
    @State private var session = StudySession()
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Picker("Bölüm", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch page {
                case .study:
                    MacStudyView(session: session, onAddTapped: { page = .add })
                case .add:
                    WordFormView(mode: .add)
                }
            }
            .frame(height: 430)

            Divider()

            footer
        }
        .frame(width: 380)
        .onDisappear {
            // Pencere kapanınca değişiklikleri yaz ve hatırlatmaları güncel sayılarla kur.
            context.saveLogging()
            Task { await ReminderScheduler.refresh(context: context) }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openWindow(id: WindowID.words)
                // Dock'ta görünmeyen uygulamanın penceresi öndeki uygulamanın arkasında kalmasın.
                NSApp.activate()
                dismiss()
            } label: {
                Label("Kelimelerim", systemImage: "books.vertical")
            }
            .keyboardShortcut("l")

            Spacer()

            Button {
                openSettings()
                NSApp.activate()
                dismiss()
            } label: {
                Label("Ayarlar", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(",")
            .help("Ayarlar (⌘,)")

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Çık", systemImage: "power")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("q")
            .help("Kelime Defteri'nden çık (⌘Q)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
