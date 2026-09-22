# Kelime Defteri

Teknik kitap okurken karşılaşılan İngilizce kelimeleri kaydedip aralıklı tekrarla
(Leitner sistemi) öğrenmek için iPhone, iPad ve Mac uygulaması. SwiftUI + SwiftData + CloudKit,
iOS 18+ / Mac Catalyst (macOS 26+).

## Özellikler

- **Kelime ekle:** İngilizce kelime, Türkçe karşılıkları (virgülle ayrılmış), isteğe bağlı
  İngilizce tanım, kitaptaki cümle ve kaynak kitap.
  - *Türkçesini bul:* Apple'ın cihaz üstü çeviri motoruyla (Translation framework) öneri.
  - *Sözlük:* iOS'un yerleşik sözlüğünde İngilizce tanıma bakma.
- **Çalış:** İngilizce kelime ve cümle gösterilir; Türkçesini yazıp kontrol ettirirsin ya da
  karta dokunup Türkçesini görürsün. Telaffuzu dinleyebilirsin.
- **Aralıklı tekrar:** Bilinen kelime üst kutuya çıkar ve 1 / 3 / 7 / 16 / 35 gün sonra tekrar
  sorulur; bilinmeyen başa döner ve aynı turda bir daha sorulur.
- **Hoşgörülü kontrol:** Büyük/küçük harf, Türkçe karakter (ş/s, ı/i…) ve noktalama fark etmez.
- **Paylaş menüsünden ekleme:** Books, Safari ya da PDF okuyucuda metni seç › Paylaş › Kelime Defteri.
  Cümle paylaşıldıysa kelimeleri düğme olarak gelir, bilinmeyene dokunulur; Apple Books'ta kitap adı
  kaynak olarak otomatik dolar.
- **iCloud eşitleme:** Kelimeler iCloud'da yedeklenir; iPhone ve Mac'te aynı defter.
  Mac'te Önizleme'den (PDF) seç › sağ tık › Paylaş › Kelime Defteri; kelime saniyeler içinde telefona gelir
  (Mac uygulaması açıkken — eşitlemeyi eklenti değil ana uygulama yapar).
- **Günlük hatırlatma:** Seçilen saatte sırada kelime varsa bildirim; ikonda sıradaki kelime sayısı.

## Proje yapısı

```
KelimeDefteri/        Uygulama
  App/                Giriş noktası
  Logic/              StudySession, hatırlatma planlama/zamanlama, Speaker
  Views/              SwiftUI ekranları
Shared/               Uygulama + paylaşım eklentisinde ortak: Word modeli, SharedStore
                      (App Group veritabanı), Leitner, AnswerChecker, SharedTextParser, WordFormView
KelimeEkle/           Paylaş menüsü eklentisi (Share Extension)
Config/               Entitlements (App Group, iCloud; -mac dosyaları Mac Catalyst için)
KelimeDefteriTests/   Swift Testing birim testleri
```

İş mantığı arayüzden ayrı ve birim testli; ekranlar sadece onu çağırır. Veritabanı App Group
klasöründe durur, böylece paylaşım eklentisinin eklediği kelimeyi uygulama da görür.

## Telefonda çalıştırma

1. `KelimeDefteri.xcodeproj` dosyasını Xcode'da aç.
2. Sol üstte **KelimeDefteri** projesine → **KelimeDefteri** target'ına → **Signing & Capabilities**
   sekmesine gel, **Team** olarak Apple Developer hesabını seç.
   Bundle ID çakışırsa `com.burakalemdar.KelimeDefteri` değerini değiştir.
3. iPhone'u kabloyla (ya da aynı Wi-Fi'da) bağla, üstteki cihaz listesinden seç.
4. İlk seferde iPhone'da **Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu**'nu aç.
5. **⌘R** ile çalıştır.

**Mac'te:** Xcode'da cihaz olarak **My Mac (Mac Catalyst)** seçip ⌘R. iCloud şeması şu an geliştirme
ortamında; TestFlight/App Store'a çıkmadan önce CloudKit Console'dan üretime aktarılmalı.

Testler: Xcode'da **⌘U**, ya da

```bash
xcodebuild test -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Yol haritası

- [x] iCloud eşitleme (SwiftData + CloudKit), iPad/Mac'te de aynı defter
- [x] Günlük tekrar hatırlatma bildirimi
- [x] Paylaş menüsünden kelime ekleme
- [ ] Ters yön: Türkçeden İngilizceye çalışma
- [ ] Ana ekran widget'ı: "Bugün 12 kelime sırada"
- [ ] Kendi backend'in: kelime listesini yedekleme / web'den ekleme (REST API)
