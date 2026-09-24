# Gelecek: Kelime Defteri'ni oyuna çevirmek

*Not alındı: 23 Eylül 2026. Burak'ın istekleri ve Claude'un önerileri.*

## İstenen

- iPhone uygulaması, telefona her bakışta yapılacak bir şey olsun: eğitici bir bulmaca, bir oyun.
- Günün içinde hem buna özel zaman ayrılabilsin hem de kısa kısa tekrar tekrar açılabilsin.
- Her kelimenin kaç kez görüldüğü ve nasıl bilindiği kaydedilsin.
- Her oynayışta kelimeler aynı sırayla gelmesin.
- iCloud eşitlemesi ve kayıt mantığı olduğu gibi kalsın; bu kısım beğenildi.

## Bugünkü sistemin sorunları

Aralıklı tekrarın arkasındaki bilim doğru: bir kelimeyi unutmaya başladığın anda görmek, onu
en kalıcı şekilde öğretir. Sorun, bu fikrin uygulamada nasıl kurulduğu:

1. **"Kutu 2/5" anlamsız bir sayı.** Kullanıcıya hiçbir şey anlatmıyor.
2. **Gün içinde tekrar oynanamıyor.** Sıradaki kelimeler bitince uygulama "Bugünlük bu kadar"
   diyor. "Hepsini Çalış" ise tekrarları hiç ayırt etmeden sayıyor. İstenen kullanımla doğrudan çelişiyor.
3. **Sıra hep aynı.** Günlük turda kelimeler tarihe göre dizildiği için aynı sırayla geliyor. Bu bir hata.
4. **Tek yanlış her şeyi sıfırlıyor.** 35 günlük kutudaki kelime bir hatayla 0. kutuya düşüyor.
5. **Sabit aralıklar.** Kolay ve zor kelime aynı takvimle soruluyor.
6. **Tek oyun türü.** Yalnızca "Türkçesini yaz" var; birkaç günde sıkıcı hale geliyor.

## Önerilen yapı: iki katman

### 1. Hafıza motoru (görünmez)

- Kutuların yerini her kelime için bir **hafıza gücü** alıyor: şu an hatırlama ihtimali
  (%0–100). Zamanla azalıyor, her doğru cevapla artıyor.
  - Modern bir aralıklı tekrar algoritmasının (FSRS) sade bir hali.
  - Kelimenin zorluğunu da öğreniyor: zor kelime daha sık, kolay kelime daha seyrek geliyor.
- Her gösterim kaydediliyor. Her oyunda ve her cevapta "ne zaman, hangi oyunda, doğru mu,
  kaç saniyede" bilgisi `ReviewLog` kaydına yazılıyor. İstenen "kaç kez gördüm" bilgisi buradan geliyor.
- **Gün içindeki tekrarlar da sayılıyor, ama ağırlıkları farklı.** Aynı gün arka arkaya görmek
  hafızayı biraz güçlendiriyor. Asıl kazanç, kelimeyi unutmaya yakınken hatırlamaktan geliyor.
  Böylece gün içinde dilediğin kadar oynayabiliyorsun ve bu öğrenmeyi bozmuyor.
- Yanlış cevap hafızayı düşürüyor ama sıfırlamıyor.

### 2. Oyun katmanı (görünen)

Kısa turlar, her biri 1–3 dakika. Her tur hafıza motorundan beslenip ona geri yazıyor.

| Oyun | Nasıl | Ne zaman |
|---|---|---|
| **Günlük Tekrar** | Hatırlama ihtimali düşmüş kelimeler, karışık sırayla. Bugünkü Çalış'ın gelişmiş hali. | Zaman ayırdığın oturum |
| **Hızlı Tur** | 5 kelime, yaklaşık 1 dakika. En zayıf kelimelerden ağırlıklı rastgele seçim. | Telefona her bakışta |
| **Eşleştir** | 5 İngilizce ve 5 Türkçe kart; doğru çiftleri eşleştir. Süre ve hata sayılır. | Bulmaca keyfi |
| **Boşluğu Doldur** | Kitaptaki cümle, kelimenin yeri boş; seçenekler arasından seç. Bu uygulamaya özgü, çünkü cümleler senin okuduğun kitaplardan. | Bağlam içinde öğrenme |
| **Harfleri Diz** | Türkçesi verilir, karışık harflerden İngilizcesini kur. | Yazımı öğrenme |
| **Çoktan Seçmeli** | 4 Türkçe seçenek, tek dokunuş. | Tek elle, yolda |
| **Ters Yön** | Türkçesi sorulur, İngilizcesini yaz. | Kelimeyi kullanabilmek |

**Sıra kuralları** (bütün oyunlar için):
- Kelimeler ağırlıklı karışık gelir; zayıf kelimelerin çıkma ihtimali daha yüksektir.
- Aynı kelime art arda gelmez.
- Bir önceki turun ilk kelimesi, yeni turun başında gelmez.
- Yeni ve eski kelimeler iç içe gelir.

## Telefona her bakışta: iPhone'un kendi yerleri

- **Etkileşimli ana ekran widget'ı:** Uygulamayı açmadan widget'ın üstünde bir soru çıkar,
  4 seçenekten birine dokunursun. Sonuç hafıza motoruna yazılır ve widget sıradaki soruya geçer.
- **Kilit ekranı widget'ı:** "Hafıza %78 · 6 kelime zayıfladı" gibi bir özet. Dokununca Hızlı Tur açılır.
- **Cevaplanabilir bildirim:** Hatırlatma bildirimini basılı tutunca seçenekler çıkar;
  bildirimden cevap verilir.
- **Denetim Merkezi / Eylem düğmesi:** Tek basışla Hızlı Tur.
- **StandBy:** Telefon şarjdayken yatay ekranda kelime kartları döner.

## Motivasyon (Fitness uygulaması tarzı, sade)

- **Günlük hedef halkası:** Ör. "Bugün 30 cevap". Halka dolar, gün sonunda kapanır.
- **Seri:** Kaç gündür halkayı kapattığın.
- **Kelime ustalığı:** Hafıza gücü belli bir eşiği uzun süre koruyan kelime "Öğrenildi" rozeti alır.
- **Haftalık özet:** Kaç kelime güçlendi, en çok zorlandığın 5 kelime.

## Kelime başına kayıt ve istatistik

Ayrıntı sayfası şunları göstermeli:
- Hafıza gücü göstergesi ve "bu hafta şuraya düşecek" tahmini
- Kaç kez görüldü, kaç kez doğru, hangi oyunlarda
- Son görülme zamanı ve ortalama cevap süresi
- Küçük bir zaman çizelgesi: her gösterim bir nokta (yeşil doğru, kırmızı yanlış)

Kelimelerim listesine "En zor kelimeler" sıralaması eklenmeli.

## Teknik notlar

- iCloud (CloudKit) şeması yalnızca **ekleyerek** değişmeli: `Word`'e yeni alanlar
  (varsayılan değerli) ve yeni bir `ReviewLog` modeli. Var olan kelimeler kaybolmaz.
- Mevcut kutu ve tarih bilgisinden başlangıç hafıza gücü hesaplanabilir; geçiş kayıpsız olur.
- Widget ve bildirim cevapları için ortak App Group deposu zaten var (Paylaş eklentisi de onu kullanıyor).
- CloudKit şemasının üretime aktarılması bu iş sırasında yapılmalı (bkz. CLAUDE.md).
- Mac: Aynı oyunlar menü çubuğu penceresine uyarlanır, klavyeyle oynanır. Eşleştir Mac'te sürükle-bırakla oynanabilir.

## Önerilen sıra

1. **Hızlı düzeltmeler:** Karışık sıra (bugünkü hata). Kelime başına görülme sayısının
   ayrıntı sayfasında gösterilmesi. "Kutu" yazısının kalkması.
2. **Hafıza motoru ve kayıtlar:** `ReviewLog` ve hafıza gücü. Kutular görünmez olur.
   "Bugünlük bu kadar" yerine her zaman oynanabilir bir tur gelir.
3. **Oyunlar:** Hızlı Tur ve Çoktan Seçmeli (en kolay), ardından Eşleştir ve Boşluğu Doldur,
   en son Harfleri Diz ve Ters Yön.
4. **Telefona yayılma:** Etkileşimli widget, kilit ekranı, cevaplanabilir bildirim.
5. **Motivasyon:** Günlük halka, seri, haftalık özet.
6. **Mac uyarlaması.**

Her adım kendi başına kullanılabilir. 1. adım birkaç saatlik iş; 2. adım işin temeli.

---

## Uygulama planı (1–3. adımlar)

Ayrıntılı spec, görev listesi ve `/loop` çalışma kuralları: [SPEC-OYUN.md](SPEC-OYUN.md).
İlerleme: [CALISMA-RAPORU.md](CALISMA-RAPORU.md).

## İleride: tekrar modları (not alındı 23 Eylül 2026)

Durum: 1–6. adımlar tamamlandı. "Yeni Eklenenler" modu eklendi; aşağıdakiler kullanıcı isteğiyle sonraya kaldı.

- **Kitaba göre tekrar:** Belirli bir kitaptan eklenen kelimeleri çalışmak (ör. kitaba geri dönmeden önce).
  Engel: "Kaynak kitap" alanı kaldırıldı (bkz. CALISMA-RAPORU "Kaynak kitap kaldırıldı"); `Word.source` modelde duruyor
  ama boş. Yapılacaksa önce kitabın zahmetsiz kaydedilmesi çözülmeli (ör. Paylaş'ta gelen Apple Books alıntısındaki
  "Alıntı Kaynağı" satırından kitap adını otomatik almak), elle yazdırmak yok. Tekrar hafızaya yazmamalı ya da yalnızca
  vadesi gelenleri öne almalı (erken tekrar takvimi bozar).
- **Kendini Sına:** Defterden rastgele ~20 kelime, ipucu yok, sonunda "%78'ini biliyorsun"; zaman içindeki oran "Bu
  Hafta"da. Hafızaya yazmaz, yalnızca ölçer (WaniKani Extra Study / Bunpro Cram gibi SRS'e dokunmayan modlar).
  Değerlendirme: oyunlar zaten hatırlama alıştırması; asıl katkısı ilerlemeyi görmek.
- Elenenler ve gerekçe: "Zorlandıkların" ("Yine de Çalış" bunu yapıyor), "Yakında unutulacaklar / erken tekrar"
  (takvimi bozar), "Sınav öncesi yoğun tekrar" (yığarak çalışma kalıcı değil).

## İleride: motivasyon (not alındı 23 Eylül 2026)

"Bu Hafta"ya "Öğrendiğin: N kelime (bu hafta +M)" satırı eklendi (`Word.learnedAt`). Sonraya kalanlar:

- **Öğrenilen kelime grafiği:** Ayarlar › İlerleme sayfasına öğrenilen kelime sayısının zamanla artışını gösteren çizgi
  grafik (Swift Charts, `learnedAt`'ten). `learnedAt` birkaç hafta veri topladıktan sonra anlamlı olur; önce düz görünür.
- **Seri esnekliği:** Bir gün kaçırmak seriyi bozmasın (Duolingo "streak freeze" benzeri). Seri kırılınca bırakma riski
  var; esneklik kaygıyı azaltıyor. Sade bir kural düşün (ör. haftada 1 kaçırılan gün seriyi koparmaz), ek düğme/envanter yok.
- Elenenler: GitHub tarzı etkinlik ızgarası (halka/seri/Bu Hafta ile aynı veri, Apple diline yabancı), "bugün X kelime",
  "toplam X kez" (zaten var / gösteriş sayısı), doğruluk trendi (motor %90'da tuttuğu için düz çizgi).

## İleride: App Store / TestFlight öncesi (not alındı 24 Eylül 2026)

Yayına çıkmadan önce yapılacaklar. Sıra önerisi: iPad → üç cihaz uyumu → mağaza görselleri → tanıtım videosu.

### iPad sürümü
- Bugün: uygulama hedefi iPad'i zaten destekliyor (`TARGETED_DEVICE_FAMILY = "1,2"`), ama arayüz iPhone düzeninin
  büyütülmüş hâli; `NavigationSplitView` / `horizontalSizeClass` kullanan ekran yok.
- Yapılacak: geniş ekranda kenar çubuklu düzen (Kelimelerim listesi + ayrıntı yan yana, Çalış/oyunlar ortada makul
  genişlikte), Split View / Stage Manager'da küçük pencerede iPhone düzenine dönme, klavye kısayolları (Mac'teki
  ↩/Esc gibi) ve donanım klavyesiyle cevap yazma, Apple Pencil ile el yazısı cevap (Scribble zaten metin alanlarında çalışır).
- Widget'ların iPad boyutları (büyük / çok büyük) ve kilit ekranı.
- Paylaş/eylem eklentileri iPad'de (şu an eklenti hedeflerinden ikisi yalnızca iPhone: `TARGETED_DEVICE_FAMILY = 1`) — kontrol et.

### iPhone + iPad + Mac uyumu
- Üçü aynı iCloud deposunu kullanır; Motor 2 hafızayı cevap kayıtlarından hesapladığı için cihazlar aynı sonuca varır.
  Gerçek üç cihazla dene: aynı gün farklı cihazlarda cevap, çevrimdışı cevap sonra eşitleme, aynı kelimeyi iki cihazda ekleme.
- Ayarların (günlük hedef, bildirim saati, seri) hangi cihazda tutulduğu netleşmeli: Mac'te günlük hedef ayrı
  (`DailyGoal.defaults`); iPad'de App Group mı, iCloud anahtar-değer deposu (`NSUbiquitousKeyValueStore`) mı? Seri ve
  hedefin üç cihazda aynı görünmesi tercih edilir.
- Evrensel satın alma (tek uygulama kaydı, iOS + macOS aynı paket kimliği `com.burakalemdar.KelimeDefteri` zaten).

### Yayın hazırlığı
- CloudKit şemasını üretime aktar (ayrı onay; CLAUDE.md'de not var).
- Gizlilik: App Store gizlilik etiketi ("veri toplanmaz", yalnızca kullanıcının kendi iCloud'u), gizlilik politikası sayfası.
- Uygulama adı, alt başlık, anahtar kelimeler, açıklama (Türkçe + İngilizce), destek bağlantısı, yaş derecesi.
- TestFlight: önce kendi cihazlar, sonra birkaç kişilik dış test grubu.

### Mağaza görselleri (ekran görüntüleri ve "thumbnail"lar)
- Gereken boyutlar: iPhone 6,9" (ör. 1320×2868), iPad 13" (2064×2752), Mac (2880×1800 ya da 1440×900); en az 3, en fazla 10 adet.
- Ham görüntüler `-demo` argümanıyla örnek veriden alınır (CLAUDE.md), gerçek defter görünmez. Açık ve koyu tema.
- Önerilen sahneler: Paylaş menüsünden kelime ekleme, Günlük Tekrar kartı, bir oyun (Eşleştir / Boşluğu Doldur),
  tur özeti ("Yeni → Yarın"), widget + kilit ekranı, Kelimelerim, Mac menü çubuğu penceresi.
- Her görselin üstüne kısa başlık ("Kitapta gördüğün kelimeyi tek dokunuşla kaydet" gibi) ve cihaz çerçevesi; tek tip
  yazı ve renk. Araç: kendi betiğimizle simülatör görüntüsü + çerçeve (fastlane `frameit` ya da benzeri).
- Uygulama simgesi hazır (Icon Composer, `AppIcon.icon`).

### Tanıtım videosu (App Preview)
- App Store'da cihaz başına en fazla 3 video, 15–30 sn, cihazın kendi çözünürlüğünde; ekran kaydı esaslı olmalı
  (Apple kuralı: uygulamanın gerçek kullanımını göstermeli).
- Plan: simülatör/cihaz ekran kaydı (`xcrun simctl io booted recordVideo`) ile kurgu: kitapta kelimeyi seç → Paylaş →
  kaydet → ertesi gün widget'ta soru → Günlük Tekrar → tur özeti.
- Yapay zekâ ile: uygulamayı kullanan kişinin göründüğü sahneler (ör. kitap okurken telefonda kelime kaydetme) yapay
  zekâ video araçlarıyla üretilebilir; App Store önizlemesinde değil, web sitesi / sosyal medya tanıtımında kullanılmalı
  (mağaza önizlemesi gerçek ekran kaydı istiyor). Seslendirme/altyazı Türkçe + İngilizce.
