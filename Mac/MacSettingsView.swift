import CloudKit
import ServiceManagement
import SwiftData
import SwiftUI

/// Mac Ayarlar penceresi (⌘,).
struct MacSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var words: [Word]

    @AppStorage(ReminderSettings.enabledKey) private var reminderEnabled = false
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour
    @AppStorage(ReminderSettings.minuteKey) private var reminderMinute = ReminderSettings.defaultMinute
    @AppStorage(DailyGoal.key, store: DailyGoal.defaults) private var dailyGoal = DailyGoal.defaultTarget
    @State private var permissionDenied = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
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
                Toggle("Oturum açılınca başlat", isOn: $launchAtLogin)
            } header: {
                Text("Genel")
            } footer: {
                Text("Hızlı ekleme: herhangi bir uygulamada (Önizleme, Safari…) kelimeyi ya da cümleyi seçip ⇧⌘E'ye bas veya sağ tık › Servisler › Kelime Defteri'ne Ekle'yi seç.")
            }

            Section {
                Toggle("Günlük hatırlatma", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Saat", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                if permissionDenied {
                    LabeledContent {
                        Button("Sistem Ayarları'nı aç") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                openURL(url)
                            }
                        }
                    } label: {
                        Label("Bildirim izni kapalı", systemImage: "bell.slash")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Hatırlatma")
            } footer: {
                Text("Sorulacak kelime olan günlerde, seçtiğin saatte Günlük Tekrar'ın kaç kelime soracağını söyleyen bir bildirim gelir.")
            }

            Section {
                Picker("Günlük hedef", selection: $dailyGoal) {
                    ForEach(DailyGoal.options, id: \.self) { Text("\($0) cevap").tag($0) }
                }
            } header: {
                Text("Hedef")
            } footer: {
                Text("Çalış sayfasındaki halka her gün bu kadar cevapla kapanır; iPhone ve Mac'teki cevaplar birlikte sayılır. Halkayı üst üste kapattığın günler serini oluşturur. Hedef her cihazda ayrı seçilir.")
            }

            Section {
                LabeledContent("iCloud eşitleme") {
                    switch iCloudStatus {
                    case .available: Text("Açık").foregroundStyle(.green)
                    case nil: ProgressView().controlSize(.small)
                    default: Text("Kapalı").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Eşitleme")
            } footer: {
                Text(iCloudStatus == .available || iCloudStatus == nil
                     ? "Kelimelerin iCloud'da yedeklenir; iPhone ve Mac'te aynı defter görünür."
                     : "Bu Mac'te iCloud'a giriş yapılmamış ya da iCloud Drive kapalı. Kelimeler yalnızca bu Mac'te saklanıyor.")
            }

            Section("Defterin") {
                LabeledContent("Toplam kelime", value: "\(words.count)")
                LabeledContent("Öğrenilen", value: "\(words.filter(\.isLearned).count)")
                LabeledContent("Toplam tekrar", value: "\(words.reduce(0) { $0 + $1.answerCount })")
                if let accuracy {
                    LabeledContent("Doğru bilme oranı", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 720)
        // Pencere açılınca hafıza alanları cevap kayıtlarından yeniden hesaplanır (İlerleme bunları okur).
        .onAppear { MemoryCache.refreshAll(in: context) }
        .task {
            iCloudStatus = (try? await CKContainer(identifier: SharedStore.cloudKitContainerID).accountStatus()) ?? .couldNotDetermine
            let denied = await ReminderScheduler.isDenied()
            permissionDenied = reminderEnabled && denied
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task {
                // İzin reddedilince anahtar kapanır; uyarı, kullanıcı sebebini görsün diye kalır.
                if enabled {
                    let granted = await ReminderScheduler.requestPermission()
                    permissionDenied = !granted
                    if !granted { reminderEnabled = false }
                }
                await ReminderScheduler.refresh(context: context)
            }
        }
        // Hedef bütün cihazlarda tek (iCloud).
        .onChange(of: dailyGoal) { _, goal in GoalCloudSync.userChose(goal) }
        .onChange(of: reminderHour) { Task { await ReminderScheduler.refresh(context: context) } }
        .onChange(of: reminderMinute) { Task { await ReminderScheduler.refresh(context: context) } }
    }

    private var accuracy: Double? {
        let reviews = words.reduce(0) { $0 + $1.answerCount }
        guard reviews > 0 else { return nil }
        return Double(words.reduce(0) { $0 + $1.correctAnswerCount }) / Double(reviews)
    }
}
