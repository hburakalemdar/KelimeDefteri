# Kelime Defteri — proje notları

Teknik kitaplardaki İngilizce kelimeleri Türkçesiyle kaydedip Leitner aralıklı tekrarıyla
çalıştıran iPhone + Mac uygulaması. SwiftUI, SwiftData + CloudKit, Swift 6
(varsayılan izolasyon MainActor). iOS 26+ (Liquid Glass: `.glass`/`.glassProminent`, `glassEffect`).
Tasarım dili sistem parçaları; İngilizce kelimeler New York serif, vurgu rengi sistemin varsayılanı (iOS mavi, Mac kullanıcının seçtiği renk). Kullanıcı Türkçe konuşur; arayüz metinleri Türkçe.
Ayrıntılı özellik listesi ve yapı: README.md.

## Hedefler (targets)

- **KelimeDefteri** — iPhone/iPad uygulaması (iOS 26+). `KelimeDefteri/` + `Shared/`.
- **KelimeEkle** — iOS Paylaş menüsü eklentisi. `KelimeEkle/` + `Shared/`. iCloud'a kendisi eşitlemez;
  App Group'taki ortak SQLite'a yazar, ana uygulama kalıcı geçmişten görüp iCloud'a gönderir.
- **KelimeEylem** — iOS eylem eklentisi (`com.apple.ui-services`, `…KelimeDefteri.KelimeEylem`): Paylaş
  sayfasının alt listesinde "Kelime Defteri’ne Ekle". KelimeEkle ile aynı akış (`Shared/AddWordExtensionController`);
  şablon simge `KelimeEylem/Assets.xcassets` (SF Symbol `character.book.closed`). Eylem eklentisine
  `attributedContentText` gelmez ve `NSString` yüklemesi başarısız olur; metin `loadItem` ile okunur.
- **KelimeWidget** — iOS widget eklentisi (`com.burakalemdar.KelimeDefteri.KelimeWidget`). `KelimeWidget/` +
  `Shared/`. KelimeEkle gibi App Group deposuna yazar; soru durumu App Group ayarlarında (`GlanceQuizStore`).
  Hızlı Tur bağlantısı `kelimedefteri://quick` (ContentView karşılar); denetim `OpenQuickRoundIntent`
  (Shared'da, uygulamada çalışır). Bildirim cevapları `NotificationDelegate` + `ReminderQuiz`.
- **KelimeDefteriMac** — yerel macOS uygulaması (macOS 26+, Catalyst değil). `Mac/` + `Shared/`.
  Dock'ta görünmez (LSUIElement), menü çubuğunda yaşar (MenuBarExtra): Çalış / Ekle penceresi,
  ayrı Kelimelerim (tablo) ve Ayarlar pencereleri. ⇧⌘E "Kelime Defteri'ne Ekle" servisini kendisi
  karşılar (`AppDelegate`), metni ayrı bir ekleme penceresinde açar. Paket kimliği iOS ile aynı
  (`com.burakalemdar.KelimeDefteri`), ürün adı `KelimeDefteri.app`, modül adı `KelimeDefteriMac`.
- **KelimeDefteriTests** — Swift Testing birim testleri (iOS).

Proje dosyası elle yazıldı ve dosya sistemi senkron gruplarını kullanır: bir klasöre dosya
koymak onu hedefe eklemek için yeterli. `Shared/` üç hedefte de derlenir (iOS uygulaması, eklenti,
Mac); platforma özel kısımlar `#if os(macOS)` / `#if os(iOS)` ile ayrılır (ör. `WordFormView`'in
Mac düzeni `macFields`).

## Derleme ve kurulum

```bash
# Testler (simülatör)
xcodebuild test -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build -parallel-testing-enabled NO -collect-test-diagnostics never

# Kullanıcının iPhone 14'ü
xcodebuild -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'id=<IPHONE_UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <IPHONE_UDID> build/Build/Products/Debug-iphoneos/KelimeDefteri.app

# Mac: Release derle, /Applications'a kur
xcodebuild -project KelimeDefteri.xcodeproj -scheme KelimeDefteriMac -configuration Release -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates build
```

Mac kurulumunda önce çalışan uygulamayı kapat (`osascript -e 'tell application id "com.burakalemdar.KelimeDefteri" to quit'`),
`build/Build/Products/Release/KelimeDefteri.app`'i `ditto` ile `/Applications`'a kopyala. Sonra **mutlaka**
`build/` içindeki .app kopyalarının LaunchServices kaydını sil (`lsregister -u`) ve Mac ürünlerini
(`build/Build/Products/{Release,Debug}`) sil; yoksa ⇧⌘E servisi çift görünür ya da eski kopyaya gider.
Sonra `lsregister -f -R /Applications/KelimeDefteri.app` ve `/System/Library/CoreServices/pbs -update`.
`build/.metadata_never_index` Spotlight'ın bu klasörü yeniden kaydetmesini engeller.

Ekran görüntüsü için (yalnızca DEBUG): `xcrun simctl launch booted com.burakalemdar.KelimeDefteri -demo`
gerçek defter yerine örnek kelimelerle açar; `-shareDemo` ek olarak Paylaş eklentisinin formunu gösterir.
Simülatör ekran görüntüsü: `xcrun simctl io booted screenshot x.png`. Testleri `-parallel-testing-enabled NO
-collect-test-diagnostics never` ile koş; paralelde simülatör kopyaları açılamayıp testler 0 sn'de "failed"
görünebiliyor, bir test başarısız olunca da `simctl diagnose` dakikalarca takılabiliyor.

Uygulama simgesi Icon Composer biçiminde: `KelimeDefteri/AppIcon.icon` ve `Mac/AppIcon.icon` (aynı dosyanın
iki kopyası; biri değişirse ötekini de güncelle). Katmanlar `Assets/` içinde 1024×1024 saydam PNG
(arka kart, ön kart, "Aa"); cam, koyu ve renklendirilmiş görünümü sistem üretir. Kontrol için:
`xcrun actool AppIcon.icon --compile out --platform iphoneos --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist out/p.plist`.

## Bilinen tuzaklar

- SwiftData bellek içi depo (`isStoredInMemoryOnly`) iOS 27 simülatöründe kaydederken ara ara çöküyor
  (`_obtainPermanentIDsForObjects`); örnek veri ve testler geçici dosya deposu kullanır.
- iOS 26 `Form` içinde pasif düğme siyah kalıyor; soluk görünmesi için yazı rengini elle ver.
- Mac'te `.tint` verilen `.glass` düğme de dolu görünür; öne çıkmayan düğmede yalnızca `foregroundStyle` kullan.

- Mac sürümü eskiden Catalyst'ti: Catalyst uygulaması servis tarafından soğuk başlatılınca çöküyordu ve
  menü çubuğunda yaşayamıyordu; bu yüzden yerel macOS hedefine geçildi. Mac'te Paylaş menüsü
  eklentisi yok, onun yerini ⇧⌘E / sağ tık › Servisler alıyor.
- MenuBarExtra penceresinden başka pencere açınca `NSApp.activate()` gerekir (Dock'ta görünmeyen
  uygulamanın penceresi yoksa arkada kalır); menü penceresi `dismiss()` ile kapanır.
- Üçüncü parti servis kısayolu, önündeki uygulamanın menüsü aynı tuşu kullanıyorsa çalışmaz
  (⇧⌘K Önizleme'de çakışıyordu → ⇧⌘E). Sistem bu kısayolları varsayılan olarak her zaman açmaz.
- Translation framework simülatörde çalışmaz; gerçek cihazda test et.
- Simülatöre otomatik yazı yazarken Türkçe klavye düzeni harfleri bozar; bu uygulama hatası değil.
- Mac'te `~/Library/Group Containers/group.com.burakalemdar.KelimeDefteri` TCC korumalı, dışarıdan okunamaz.
- `URL.path()` yüzde kodlu döner; dosya sistemi için `path(percentEncoded: false)`.
- CloudKit şeması geliştirme ortamında; TestFlight/App Store öncesi üretime aktarılmalı.

## Çalışma şekli

- Kullanıcı "sen yaz, ben kullanayım" diyor: özelliği yaz, test et, cihazlara kur, sonucu sade Türkçe anlat.
- Apple Developer hesabında değişiklik (cihaz/App Group/iCloud kaydı vb.) ve commit/push öncesi onay al.
- Mac'te görsel test için ekranı devralmak serbest (kullanıcı izin verdi); Önizleme'yi zorla kapatma.
  Menü çubuğu simgesi ekran kaydında görünür; tıklayınca pencere açılır.
