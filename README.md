# Kelime Defteri

Teknik kitap okurken karşılaşılan İngilizce kelimeleri kaydedip aralıklı tekrarla
(FSRS unutma eğrisine dayanan hafıza modeli) ve kısa oyunlarla öğrenmek için iPhone, iPad ve Mac uygulaması. SwiftUI + SwiftData + CloudKit,
iOS 26+ / macOS 26+ (Mac'te menü çubuğu uygulaması).

## Özellikler

- **Kelime ekle:** İngilizce kelime, Türkçe karşılıkları (virgülle ayrılmış), isteğe bağlı
  kitaptaki cümleler (her biri bir anlama bağlanabilir; sorularda sorulan anlamın cümlesi ipucu olur,
  bkz. `docs/SPEC-CUMLE.md`).
  - *Türkçesini bul:* Apple'ın cihaz üstü çeviri motoruyla (Translation framework) öneri.
  - *Sözlük:* iOS'un yerleşik sözlüğünde İngilizce tanıma bakma.
- **Çalış (oyun merkezi):** Üstte **Günlük Tekrar** (zayıflayan kelimeler, en fazla 20, en fazla 5 yeni),
  altında oyunlar: **Hızlı Tur** (5 karışık soru), **Çoktan Seçmeli**, **Eşleştir**, **Boşluğu Doldur**
  (kitaptaki cümle), **Harfleri Diz**, **Ters Yön** (Türkçeden İngilizceye). Her tur sonunda özet:
  kaç doğru, ne kadar sürdü, her kelimenin hafızası nasıl değişti.
- **Hafıza:** Her kelimenin hatırlama ihtimali (%) zamanla azalır; %90'ın altına inen kelime tekrara gelir.
  Not kullanıcıya sorulmaz, cevaptan çıkarılır (hız, cevaba bakma, yazım hatası). Seçeneklerden tanımak
  kendin hatırlamaktan daha az sayılır. Sıra karışıktır, zayıf kelime öne gelme eğilimindedir.
- **Kelimelerim:** Tümü / Zayıf / Güçlü / Yeni süzgeci; Eklenme / A–Z / Hafıza / En Zor sıralaması.
  Ayrıntı sayfasında hafıza halkası, görülme, doğru bilme, son görülme, ortalama cevap süresi ve
  son 30 cevabın geçmişi.
- **İlerleme:** Ayarlar › İlerleme'de hafıza dağılımı (Yeni / %0–50 … %95+) ve ortalama hafıza.
- **Hoşgörülü kontrol:** Büyük/küçük harf, Türkçe karakter (ş/s, ı/i…) ve noktalama fark etmez.
- **Paylaş menüsünden ekleme:** Books, Safari ya da PDF okuyucuda metni seç › Paylaş › Kelime Defteri.
  Cümle paylaşıldıysa kelimeleri düğme olarak gelir, bilinmeyene dokunulur; Apple Books'un eklediği
  alıntı satırı cümleye girmez. Aynı form Paylaş sayfasının alt listesindeki "Kelime Defteri’ne Ekle"
  eyleminden de açılır (uygulama satırında görünmediğinde "Daha Fazla"ya gerek kalmaz).
- **Panodaki kelimeyi ekleme:** "Panodaki Kelimeyi Ekle" kısayolu (Kısayollar, Arkaya Vurma, Eylem düğmesi)
  uygulamayı açıp Ekle sekmesini kopyalanan metinle doldurur.
- **iCloud eşitleme:** Kelimeler iCloud'da yedeklenir; iPhone ve Mac'te aynı defter.
- **Mac: menü çubuğu uygulaması.** Dock'ta görünmez; menü çubuğundaki kitap simgesi zayıf kelime
  sayısını gösterir. Tıklayınca Çalış / Ekle penceresi açılır (klavyeyle: Return kontrol, ← Bilemedim,
  → Bildim). Kelimelerim penceresinde sıralanabilir tablo, arama, çift tıkla düzenleme, ⌫ ile silme.
  Ayarlar'da oturum açılınca başlatma ve hatırlatma.
- **Mac kısayolu ⇧⌘E:** Önizleme'de (veya herhangi bir uygulamada) metni seç, ⇧⌘E'ye bas ya da
  sağ tık › Servisler › Kelime Defteri'ne Ekle. Uygulama kapalıysa kendisi açılır; kelime ayrı bir
  pencerede eklenir ve saniyeler içinde telefona gelir.
- **Günlük hatırlatma:** Seçilen saatte zayıflayan kelime varsa bildirim; ikonda zayıf kelime sayısı.
  Bildirimde bir kelime sorulur; basılı tutunca 4 Türkçe seçenek çıkar, cevap uygulama açılmadan yazılır.
- **Widget'lar (iPhone):** Ana ekranda (ve StandBy'da) soru widget'ı: kelime ve 4 seçenek, dokununca
  cevap hafızaya yazılır, doğru/yanlış görünür, sıradaki soru gelir. Kilit ekranında "Hafıza %78 · 6 kelime
  zayıfladı" özeti; dokununca Hızlı Tur. Denetim Merkezi / Eylem düğmesi için "Hızlı Tur" düğmesi.

## Proje yapısı

```
KelimeDefteri/        iPhone/iPad uygulaması
  App/                Giriş noktası
  Views/              SwiftUI ekranları (StudyView = oyun merkezi)
    Games/            Oyun ekranları ve ortak soru parçaları, tur özeti
Mac/                  Yerel macOS menü çubuğu uygulaması: MenuBarExtra, Kelimelerim tablosu,
                      Ayarlar, ⇧⌘E servisi (AppDelegate)
Shared/               iOS, Mac ve paylaşım eklentisinde ortak: Word modeli, SharedStore
                      (App Group veritabanı), ReviewLog, AnswerChecker, SharedTextParser, WordFormView
  Logic/              Hafıza motoru (Memory), ReviewRecorder, WordPicker, StudySession, GameRound,
                      oyun mantıkları (ChoiceQuiz, MatchBoard, ClozeSentence, LetterPuzzle, ReverseChecker,
                      QuickMix), hatırlatma, Speaker
KelimeEkle/           iOS Paylaş menüsü eklentisi (Share Extension, uygulama satırı)
KelimeEylem/          iOS eylem eklentisi (Action Extension, alt liste); form Shared/AddWordExtensionController
KelimeWidget/         iOS widget eklentisi: soru widget'ı, kilit ekranı özeti, Hızlı Tur denetimi
Config/               Entitlements ve Info.plist'ler (KelimeDefteriMac-* Mac uygulaması için)
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

**Mac'te:** Xcode'da **KelimeDefteriMac** şemasını ve **My Mac**'i seçip ⌘R. iCloud şeması şu an geliştirme
ortamında; TestFlight/App Store'a çıkmadan önce CloudKit Console'dan üretime aktarılmalı.

Testler: Xcode'da **⌘U**, ya da

```bash
xcodebuild test -project KelimeDefteri.xcodeproj -scheme KelimeDefteri -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Yol haritası

- [x] iCloud eşitleme (SwiftData + CloudKit), iPad/Mac'te de aynı defter
- [x] Mac'te menü çubuğu uygulaması
- [x] Günlük tekrar hatırlatma bildirimi
- [x] Paylaş menüsünden kelime ekleme
- [ ] Oyunlaştırma: hafıza gücü, kelime başına kayıt, Hızlı Tur / Eşleştir / Boşluğu Doldur ve diğer
      oyunlar, karışık sıra, etkileşimli widget. Ayrıntılı plan: [docs/GELECEK.md](docs/GELECEK.md)
- [ ] Kendi backend'in: kelime listesini yedekleme / web'den ekleme (REST API)
