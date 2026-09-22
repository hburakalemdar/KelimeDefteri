# Kelime Defteri — proje notları

Teknik kitaplardaki İngilizce kelimeleri Türkçesiyle kaydedip Leitner aralıklı tekrarıyla
çalıştıran iPhone + Mac (Catalyst) uygulaması. SwiftUI, SwiftData + CloudKit, Swift 6
(varsayılan izolasyon MainActor). Kullanıcı Türkçe konuşur; arayüz metinleri Türkçe.
Ayrıntılı özellik listesi ve yapı: README.md.

## Hedefler (targets)

- **KelimeDefteri** — ana uygulama (iOS 18+, Mac Catalyst 26+). `KelimeDefteri/` + `Shared/`.
- **KelimeEkle** — Paylaş menüsü eklentisi. `KelimeEkle/` + `Shared/`. iCloud'a kendisi eşitlemez;
  App Group'taki ortak SQLite'a yazar, ana uygulama kalıcı geçmişten görüp iCloud'a gönderir.
- **KelimeDefteriHelper** — yalnızca Mac: ⇧⌘E "Kelime Defteri'ne Ekle" servisini sağlayan görünmez
  AppKit uygulaması (`MacHelper/`, `Contents/Library/Helpers` içine gömülür). Seçili metni
  `kelimedefteri://add?text=…` ile ana uygulamaya iletir.
- **KelimeDefteriTests** — Swift Testing birim testleri.

Proje dosyası elle yazıldı ve dosya sistemi senkron gruplarını kullanır: bir klasöre dosya
koymak onu hedefe eklemek için yeterli. `Shared/` hem uygulamada hem eklentide derlenir.

## Derleme ve kurulum

```bash
# Testler (simülatör)
xcodebuild test -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build

# Kullanıcının iPhone 14'ü
xcodebuild -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'id=<IPHONE_UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <IPHONE_UDID> build/Build/Products/Debug-iphoneos/KelimeDefteri.app

# Mac: Release derle, /Applications'a kur
xcodebuild -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -configuration Release -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build -allowProvisioningUpdates build
```

Mac kurulumundan sonra **mutlaka** `build/` içindeki .app kopyalarının LaunchServices kaydını sil
(`lsregister -u`) ve Mac ürünlerini sil; yoksa servis ve paylaşım eklentisi çift görünür, eski
kopya ⇧⌘E'yi yakalayıp uygulamayı çökertebilir. Sonra `/System/Library/CoreServices/pbs -update`.
`build/.metadata_never_index` Spotlight'ın bu klasörü yeniden kaydetmesini engeller.

## Bilinen tuzaklar

- Catalyst uygulaması bir macOS servisi tarafından doğrudan (NSPortName) soğuk başlatılırsa dyld
  "SwiftUI symbol missing" ile çöker — bu yüzden servis ayrı AppKit yardımcısında.
- Üçüncü parti servis kısayolu, önündeki uygulamanın menüsü aynı tuşu kullanıyorsa çalışmaz
  (⇧⌘K Önizleme'de çakışıyordu → ⇧⌘E). Sistem bu kısayolları varsayılan olarak her zaman açmaz.
- Mac'te pencere araç çubuğundaki `ToolbarItem` düğmelerinin `.disabled` durumu güncellenmiyor;
  form eylemleri formun içinde duruyor.
- Translation framework simülatörde çalışmaz; gerçek cihazda test et.
- Simülatöre otomatik yazı yazarken Türkçe klavye düzeni harfleri bozar; bu uygulama hatası değil.
- Mac'te `~/Library/Group Containers/group.com.burakalemdar.KelimeDefteri` TCC korumalı, dışarıdan okunamaz.
- `URL.path()` yüzde kodlu döner; dosya sistemi için `path(percentEncoded: false)`.
- CloudKit şeması geliştirme ortamında; TestFlight/App Store öncesi üretime aktarılmalı.

## Çalışma şekli

- Kullanıcı "sen yaz, ben kullanayım" diyor: özelliği yaz, test et, cihazlara kur, sonucu sade Türkçe anlat.
- Apple Developer hesabında değişiklik (cihaz/App Group/iCloud kaydı vb.) ve commit/push öncesi onay al.
- Kullanıcının Mac ekranını devralmadan önce aktif çalışıp çalışmadığına dikkat et; Önizleme'yi zorla kapatma.
