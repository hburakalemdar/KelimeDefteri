# Spec: Oyunlaştırma (1–3. adımlar)

Bu dosya `/loop` ile yürütülecek işin tek kaynağıdır. Neden yapıldığı `docs/GELECEK.md`'de.

**Ne kadar bağlayıcı:** Davranış ve mantık (veri modeli, hafıza formülleri, not verme, sıra kuralları,
oyun kuralları) spec'teki gibi uygulanır. Görsel ayrıntılar (ölçüler, köşe yarıçapları, yerleşim,
süreler) başlangıç önerisidir: ekranda daha iyi görünen bir çözüm varsa uygula ve nedenini
`docs/CALISMA-RAPORU.md`'ye yaz. Ama **uygulamanın mevcut tasarım desenine bağlı kal** (§4):
yeni ekranlar bugünkü ekranların devamı gibi görünmeli, ayrı bir uygulama gibi değil.

**Karar verme:** Kullanıcıya soru sorma. Her kararı kendin ver: en sade, Apple uygulamalarına ve
mevcut desene en yakın seçeneği seç, `docs/CALISMA-RAPORU.md`'ye "Verilen kararlar" altında gerekçesiyle yaz.

**Kullanıcının verdiği kararlar (23 Eylül 2026):**
- Çalış sekmesi: üstte Günlük Tekrar kartı, altında 2 sütunlu oyun kartları.
- Hafıza gücü: yüzde ve halka ("%62"), renkli.
- B3'e kadar yalnızca simülatör. B3 bittikten sonra her görevin sonunda iPhone'a ve Mac'e kurulur
  (kullanıcının gerçek defterinde az sayıda deneme kelimesi var).
- Mac derlenir ve yeni dili gösterir (hafıza gücü, karışık sıra); oyunlar Mac'e sonra gelecek.
- Her görev `main`'e commit edilip push edilir.

---

## 1. Veri modeli (B1)

`Word`'e eklenen alanlar. Hepsi varsayılan değerli; CloudKit yalnızca ekleme kabul eder.

| Alan | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `stability` | `Double` | `0` | Gün cinsinden hafıza dayanıklılığı. `0` = hiç çalışılmamış (yeni). |
| `difficulty` | `Double` | `5` | 1 (kolay) … 10 (zor). |
| `lastReviewedAt` | `Date?` | `nil` | Son cevap zamanı. |
| `logs` | `[ReviewLog]?` | `nil` | `@Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)` |

Yeni model `ReviewLog` (`Shared/ReviewLog.swift`):

| Alan | Tür | Varsayılan |
|---|---|---|
| `date` | `Date` | `.now` |
| `mode` | `String` | `""` (`GameMode.rawValue`) |
| `correct` | `Bool` | `false` |
| `grade` | `Int` | `0` (`AnswerGrade.rawValue`) |
| `responseTime` | `Double` | `0` (saniye) |
| `word` | `Word?` | `nil` |

- `ModelContainer` şemasına `ReviewLog` eklenir: `SharedStore`, `PreviewData`, testlerdeki geçici depolar.
- `box` ve `dueDate` alanları **silinmez**. `box` artık yazılmaz. `dueDate` her cevapta motorun
  hesapladığı sıradaki tekrar zamanıyla güncellenir; hatırlatma bildirimi ve sıralama onu kullanmaya devam eder.
- `reviewCount` ve `correctCount` artmaya devam eder.

**Tek seferlik geçiş** (`MemoryMigration.migrateIfNeeded(context:)`, uygulama açılışında; Mac'te de):
- Koşul: `stability == 0 && reviewCount > 0`.
- `stability = max(Leitner.intervalsInDays[box], 0.5)`
- `lastReviewedAt = dueDate > .distantPast ? dueDate − stability gün : nil`
- `difficulty = clamp(5 + (0.5 − correctCount/reviewCount) × 6, 1…10)`
- Birim testli. İkinci kez çalışınca hiçbir şeyi değiştirmemeli.

## 2. Hafıza motoru (B2)

> **Not (24 Eylül 2026):** Bu bölümün yerine `docs/SPEC-MOTOR2.md` geçer (loglardan yeniden oynatılan motor).

`Shared/Logic/Memory.swift`, saf fonksiyonlar, `nonisolated`.

**Hatırlama ihtimali** (FSRS-4.5 unutma eğrisi):

    R(t, S) = (1 + 19/81 · t / S) ^ (−0.5)      t: son cevaptan beri geçen gün

- `t = S` iken `R = 0.9`.
- `S == 0` (yeni kelime) → R tanımsız; arayüzde "Yeni" yazılır.

**Cevap notu**: `AnswerGrade` = `again(1)`, `hard(2)`, `good(3)`, `easy(4)`. Kullanıcıya not
**sorulmaz**; cevaptan çıkarılır:

| Durum | Not |
|---|---|
| Yanlış cevap ve Devam / Bilemedim | `again` |
| Cevaba baktı, sonra Bildim | `hard` |
| Yazarak doğru, süre > 12 sn | `hard` |
| Yazarak doğru, 4–12 sn | `good` |
| Yazarak doğru, ≤ 4 sn | `easy` |
| Yanlış çıktı ama Doğru Say | `good` |
| Tanıma oyunlarında doğru (Çoktan Seçmeli, Eşleştir, Boşluğu Doldur) | `good` (asla `easy`) |

**Oyun ağırlığı** (`GameMode.weight`): hatırlama oyunları (Günlük Tekrar, Hızlı Tur, Ters Yön) `1.0`,
Harfleri Diz `0.8`, tanıma oyunları `0.6`.

**Güncelleme** (`Memory.review(stability:difficulty:lastReviewedAt:grade:weight:now:)` → yeni S, D, sıradaki tekrar):

- İlk cevap (`S == 0`): `S = [0.4, 1.2, 3.0, 8.0][grade−1] × weight` (en az 0.3),
  `D = [7, 6, 5, 3.5][grade−1]`.
- Doğru cevap (hard/good/easy):

      R      = R(t, S)
      büyüme = e^1.5 · (11 − D) · S^(−0.2) · (e^(1.2·(1−R)) − 1)
      çarpan = hard 0.5 · good 1.0 · easy 1.5
      S'     = S · (1 + büyüme · çarpan · weight)

  Aynı gün içindeki tekrarda R ≈ 1 olduğu için büyüme çok küçük kalır. Gün içinde oynamak
  zarar vermez ama asıl kazanç kelimeyi unutmaya yakınken hatırlamaktan gelir.
- Yanlış cevap (again): `S' = max(0.3, S × (weight == 1 ? 0.35 : 0.5))`. Sıfırlanmaz.
- Zorluk: again +1.0, hard +0.4, good −0.2, easy −0.6; sonra 5'e doğru %5 yaklaştır; 1…10 aralığında tut.
- Sıradaki tekrar: `now + S'` gün (hedef hatırlama %90).

**Türetilen kavramlar** (`Word` uzantısı):
- `memory(at:)` → `Double?` (yeni ise `nil`)
- `isWeak` → yeni **ya da** `R < 0.9`. Günlük Tekrar bunu sayar; sekme ve simge rozeti ile bildirim Günlük Tekrar'ın soracağı sayıyı (en fazla 20, 5'i yeni) gösterir.
- `isLearned` → `stability ≥ 21` gün (eski `box ≥ maxBox` tanımının yerini alır).

**Testler (zorunlu):** R(S,S)=0.9; yeni kelimenin ilk notları; doğru cevap S'yi büyütür, easy > good > hard;
aynı gün tekrarı neredeyse hiç büyütmez; yanlış sıfırlamaz; tanıma oyunu hatırlamadan az büyütür;
zorluk sınırlar içinde kalır.

## 3. Seçim ve sıra (A1, B3'te motora bağlanır)

`Shared/Logic/WordPicker.swift`, tohumlanabilir rastgele sayı üreteci alır (testte sabit sonuç).

- **Ağırlık:** yeni kelime `1.0`, diğerleri `(1 − R) + 0.1`. A1'de R yerine geçici olarak
  "gecikme": `min(1, gecikenGün / 7) + 0.1`.
- Ağırlıklı, tekrarsız örnekleme.
- **Aynı kelime art arda gelmez.** Yanlış bilinen kelime sıraya yeniden girerse arada en az 2 kelime olur
  (turda yeterli kelime yoksa en sona).
- **Yeni turun ilk kelimesi, önceki turun ilk kelimesi olamaz.** Önceki ilk kelimenin kimliği
  `UserDefaults`'ta tutulur.
- **Günlük Tekrar:** zayıf kelimeler, en fazla 20; bunların en fazla 5'i yeni.
- **Hızlı Tur:** 5 kelime, bütün defterden ağırlıklı seçim.
- **Diğer oyunlar:** oyunun kuralına göre (aşağıda), ağırlıklı seçim.

## 4. Görünüm dili ve tasarım deseni

Yeni her ekran, uygulamanın bugünkü ekranlarından türetilir. Başvuru kaynakları:
- **Kart ve cevap akışı:** `KelimeDefteri/Views/StudyView.swift` (26 pt köşeli kart, altta cam cevap çubuğu
  "Göster / ↑", sonuca göre `GradeOption` düğmeleri, kart içinde simgeli sonuç satırı).
- **Liste ve ayrıntı:** `WordListView.swift`, `WordDetailView.swift` (grouped `List`, `LabeledContent`,
  bölüm başlıkları, serif kelime + ikincil renkte Türkçe).
- **Simgeli satırlar:** `SettingsView.swift` (`SettingsIcon`: renkli kare içinde beyaz SF Symbol).
- **Boş durumlar:** `ContentUnavailableView`.
- **Mac:** `Mac/MacStudyView.swift`, `Mac/WordsWindow.swift` (menü penceresi kartı, sıralanabilir tablo);
  düğmeler formun altında sade durur, Sistem Ayarları'ndaki gibi satır içi standart düğmeler.

Desenin kuralları:

- **`MemoryRing`** (`BoxRing`'in yerini alır; iOS ve Mac ortak):
  - Halka R oranında dolu.
  - Renk: `≥ 0.90` yeşil (zayıf sınırı, `Memory.targetRetention`), `0.60–0.90` turuncu, `< 0.60` kırmızı.
  - Yeni kelimede kesik çizgili gri boş halka.
  - Yanına metin: `%62` ya da `Yeni`. Metin opsiyonel parametre.
- **"Kutu" kelimesi hiçbir ekranda kalmaz** (iOS, Mac, Paylaş eklentisi, İlerleme, Ayarlar).
- **Renkler ve yazı:** sistem mavisi vurgu; İngilizce kelimeler New York serif; Liquid Glass düğmeler
  (`.glass` / `.glassProminent`).
- **Titreşim:** doğru `.success`, yanlış `.warning`, seçim `.selection`.
- Kullanıcının istikrarlı istekleri: sonucu belli şeyi tekrar sorma, gereksiz seçenek ekleme, her düğmenin
  ayrı bir işi olsun. CLAUDE.md'deki tuzaklar da geçerli (pasif form düğmesinin rengini elle soldur,
  Mac'te form üstüne `.bar` şerit koyma, Mac'te `.tint`li `.glass` düğme dolu görünür).

## 5. Ekranlar

### 5.1 Çalış sekmesi: oyun merkezi (C1)

- `NavigationStack`, büyük başlık "Çalış". Alt başlık: "Hafıza %78 · 7 kelime zayıfladı"
  (ortalama R, yeni kelimeler hariç). Sağ üstte Ayarlar dişlisi kalır.
- Zemin `systemGroupedBackground`, içerik `ScrollView`.
- **Günlük Tekrar kartı** (tam genişlik, 26 pt köşe, `secondarySystemGroupedBackground`):
  - Solda başlık "Günlük Tekrar" (`.title2.bold`), altında "7 kelime zayıfladı · yaklaşık 3 dk"
    (kelime başına ~25 sn, yukarı yuvarlanır).
  - Sağda defterin ortalama hafızasını gösteren büyük `MemoryRing` (56 pt, ortasında yüzde).
  - Altta tam genişlik **Başla** (`.glassProminent`, large).
  - Zayıf kelime yoksa: "Bütün kelimeler güçlü" ve düğme **Yine de Çalış** (en zayıf 10 kelime).
- **"Oyunlar"** başlığı (`.title3.bold`), altında `LazyVGrid`, 2 sütun, 12 pt aralık.
- **Oyun kartı:** 18 pt köşeli kutu; üstte 44 pt renkli kare içinde beyaz SF Symbol
  (Ayarlar simgelerinin büyüğü); altında başlık (`.headline`) ve tek satırlık açıklama (`.footnote`, ikincil renk).
  Oynanamıyorsa soluk görünür ve açıklama yerine nedeni yazılır ("En az 4 kelime gerekli").

| Oyun | Simge | Renk | Açıklama | Koşul |
|---|---|---|---|---|
| Hızlı Tur | `bolt.fill` | turuncu | 5 kelime, 1 dakika | ≥ 1 kelime |
| Çoktan Seçmeli | `checklist` | mavi | 4 seçenekten doğrusu | ≥ 4 kelime |
| Eşleştir | `square.grid.2x2.fill` | yeşil | Anlamıyla eşle | ≥ 4 kelime |
| Boşluğu Doldur | `text.cursor` | mor | Cümleyi tamamla | cümlesi olan ≥ 4 kelime |
| Harfleri Diz | `textformat.abc` | pembe | Harflerden kelimeyi kur | ≤ 14 harfli ≥ 1 kelime |
| Ters Yön | `arrow.left.arrow.right` | camgöbeği | Türkçeden İngilizceye | ≥ 1 kelime |

- Henüz yapılmamış oyunun kartı gösterilmez; her C görevi kendi kartını ekler.
- Defter boşsa ekranın tamamı mevcut "Defterin Boş" görünümü.
- Her oyun `fullScreenCover` ile açılır: sol üstte kapat (✕, `role: .close`), üstte ince ilerleme çubuğu
  ve "3/10". Oyun ortasında kapatılırsa o ana kadarki cevaplar kaydedilmiş kalır.
- Sekme rozeti: Günlük Tekrar'ın soracağı kelime sayısı (kartta yazanla aynı).

### 5.2 Günlük Tekrar ve Hızlı Tur (C1)

- Bugünkü Çalış kartı ve cevap çubuğu aynen kullanılır: Göster / ↑, sonuca göre Devam / Doğru Say /
  Bilemedim–Bildim. `GradeOption` mantığı korunur. Kart başlığında "Kutu 2/5" yerine `MemoryRing` ve yüzde.
- Cevap süresi, kartın gösterildiği andan cevabın açıldığı ana kadar ölçülür.
- "Bugünlük Bu Kadar" ekranı kalkar; yerine tur özeti gelir.

### 5.3 Tur özeti (C1, bütün oyunlarda ortak)

- Başlık "Tur Bitti", altında "4/5 doğru · 42 sn".
- Liste: her kelime için kelime, Türkçesi ve "%45 → %78" (önceki ve sonraki hafıza, küçük halkayla).
  Yeni kelimede "Yeni → %71".
- Altta **Bir Tur Daha** (`.glassProminent`) ve **Bitti** (`.glass`). Bitti oyun merkezine döner.

### 5.4 Çoktan Seçmeli (C2)

- 10 soru. Üstte İngilizce kelime (serif, büyük) ve 🔊; varsa cümlesi küçük italik.
- Altta 4 tam genişlik cam düğme: Türkçe anlamlar, her kelimenin **ilk** anlamı.
- Yanlış seçenekler defterdeki diğer kelimelerden gelir. Önce aynı kaynaktan olanlar tercih edilir.
  Doğru cevapla aynı (katlanmış) anlam asla yanlış seçenek olmaz.
- Doğru seçim: düğme yeşile döner, 0,8 sn sonra otomatik geçer.
- Yanlış seçim: seçilen kırmızı, doğrusu yeşil olur ve altta **Devam** belirir. Otomatik geçmez; kullanıcı doğrusunu görür.

### 5.5 Eşleştir (C3)

- 5 kelime (defterde 4 varsa 4). İki sütun: solda İngilizce (serif), sağda karışık sırayla Türkçe ilk anlamlar.
- Bir sol ve bir sağ kutuya dokunulur.
  - Doğru çift: ikisi yeşil olup solar ve kaybolur (`.snappy`).
  - Yanlış çift: iki kutu kısa sallanır, kırmızı yanıp söner. Hata sayılır, seçim sıfırlanır.
- Üstte süre (mm:ss) ve hata sayısı. Hepsi eşleşince tur özeti.
- Kayıt: eşleşmeden önce hiç yanlış çifte girmediyse `good`, girdiyse `again`.

### 5.6 Boşluğu Doldur (C4)

- Yalnızca cümlesinde kelimenin kendisi geçen kelimeler (büyük/küçük harf ve aksan farkı yok). 10 soru.
  Kelime bilinen bir İngilizce ekle de geçebilir (s, es, d, ed, ing, er, ers, ly; son harf ikilenebilir).
  Kalıpta her 3+ harfli kelime ek alabilir ("depend on" ↔ "depends on", "raise an issue" ↔ "raised an issue");
  1–2 harfli kelimeler (in, on, an…) olduğu gibi aranır, kelimeler arası boşluk esnek. Bilinen sınır:
  düzensiz fiiller (took, made, rose) ve e düşmesi (raising) bulunmaz.
- Cümle serif gösterilir, kelimenin yeri `_____` ile boş. Altında Türkçe ilk anlamı ipucu olarak (ikincil renk).
- 4 İngilizce seçenek (cam düğme); yanlışlar diğer kelimelerden. Doğru/yanlış davranışı Çoktan Seçmeli ile aynı.
  Doğru seçilince boşluk kelimeyle dolar (vurgu rengi, kalın).

### 5.7 Harfleri Diz (C5)

- ≤ 14 harfli kelimeler. 8 soru. Üstte Türkçe anlamlar, altında cevap yuvaları
  (ifadelerde boşluk sabit bir aralık olarak görünür).
- Altta karışık harf taşları (cam, yuvarlak köşe).
  - Taşa dokununca ilk boş yuvaya gider; yuvadaki harfe dokununca taşa geri döner.
  - Yuvalar dolunca otomatik kontrol edilir.
  - Doğru: yeşil, 0,8 sn sonra geçer.
  - Yanlış: yuvalar sallanır, harfler yerinde kalır, düzeltilebilir.
- **Göster** düğmesi cevabı açar ve `again` sayılır. Hata sayısına göre not: 0 hata `good`, 1–2 hata `hard`, göster `again`.

### 5.8 Ters Yön (C6)

- Türkçe anlamlar büyük gösterilir; İngilizcesi yazılır. 10 soru.
- Çalış'taki cevap çubuğu (Göster / ↑) ve `GradeOption` mantığı aynen kullanılır.
- Kontrol: `AnswerChecker.fold` eşitliği ya da 5+ harfli kelimelerde en fazla 1 harf fark (yazım hatası).
  Yazım hatasıyla doğruysa "Neredeyse: doğrusu *idempotent*" gösterilir ve `hard` sayılır.

### 5.9 Hızlı Tur karışık (C7)

Hızlı Tur'un 5 sorusu oynanabilir oyun türlerinden rastgele seçilir; art arda aynı tür en fazla iki kez gelir.

### 5.11 Günlük Tekrar'da oyunlar (İŞ 5, 2026-09-26)

Günlük Tekrar, Tanış ve Yine de Çalış aynı karışımı kullanır (`Shared/Logic/DailyMix.swift`, `StudySession`);
Hızlı Tur ve Ters Yön değişmez. Kelime seçimi aynı: toplam 20, bunun en fazla 5'i yeni.

- **Yeni ya da zayıf (`isLapsed`) kelime:** önce Çoktan Seçmeli (ısınma). Cevaplanınca üretim sorusu sıraya
  araya en az iki başka kelime girecek yere eklenir (o kadar kelime yoksa sona): en fazla 14 harfliyse
  Harfleri Diz (Türkçeden İngilizceye), uzun ifadede yazarak cevap. Başlangıç sırasında ısınmalar mümkünse
  son iki sıraya düşmez.
- **Diğer vadeli kelimeler:** bugünkü gibi yalnız yazarak.
- Defterde 4'ten az farklı anlam varsa ya da kelimeye 3 çeldirici bulunamazsa ısınma yok, yazarak sorulur.
- Her cevap kendi türüyle kaydedilir (`choice`, `letters`, `daily`). Kelime turdan ancak üretimle çıkar;
  ilerleme ("3/5") ve silme benzersiz kelimeyle sayılır.
- **Yarıda bırakma:** bugün (04:00 sınırıyla) Çoktan Seçmeli cevabı olup hiç üretim cevabı olmayan, ilk cevabı
  bugün olan ya da zayıf kelime "üretim bekliyor" sayılır; sonraki Günlük Tekrar'a (20 sınırı içinde, önce)
  girer ve doğrudan üretimle sorulur. Kart sayısı ve rozet de onu sayar. Çoktan Seçmeli oyunu ve widget aynı
  türle yazdığı için orada tanınan yeni/zayıf kelime de böyle gelir. Kartta "1 kelime tekrar bekliyor" diye
  zayıflayanlardan ayrı yazılır; bugünün hatırlatması da onu sayar.
  Sınırlar: kural yalnız bugüne bakar; 04:00'ten hemen önce ısınıp bırakılan yeni kelime ertesi gün bekleyen
  sayılmaz, vadesi gelince (ısınma doğruysa ~2 gün, yanlışsa ertesi gün) normal yoldan sorulur. Sonraki turda
  bekleyen kelimenin özet satırı ısınmadan sonraki durumla başlar (yeni kelime "Yeni" yerine yüzdeyle görünür).
- Seçmeli ve harf sorularında kayıt ve ilerleme adım kimliğiyle yapılır: gecikmiş otomatik geçiş eski adımı
  ilerletemez, aynı adım iki kez kaydedilmez. Mac'te cevaptan sonra pencere kapanırsa açılınca sıradaki adıma geçilir.
- Tur özeti: kelime ilk üretim cevabıyla girer; önceki durum ısınmadan önceki, "doğru" için ısınma ve ilk
  üretim ikisi de doğru olmalı.
- **SPEC-MOTOR2 §9 karar 1'den sapma:** orada tur içinde yalnız hatırlama/Ters Yön yeniden sorar. Bu karışımda
  Harfleri Diz üretim sorusu olduğu için yanlışta yazarak cevap gibi yeniden sorulur (arada en az iki kelime; yeni
  karışık taşlarla). Isınma (Çoktan Seçmeli) yeniden sorulmaz. Harfleri Diz Türkçeden İngilizceye sorar,
  yazarak cevap İngilizceden Türkçeye; motor ikisini de üretim sayar.
- Tahmini süre: seçmeli 8 sn, Harfleri Diz 18 sn, yazarak 25 sn (`StudySession.dailySeconds`).

### 5.10 Diğer ekranlar (B3, B4)

- **Kelimelerim satırı:** sağda `MemoryRing` ve yüzde (ya da "Yeni").
  - Süzgeç: Tümü / Zayıf / Güçlü / Yeni.
  - Sıralama: Eklenme Tarihi / A–Z / Hafıza (en zayıf önce) / En Zor (zorluk).
- **Ayrıntı sayfası:**
  - "Hafıza" bölümü: büyük halka ve yüzde, "Sıradaki tekrar", "Görülme" (log sayısı),
    "Doğru bilme" oranı, "Son görülme" (göreli), "Ortalama cevap süresi".
  - "Geçmiş" bölümü: son 30 gösterim, her biri bir nokta (yeşil doğru, kırmızı yanlış),
    soldan sağa eskiden yeniye; altında oyun adlarına göre sayılar ("Günlük Tekrar 8 · Eşleştir 3").
- **İlerleme (Ayarlar):** kutu grafiği yerine hafıza dağılımı:
  Yeni / %0–50 / %50–70 / %70–90 / %90–95 / %95+ ve "Ortalama hafıza %78".
- **Ayarlar › Defterin:** "Öğrenilen" = `isLearned`.
- **Mac:** Çalış kartında `MemoryRing` ve yüzde; Kelimelerim tablosunda "Kutu" sütunu yerine
  sıralanabilir "Hafıza" sütunu; bitiş ekranı "Hepsi Güçlü" / "Yine de Çalış". Mac'teki çalışma da
  `ReviewLog` yazar ve karışık sırayı kullanır.

---

## 6. Görevler

`/loop` her turda işaretlenmemiş **ilk** görevi alır. Her görev bitince: kutuyu `[x]` yap,
kısa bir satırla ne yapıldığını rapora ekle, commit + push.

- [x] **A1 · Karışık sıra.** `WordPicker` (§3, gecikme ağırlığıyla) ve `StudySession` onu kullanır.
      Testler: tohumla belirli sonuç, art arda aynı kelime yok, ilk kelime öncekiyle farklı, yanlış kelime en az 2 kelime sonra.
- [x] **B1 · Kayıt modeli ve geçiş.** §1. Testler: geçiş değerleri, ikinci çalıştırmada değişiklik yok,
      `ReviewLog` ilişkisi (kelime silinince logları da silinir).
- [x] **B2 · Hafıza motoru.** §2, bütün zorunlu testlerle.
- [x] **B3 · Motoru bağla.** Her cevap `AnswerGrade` çıkarır, motoru uygular, `ReviewLog` yazar
      (`ReviewRecorder`, testli). `WordPicker` R ağırlığına geçer. `MemoryRing` her yerde, "Kutu" hiçbir yerde (§4, §5.10).
      Rozet ve bildirim zayıf kelime sayısıyla. iOS ve Mac.
- [x] **B4 · Kelime istatistiği.** §5.10 ayrıntı sayfası ve Kelimelerim süzgeç/sıralama.
- [x] **C1 · Oyun merkezi, Günlük Tekrar, Hızlı Tur, tur özeti.** §5.1–5.3.
- [x] **C2 · Çoktan Seçmeli.** §5.4
- [x] **C3 · Eşleştir.** §5.5
- [x] **C4 · Boşluğu Doldur.** §5.6
- [x] **C5 · Harfleri Diz.** §5.7
- [x] **C6 · Ters Yön.** §5.8
- [x] **C7 · Hızlı Tur karışık.** §5.9
- [x] **Z · Rapor.** `docs/CALISMA-RAPORU.md` tamamlanır (§7).

## 7. Her turda çalışma kuralları

1. `CLAUDE.md`'yi, bu dosyayı ve `docs/CALISMA-RAPORU.md`'yi (varsa) oku.
2. Görevi uygula. Paylaşılan mantık `Shared/Logic/` altında, `nonisolated`, birim testli.
3. Derle: iOS **ve** Mac (`-scheme KelimeDefteriMac -destination 'platform=macOS'`). Paylaş eklentisi iOS şemasıyla derlenir.
4. Testleri koş: `-parallel-testing-enabled NO`. Hepsi geçmeden commit etme.
5. Simülatörde `-demo` ile aç (`PreviewData` gerekirse güncelle: yeni, zayıf, güçlü, cümlesi olan/olmayan
   kelimeler olmalı). Görevin değiştirdiği her ekranın açık ve koyu mod görüntüsünü al
   (`xcrun simctl io booted screenshot`), kendin incele, sorunları düzelt.
   Kontrol: kesilen/taşan yazı, soluk görünmeyen pasif düğme, yanlış renk, "Kutu" kalıntısı.
6. Ekran görüntülerini kullanıcıya gönder (SendUserFile, `proactive`, kısa Türkçe açıklama).
7. `docs/CALISMA-RAPORU.md`'ye görev satırı ekle: ne yapıldı, verilen kararlar, bilinen eksikler.
8. Listede işaretle, `main`'e commit et (Türkçe mesaj, sonuna `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`), push et.
9. Tur sonunda `xcrun simctl shutdown all`.

**Cihaza kurulum (B3'ten sonra):** Görev bitip testler geçince CLAUDE.md'deki komutlarla iPhone'a kur
(telefon bağlı değilse atla ve rapora yaz) ve Mac'te `/Applications`'a kur (CLAUDE.md'deki Mac kurulum
adımlarının hepsi). Mac'te görsel test için ekranı devralabilirsin; kullanıcının gerçek kelimelerine
not verme, yazdığın deneme metinlerini sil.

**Kesin kurallar (yalnızca bunlar):**
1. **Apple Developer hesabında değişiklik yok** (yeni hedef, paket kimliği, App Group, iCloud kaydı).
   Gerekirse görevi `[~]` yap ve rapora yaz.
2. **iCloud (CloudKit) şemasında alan silme ya da yeniden adlandırma yok.** Yeni alan ve model eklemek serbest.

**Takılırsan:** Çalışır durumda bırak, sorunu rapora yaz, kutuyu `[~]` yap ve sıradaki göreve geç.
Bir görev bir sonrakinin ön koşuluysa (B1→B2→B3) ve bitmediyse döngüyü durdur ve raporda açıkla.

**Döngü bitişi:** Bütün kutular `[x]` ya da `[~]` olunca Z'yi yap, özet mesaj gönder ve döngüyü durdur.
