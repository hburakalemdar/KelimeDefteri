import CloudKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var words: [Word]

    @AppStorage(ReminderSettings.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour
    @AppStorage(ReminderSettings.minuteKey) private var reminderMinute = ReminderSettings.defaultMinute
    @State private var permissionDenied = false
    @State private var iCloudStatus: CKAccountStatus?

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminderHour = parts.hour ?? ReminderSettings.defaultHour
            reminderMinute = parts.minute ?? ReminderSettings.defaultMinute
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Günlük hatırlatma", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Saat", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Hatırlatma")
            } footer: {
                Text("Sırada kelime olan günlerde, seçtiğin saatte kaç kelimenin beklediğini söyleyen bir bildirim gelir. Uygulama ikonunda da sıradaki kelime sayısı görünür.")
            }

            if permissionDenied {
                Section {
                    Label("Bildirim izni kapalı. Hatırlatma için iPhone ayarlarından Kelime Defteri'ne bildirim izni ver.", systemImage: "bell.slash")
                        .font(.subheadline)
                    Button("Ayarları aç") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section {
                LabeledContent("iCloud eşitleme") {
                    switch iCloudStatus {
                    case .available: Label("Açık", systemImage: "checkmark.icloud").foregroundStyle(.green)
                    case nil: ProgressView()
                    default: Label("Kapalı", systemImage: "xmark.icloud").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Eşitleme")
            } footer: {
                Text(iCloudStatus == .available || iCloudStatus == nil
                     ? "Kelimelerin iCloud'da yedeklenir; iPhone ve Mac'te aynı defter görünür. Mac'te paylaşarak eklediğin kelime, Mac uygulaması açıkken telefona gider."
                     : "Bu cihazda iCloud'a giriş yapılmamış ya da iCloud Drive kapalı. Kelimeler yalnızca bu cihazda saklanıyor.")
            }

            Section("Defterin") {
                LabeledContent("Toplam kelime", value: "\(words.count)")
                LabeledContent("Öğrenilen", value: "\(words.filter(\.isLearned).count)")
                LabeledContent("Toplam tekrar", value: "\(words.reduce(0) { $0 + $1.reviewCount })")
                if let accuracy {
                    LabeledContent("Doğru bilme oranı", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { dismiss() }
            }
        }
        .task {
            iCloudStatus = (try? await CKContainer(identifier: SharedStore.cloudKitContainerID).accountStatus()) ?? .couldNotDetermine
            let denied = await ReminderScheduler.isDenied()
            permissionDenied = reminderEnabled && denied
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task {
                if enabled {
                    let granted = await ReminderScheduler.requestPermission()
                    permissionDenied = !granted
                    if !granted { reminderEnabled = false }
                } else {
                    permissionDenied = false
                }
                await ReminderScheduler.refresh(context: context)
            }
        }
        .onChange(of: reminderHour) { Task { await ReminderScheduler.refresh(context: context) } }
        .onChange(of: reminderMinute) { Task { await ReminderScheduler.refresh(context: context) } }
    }

    private var accuracy: Double? {
        let reviews = words.reduce(0) { $0 + $1.reviewCount }
        guard reviews > 0 else { return nil }
        return Double(words.reduce(0) { $0 + $1.correctCount }) / Double(reviews)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewData.container)
}
#endif
