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
                Toggle(isOn: $reminderEnabled) {
                    Label { Text("Günlük Hatırlatma") } icon: { SettingsIcon(systemName: "bell.fill", color: .red) }
                }
                if reminderEnabled {
                    DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                        Label { Text("Saat") } icon: { SettingsIcon(systemName: "clock.fill", color: .orange) }
                    }
                }
                if permissionDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label { Text("Bildirim İzni Ver") } icon: { SettingsIcon(systemName: "bell.slash.fill", color: .gray) }
                    }
                }
            } header: {
                Text("Hatırlatma")
            } footer: {
                Text(reminderFooter)
            }

            Section {
                LabeledContent {
                    switch iCloudStatus {
                    case .available: Text("Açık")
                    case nil: ProgressView()
                    default: Text("Kapalı")
                    }
                } label: {
                    Label { Text("iCloud Eşitleme") } icon: { SettingsIcon(systemName: "icloud.fill", color: .blue) }
                }
            } header: {
                Text("Eşitleme")
            } footer: {
                Text(iCloudStatus == .available || iCloudStatus == nil
                     ? "Kelimelerin iCloud'da yedeklenir; iPhone ve Mac'te aynı defter görünür."
                     : "Bu cihazda iCloud'a giriş yapılmamış ya da iCloud Drive kapalı. Kelimeler yalnızca bu cihazda saklanıyor.")
            }

            Section("Defterin") {
                NavigationLink {
                    ProgressChartView()
                } label: {
                    Label { Text("İlerleme") } icon: { SettingsIcon(systemName: "chart.bar.fill", color: .green) }
                }
                LabeledContent("Toplam kelime", value: "\(words.count)")
                LabeledContent("Öğrenilen", value: "\(words.filter(\.isLearned).count)")
                LabeledContent("Toplam tekrar", value: "\(words.reduce(0) { $0 + $1.answerCount })")
                if let accuracy {
                    LabeledContent("Doğru bilme oranı", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
            }

            Section("Hakkında") {
                LabeledContent("Sürüm", value: Self.version)
            }
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
        .task {
            iCloudStatus = (try? await CKContainer(identifier: SharedStore.cloudKitContainerID).accountStatus()) ?? .couldNotDetermine
            let denied = await ReminderScheduler.isDenied()
            permissionDenied = reminderEnabled && denied
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task {
                // İzin reddedilince anahtar kapanır; uyarı, kullanıcı sebebini görsün diye kalır
                // (kapanmanın tetiklediği bu blok onu silmemeli).
                if enabled {
                    let granted = await ReminderScheduler.requestPermission()
                    permissionDenied = !granted
                    if !granted { reminderEnabled = false }
                }
                await ReminderScheduler.refresh(context: context)
            }
        }
        .onChange(of: reminderHour) { Task { await ReminderScheduler.refresh(context: context) } }
        .onChange(of: reminderMinute) { Task { await ReminderScheduler.refresh(context: context) } }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var reminderFooter: String {
        if permissionDenied {
            return "Bildirim izni kapalı. Hatırlatma için iPhone ayarlarından Kelime Defteri'ne bildirim izni ver."
        }
        if reminderEnabled {
            return "Zayıflayan kelime olan günlerde, seçtiğin saatte kaç kelimenin tekrar beklediğini söyleyen bir bildirim gelir. Uygulama simgesinde de Günlük Tekrar'da bekleyen kelime sayısı görünür."
        }
        return "Açarsan zayıflayan kelime olan günlerde, seçeceğin saatte bir bildirim gelir ve uygulama simgesinde Günlük Tekrar'da bekleyen kelime sayısı görünür."
    }

    private var accuracy: Double? {
        let reviews = words.reduce(0) { $0 + $1.answerCount }
        guard reviews > 0 else { return nil }
        return Double(words.reduce(0) { $0 + $1.correctAnswerCount }) / Double(reviews)
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
