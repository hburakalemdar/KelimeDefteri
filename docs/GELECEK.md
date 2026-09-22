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

## Gece planı (1–3. adımlar)

`/loop` her turda aşağıdaki listeden **işaretlenmemiş ilk görevi** alır, bitirir, işaretler.
Görevler sırayla yapılır; her biri kendi başına derlenir, test edilir ve commit edilir.

- [ ] **A1 · Karışık sıra.** Günlük turda kelimeler ağırlıklı karışık gelsin (zamanı daha çok geçmiş olan
      öne çıkma ihtimali yüksek ama sabit değil). Aynı kelime art arda gelmesin. Yeni turun ilk kelimesi,
      bir önceki turun ilk kelimesiyle aynı olmasın. `StudySession` testleri güncellensin.
- [ ] **B1 · Kayıt modeli.** `ReviewLog` modeli (kelime, tarih, oyun türü, doğru mu, cevap süresi) ve
      `Word`'e hafıza alanları (ör. stability, difficulty, lastReviewedAt). Hepsi varsayılan değerli ve
      isteğe bağlı ilişkili (CloudKit kuralı). Var olan `box`/`dueDate`'ten başlangıç değerleri hesaplansın.
      `PreviewData` yeni alanlarla güncellensin.
- [ ] **B2 · Hafıza motoru.** FSRS'nin sade bir hali: hatırlama ihtimali (%0–100), cevaba göre güncelleme,
      sıradaki tekrar zamanı. Yanlış cevap sıfırlamaz. Aynı gün içindeki tekrar daha az ağırlık taşır.
      Saf mantık (`Shared/Logic/`), kapsamlı birim testli.
- [ ] **B3 · Motoru bağla.** `StudySession` hafıza motorunu kullansın; her cevap bir `ReviewLog` yazsın.
      "Bugünlük bu kadar" ekranı yerine her zaman oynanabilir tur (en zayıf kelimeler). "Kutu" dili
      her yerden kalksın; yerine hafıza gücü gösterilsin (kart, Kelimelerim, ayrıntı, İlerleme grafiği,
      Mac çalışma kartı ve tablosu). Hatırlatma bildirimi ve rozet sayısı yeni mantığa uysun.
- [ ] **B4 · Kelime istatistiği.** Ayrıntı sayfasında: kaç kez görüldü, doğru oranı, son görülme,
      ortalama cevap süresi, her gösterim bir nokta olan küçük zaman çizelgesi. Kelimelerim'e
      "En zor kelimeler" sıralaması.
- [ ] **C1 · Oyun merkezi.** Çalış sekmesi oyun seçme ekranına dönüşsün: üstte Günlük Tekrar (asıl oturum,
      kaç kelimenin zayıfladığıyla), altında oyun kartları. İlk oyun **Hızlı Tur**: 5 kelime, zayıflardan
      ağırlıklı rastgele seçim, sonunda kısa özet.
- [ ] **C2 · Çoktan Seçmeli.** 4 Türkçe seçenek; yanlış seçenekler defterdeki diğer kelimelerden gelir.
- [ ] **C3 · Eşleştir.** 5 İngilizce, 5 Türkçe kart; eşleştirme; süre ve hata sayısı.
- [ ] **C4 · Boşluğu Doldur.** Kitaptaki cümlede kelimenin yeri boş; 4 seçenek. Cümlesi olmayan kelime bu oyuna girmez.
- [ ] **C5 · Harfleri Diz.** Türkçesi verilir, karışık harf düğmelerinden İngilizcesi kurulur.
- [ ] **C6 · Ters Yön.** Türkçesi sorulur, İngilizcesi yazılır (hoşgörülü kontrol).
- [ ] **Z · Sabah raporu.** `docs/GECE-RAPORU.md`: ne yapıldı, ekran görüntülerinde ne görüldü,
      nerede takılındı, sabah iPhone'a kurmadan önce bilinmesi gerekenler (veri dönüşümü).

### Gece çalışma kuralları

- Her turun başında `CLAUDE.md`'yi ve bu dosyayı oku. Kullanıcı yokken çalışıyorsun; soru sorma,
  karar gerekiyorsa en sade ve Apple'a en yakın seçeneği seç ve sabah raporuna yaz.
- Tasarım: tamamen iOS'a özgü (Liquid Glass, sistem parçaları, SF Symbols, sistem mavisi).
  Gereksiz seçenek ekleme; sonucu belli şeyi kullanıcıya tekrar sorma. Her düğmenin ayrı bir işi olsun.
- Her görevde: derle, testleri `-parallel-testing-enabled NO` ile koş, simülatörde `-demo` ile ilgili
  ekranları aç, ekran görüntüsünü alıp kendin bak, hatayı düzelt. Mac hedefi her görevde derlenmeli ve
  menü çubuğu penceresi bozulmamalı.
- Görev bitince: listede işaretle, `main`'e commit et (sonuna Co-Authored-By satırı) ve GitHub'a push et.
- **iPhone'a ve /Applications'a kurma.** Kullanıcının gerçek verisi var; sabah kendisi kuracak.
- Apple Developer hesabında değişiklik yok (yeni hedef, kimlik, App Group yok). Widget ve bildirim işleri sonraya.
- CloudKit şeması yalnızca ekleyerek değişir; alan silme ya da yeniden adlandırma yok.
- Bir görevde takılırsan: yapabildiğin kadarını çalışır halde bırak, sorunu sabah raporuna yaz,
  görevi `[~]` ile işaretle ve sıradakine geç.
- Tur sonunda simülatörü kapat (`xcrun simctl shutdown all`). Tüm görevler bitince döngüyü durdur.
