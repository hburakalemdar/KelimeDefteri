# Spec: Hafıza Motoru ve Tur İçi Oyun Mantığı — Yeniden Tasarım (Motor 2)

**Sürüm 8 — kodlamadan önceki son sürüm, kendi başına yeterli.** v6, kelimenin durumunu artımlı
alanlar yerine bir tabandan sonraki bütün cevapların gün gün yeniden oynatılmasıyla hesaplayan bir
mimariye geçti (`replay(taban, loglar, now) -> MemoryState`); v7 ve v8 bu mimarideki uç durumları
(göç sınırları, tanıma cevabının etkisi, yeniden hesap tetikleyicileri) kapattı. Bu belge önceki
sürümlere referans vermeden tek başına uygulanabilir.

Kaynaklar (tarihçe): `scratchpad/motor/1-ilerleme.md` … `17-denetim-v7.md`, `16-simulasyon-v7.md`.
Kod: `Shared/Word.swift`, `Shared/ReviewLog.swift`, `Shared/SharedStore.swift`,
`Shared/Logic/Memory.swift`, `ReviewRecorder.swift`, `MemoryMigration.swift`, `StudySession.swift`,
`GameRound.swift`, `WordPicker.swift`, `GameMode.swift`, `StoreMaintenance.swift`,
`ReminderPlanner.swift`, `Shared/Logic/GlanceQuiz.swift`, `Shared/Components.swift`,
`KelimeDefteri/Views/ContentView.swift`, `KelimeDefteri/Views/WordDetailView.swift`,
`Mac/MacGamesView.swift`, `Mac/WordsWindow.swift`, `Mac/MacSettingsView.swift`.

---

## 1. Özet

1. Kelimenin hafıza durumu, kayıtlı bir tabandan sonraki bütün cevapların **gün gün yeniden
   oynatılmasıyla** hesaplanır; sıra, hangi cihazdan geldiği, hangi sırada eşitlendiği sonucu
   değiştirmez.
2. Günün notu **orana** göre: üretim (hatırlama/Ters Yön/Harfleri Diz/Hızlı Tur'un hatırlama sorusu)
   cevap varsa yalnız onlardan, yoksa tanımadan (Çoktan Seçmeli/Eşleştir/Boşluğu Doldur/widget/
   bildirim). Yanlış oranı 1/3'ten fazlaysa gün "yanlış"; azsa "zayıflatmayan doğru"; hiç yanlış
   yoksa günün en iyi doğrusu. Yanlışlar her zaman sayılır; yalnızca bir yanlıştan sonraki 30
   dakikadan az süre içindeki doğrular sayılmaz.
3. Tanıma cevapları **hiçbir zaman "çıpayı" (büyüme hesabının başlangıç anını) ilerletmez**: kelime
   henüz olgunlaşmadıysa (S<21) S'yi büyütebilir (tavan 20,9) ve vade eski çıpadan yeniden hesaplanır
   (zaman ilerletilmeden, yalnızca S değiştiği için değişebilir); kelime zaten olgunsa (S≥21) hiçbir
   şeyi değiştirmez. Olgun bir kelime zayıflarsa (S≥21 kalarak), zayıflığını **yalnız üretim**
   kaldırabilir — tanıma tek başına kaldıramaz.
4. Seçim tek kurala indirgendi: `word.isDue(at: now)` (`dueDate <= now`). Ayrı bir "bugün yanlış
   yapılan hiçbir yerde seçilmesin" filtresi yok.
5. Gün sabah 04:00'te döner; göç deterministik ve kayıpsız (taban, göç anındaki son logun tarihine
   kadar sabitlenir, sonrası gelen loglar oynatılmaya devam eder).
6. Geri alma artık ayrı bir mekanizma değil: logu sil, yeniden oynat.
7. Önbellek cevap sonrası tek kelime için; uygulama/Mac penceresi öne gelince **bütün defter** için
   yeniden hesaplanır.

---

## 2. Motor kuralları

### 2.0 Kısa liste

1. Durum = `replay(taban, loglar, now)`; `Word` bu fonksiyonun önbelleği (§2.1).
2. Taban 7 alanla tutulur (`base*`); replay yalnızca `date > baseAt` olan logları işler; `baseAt`
   göç anındaki son logun (ya da eski çıpanın, hangisi ileriyse) tarihidir, `now` değil (§2.2, §6).
3. Gün sınırı 04:00, takvim bileşenli gün farkı (§2.3).
4. Günün notu = orana göre (üretim önce, yoksa tanıma); yanlışlar her zaman sayılır, yanlıştan
   sonraki <30 dakika içindeki doğrular sayılmaz (§2.4).
5. Gün işlenmesi: yanlış → zayıflat + ertesi gün 04:00'e sabitle; değilse büyüt — tanıma günü
   çıpayı hiç ilerletmez (S<21'de yalnız S/D büyür, S≥21'de hiçbir şey değişmez); zayıflık
   üretimle (S seviyesi fark etmez) ya da (yalnız S<21'de) iki farklı günde tanımayla temizlenir (§2.5).
6. Büyüme/ceza formülleri sabit, `t` tam gün, çıpa = `anchorAt` (§2.6).
7. `learnedAt` = replay'de şartın ilk sağlandığı gün; göç tabanı öğrenilmişse şart baştan
   sağlanmış sayılır (§2.7).
8. Seçim = `word.isDue(at:)`, tek kural, ekstra filtre yok (§2.9).
9. Önbellek: cevap sonrası o kelime; öne gelince/Mac penceresi açılınca bütün defter; widget kendi
   sürecinde tek kelime — hepsi önce o kelimenin göçünü tetikler (§2.10, §6).
10. Sıralama: eşit zamanda yanlış→mod→not; gelecekteki log oynatılmaz; 30 dk kapısı saniyeyle, `<` (§2.11).

### 2.1 Mimari: taban + loglardan yeniden oynatma

    func replay(base: BaseState, logs: [ReviewLog], now: Date) -> MemoryState

- `logs`, `date > base.at` VE `date <= now` olanlar, §2.11'deki sırayla işlenir, `DayBoundary`
  gününe göre kümelenir.
- Her gün için §2.4 (günün notu) ve §2.5 (günün işlenmesi) sırayla uygulanır; çıkan `MemoryState`
  bir sonraki günün girdisidir; son günün çıktısı `replay`in sonucudur.
- `MemoryState = { stability, difficulty, dueDate, lapsedAt: Date?, learnedAt: Date?, anchorAt: Date }`.

`Word` üzerindeki `stability`, `difficulty`, `dueDate`, `lastReviewedAt` (=`anchorAt` önbelleği),
`lapsedAt`, `learnedAt` alanları bu fonksiyonun **önbelleğidir**. Yazan taraf (`ReviewRecorder`)
artık "alanı doğrudan güncelle" yerine "logu ekle, sonra o kelime için `replay` çalıştırıp önbelleği
güncelle" yapar.

### 2.2 Alanlar (CloudKit yalnızca ekleme)

| Alan | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `lapsedAt` | `Date?` | `nil` | **Önbellek**: `replay`in son çıktısındaki zayıflık günü. Eski "vade geçmişte = zayıf" hilesi tamamen kalkar. |
| `baseStability` | `Double` | `0` | Taban S. |
| `baseDifficulty` | `Double` | `5` | Taban D. |
| `baseDueDate` | `Date` | `.distantPast` | Taban vade. |
| `baseLapsedAt` | `Date?` | `nil` | Taban zayıflık. |
| `baseAnchorAt` | `Date?` | `nil` | Taban çıpa (eski `lastReviewedAt`). |
| `baseLearnedAt` | `Date?` | `nil` | Taban `learnedAt`. |
| `baseAt` | `Date?` | `nil` | Tabanın geçerli olduğu an. `nil` = kelime henüz hiç göç kontrolünden geçmedi (bkz. §6: bu, "eski veri var, göç bekliyor" ile "yepyeni kelime" durumlarının ikisini de kapsar — ayrım `reviewCount`e bakılarak yapılır). |

`ReviewLog`'a yeni alan eklenmez.

**Yeni tanımlar** (`Word` üzerinde, tüm okuyucular bunları kullanır — eski `isWeak` **kaldırılır**):

    isLapsed         = lapsedAt != nil
    memory(at:)      = isNew ? nil : (isLapsed ? min(R(gerçek t, S), 0.5) : R(gerçek t, S))   // gerçek t = now − anchorAt
    isLearned        = stability >= 21 && !isLapsed        // canlı, learnedAt'ten ayrı
    isDue(at: date)  = dueDate <= date                     // TEK seçim/zayıflık kuralı

`DeckSummary`nin "N zayıf" sayacı (Kelimelerim özeti, "9 kelime · 2 zayıf · 4 güçlü · 3 yeni")
**`isDue(at: now)`** kullanır — Günlük Tekrar'ın seçtiği kümeyle birebir aynı kelimeler. "Güçlü" =
`!isNew && !isDue(at: now)`.

### 2.3 Gün sınırı

    DayBoundary.start(of: date) = 04:00 (saat < 04:00 ise bir önceki günün 04:00'ü)

Gün farkı takvim bileşeniyle alınır (`Calendar.dateComponents([.day], ...)`), `timeInterval/86400` ile değil.

### 2.4 Günün notu

    birincilCevaplar(gün) = o günün logları: bütün yanlışlar + öyle bir doğru ki, kendisinden önce
      aynı gün içinde 30 dakikadan AZ önce (< 1800 sn, §2.11) gelmiş bir yanlış YOKTUR.
    grup = birincilCevaplar içinde üretim varsa üretim, yoksa tanıma
      (üretim = hatırlama, Ters Yön, Harfleri Diz, Hızlı Tur'un hatırlama sorusu — GameMode
       eşlemesi §2.4a; tanıma = Çoktan Seçmeli, Eşleştir, Boşluğu Doldur, widget, bildirim)
    dayRatio = grup içindeki yanlış sayısı / grup içindeki toplam sayı
    dayGrade = dayRatio > 1/3 → YANLIŞ  ·  0 < dayRatio ≤ 1/3 → ZOR (zayıflatmaz)  ·  dayRatio == 0 → EN İYİ DOĞRU

Grup boşsa (o gün hiç birincil cevap yoksa) o gün motor için hiçbir şey değişmez.

**Kaynak seçimi (hangi cevabın notu/ağırlığı kullanılır):**
- Gün **yanlış** ise: grup içindeki en sert yanlışın (en küçük `yanlış_tür` katsayılı, §2.6 —
  yani tanıma > Harfleri Diz > hatırlama sertlik sırasıyla) oyunu kullanılır.
- Gün **"zor" (0<oran≤1/3)** ise: büyüme formülüne not olarak sabit `hard` verilir (bireysel
  cevapların notu ne olursa olsun); yalnızca **hangi oyunun ağırlığının** kullanılacağı, grup
  içindeki doğrulardan en iyi bireysel nota (easy>good>hard) sahip olanın oyunundan alınır.
- Gün **"en iyi doğru" (oran==0)** ise: grup içindeki doğrulardan en iyi bireysel nota (easy>good>
  hard) sahip olanın notu VE oyunu kullanılır; eşitlikte (aynı en iyi not birden fazla cevapta)
  üretim ağırlığı büyük olan (hatırlama/Ters Yön > Harfleri Diz) tercih edilir, o da eşitse günün
  en erken cevabı.

### 2.4a Üretim/tanıma eşlemesi (`GameMode`)

| Üretim (ağırlık 1.0/0.8) | Tanıma (ağırlık 0.6) |
|---|---|
| Günlük Tekrar, Yeni Eklenenler, Yine de Çalış, Ters Yön, Hızlı Tur'un hatırlama sorusu (ağırlık 1.0) | Çoktan Seçmeli, Eşleştir, Boşluğu Doldur, widget, bildirim (ağırlık 0.6) |
| Harfleri Diz (ağırlık 0.8) | |

### 2.5 Günün işlenmesi

    if dayGrade == YANLIŞ:
        S'/D' = yanlış formülü (§2.6), "zaten zayıf mı" sorusu GÜNÜN BAŞINDAKİ lapsedAt'e bakar
        anchorAt = bugün; lapsedAt = bugün; dueDate = bugün + 1 gün (04:00), lapsedAt kalkana kadar SABİT
    else:  // ZOR ya da EN İYİ DOĞRU
        isTanıma = grup == tanıma
        if isTanıma && stability ≥ 21:
            // olgun kelimede tanıma günü TAMAMEN donuk: S/D/anchorAt değişmez
        else:
            S'/D' = büyüme formülü (§2.6; tanıma+S<21 ise 20,9 tavanlı)
            if isTanıma: anchorAt DEĞİŞMEZ (yalnızca S/D güncellenir)
            else: anchorAt = bugün
        // zayıflık temizleme (§2.5a) her durumda ayrıca değerlendirilir:
        if lapsedAt != nil VE temizleme şartı (§2.5a) sağlanıyorsa: lapsedAt = nil
        dueDate = lapsedAt == nil ? anchorAt + stability gün : (değişmeden kalır)

**§2.5a Zayıflık temizleme şartı:**
- Üretim kaynaklı gün, farklı bir günde ise → temizlenir (**S seviyesinden bağımsız**, olgun ya da
  olgun olmayan kelimede aynı).
- Tanıma kaynaklı gün **VE `stability < 21`** ise, `lapsedAt`ten sonra `YANLIŞ` olmayan en az 2.
  farklı günde ise → temizlenir.
- Tanıma kaynaklı gün **VE `stability ≥ 21`** ise → **hiçbir zaman** temizlenmez; olgun bir kelime
  zayıfladıysa yalnız üretim onu kurtarabilir.

— *neden (S≥21 zayıf kelimede yalnız üretim):* 17-denetim-v7 [ŞÜPHE]: S=300'den 51,96'ya düşmüş bir
kelime, hâlâ olgun (S≥21) olduğu için iki farklı günde tanıma doğrusuyla, hiç hatırlama sorulmadan
"Öğrenildi"ye geri dönebiliyordu. Bu, widget kilidinin olgun kelimedeki başka bir biçimiydi: olgun
bir kelimenin yanlış yapılması güçlü bir sinyal (kelime gerçekten unutulmuş), bunu tersine çevirmek
için de güçlü bir kanıt (gerçek hatırlama) gerekir — tanımanın şansla/tanımayla geçilebilir doğası
bunun için yetersiz.

### 2.6 Büyüme/ceza formülleri

    t = DayBoundary(bugün) − DayBoundary(anchorAt)   (tam gün)
    R(t,S) = (1+19/81·t/S)^−0.5
    Doğru: büyüme = e^1.5·(11−D)·S^−0.2·(e^{1.2(1−R)}−1); çarpan hard 0.5·good 1.0·easy 1.5
           S'=S·(1+büyüme·çarpan·ağırlık); ağırlık: hatırlama/Ters Yön 1.0·Harfleri Diz 0.8·tanıma 0.6
           Tanıma tavanı: S<21 iken S'=min(S',20.9)
    Yanlış:  ceza(R)=0.65−0.30R, tavan=3√S, yanlış_tür: hatırlama/Ters Yön 1.0·Harfleri Diz 0.85·tanıma 0.7
             İlk zayıflama: S'=max(0.3,min(S·ceza(R)·yanlış_tür,tavan)); Zaten zayıf: S'=max(0.3,S·0.5·yanlış_tür)
    Zorluk: again +1.0·hard +0.4·good 0·easy −0.6; %15 ile 5'e yaklaştır; 1…10. S tavanı 3650 gün.

**Not türetme** (hangi cevap hangi nota dönüşür): yazarak doğru bilinen kelimede hız belirleyici —
süre eşikleri `max(2.5, 0.5×harf sayısı)` saniyeden az ise `easy`, `max(8, 1.2×harf sayısı)`
saniyeden azsa `good`, üzerindeyse `hard`; cevaba bakıp "Bildim" denmesi ve yazım hatasıyla doğru
("Neredeyse") `hard`; "Doğru Say" `hard` (kullanıcının kendi beyanı, gerçek doğru cevaptan zayıf
kanıt); Bilemedim/yanlış `again`. Tanıma oyunlarında doğru cevap her zaman `good` (asla `easy`).

Ekranda gösterilen anlık yüzde gerçek (kesirli) zamanla (`now − anchorAt`); yalnızca büyüme
formülündeki `t` tam gün. Zayıf kelimede ekran `min(R,0.5)`; halka rengi zayıf kelimede doğrudan
`lapsedAt != nil`den turuncu (sayısal değere bakmaz).

**Yeni kelime sınırı:** `bugünTanıtılan = words.count { kelimenin en eski ReviewLog'unun günü ==
bugün }`; günlük bütçe `max(0, 5 − bugünTanıtılan)`.

### 2.7 `learnedAt`

    learnedAt = replay boyunca, şu şart İLK KEZ sağlandığı günün tarihi:
      stability ≥ 21 VE lapsedAt == nil VE bugüne kadar YANLIŞ olmayan en az 2 FARKLI günde üretim
      katkısı var (bu iki gün ardışık olmak zorunda değil).
    Şart bir kez sağlanınca bir daha kontrol edilmez (o günün tarihinde sabit kalır).
    isLearned (canlı rozet) = stability ≥ 21 && lapsedAt == nil — replay'in son gündeki durumundan
    doğrudan okunur, learnedAt'ten AYRI.

Taban öğrenilmişse (`baseLearnedAt != nil`), replay bu tarihle başlar ve "2 farklı gün" şartı
**taban itibarıyla zaten sağlanmış** sayılır.

`ReviewRecorder`deki eski "öğrenilmiş değilse `learnedAt`'i sil" dalı ve
`MemoryMigration.fillLearnedDates` **tamamen kaldırılır**: `learnedAt` yalnızca `replay`in çıktısı.

### 2.8 Seçim

    isDue(word, now) = word.dueDate <= now

Bütün seçiciler (Günlük Tekrar, Yine de Çalış, Hızlı Tur, Çoktan Seçmeli, Eşleştir, Boşluğu Doldur,
Ters Yön, widget, bildirim) bu tek koşulu kullanır. Ayrı bir "bugün yanlış yapılan hiçbir yerde
seçilmesin" filtresi yoktur. "Vadeye bakan" akışlar (Günlük Tekrar, Yine de Çalış, widget, bildirim)
bugün zayıflayan kelimeyi doğal olarak yarına kadar bir daha almaz; "ağırlıklı, bütün defterden
seçen" oyunlar (Çoktan Seçmeli, Eşleştir, Boşluğu Doldur, Hızlı Tur, Ters Yön) `isDue`e bakmadan
seçtiği için bugün yanlış yapılan kelimeyi yine alabilir — bu kasıtlı: oranın kendini düzeltme
şansı (30 dakikalık kapı hile riskini zaten kapatıyor).

### 2.9 Önbellek — ne zaman ve nasıl yeniden hesaplanır

- **Bir cevap kaydedildiğinde**: önce o kelime için tek-kelime göçü (`migrateIfNeeded(word)`, §6)
  çalışır, sonra `replay` ile önbellek güncellenir.
- **iOS: `scenePhase == .active` olunca** (`ContentView.swift`): **bütün defter**. `MemoryCache.refreshAll(in:
  ModelContext)` (yeni dosya `Shared/Logic/MemoryCache.swift`) bütün `ReviewLog`ları tek sorguyla
  çekip kelimeye göre gruplar, her kelime için önce `migrateIfNeeded`, sonra `replay` çalıştırır.
- **Mac: menü penceresi açılınca, Kelimelerim (`WordsWindow`) ya da Ayarlar (`MacSettingsView`)
  penceresi açılınca**: aynı `MemoryCache.refreshAll`. Periyodik (ör. saatte bir) bir zamanlayıcı
  **eklenmez** — pencereler zaten sık açılıp kapanıyor, gözlemci (aşağıda) CloudKit tarafını
  kapsıyor, ek bir zamanlayıcı gereksiz karmaşıklık olurdu.
- **Uzak (iCloud) değişiklik bildirimi**: `MemoryCache.observeRemoteChanges(context:)`
  (`Shared/Logic/MemoryCache.swift`), SwiftData'nın uzak değişiklik bildirimini dinler, gelince
  `refreshAll` çağırır. *[Cihazda doğrulanacak: bu bildirimin CloudKit içe aktarımında güvenilir
  geldiği gerçek cihazda teyit edilmeli.]*
- **Widget/bildirim**: kendi sürecinde (`GlanceQuiz`/`ReminderQuiz`), yalnızca cevapladığı kelime
  için önce `migrateIfNeeded(word)`, sonra `replay`. `SharedStore`'un bazı kurulum adımlarını
  eklenti/widget sürecinde atlayan `!isExtension` koruması, **tek-kelime göçünü etkilemez** — bu
  kontrol her süreçte (ana uygulama, Paylaş eklentisi, widget) çalışır.

Maliyet: bütün defter (birkaç yüz kelime × onlarca log) tek toplu sorgu + kelime başına ucuz bir
döngü; gözle görülür gecikme yaratmaz.

### 2.10 Sıralama ve zaman belirsizlikleri

- Loglar tarihe göre artan sırada işlenir; tarihleri tam eşit olan loglarda ikincil sıralama: önce
  yanlış (`correct==false`), sonra oyun türü (`mode.rawValue` alfabetik), sonra not (küçükten büyüğe).
- `now`dan ileri tarihli loglar `replay`e alınmaz (cihaz saati ileri kaymışsa; zamanı gelince işlenir).
- 30 dakikalık kapı saniye hassasiyetinde: "yanlıştan sonraki doğru" `deltaSaniye < 1800` ise
  sayılmaz; tam `1800` saniye (30. dakika) **sayılır**.

---

## 3. Seçim, sayaç ve tur içi akış

### 3.1 Tur içi yeniden sorma ve sayaç

Hatırlama/üretim oyunları yanlış bilinen kelimeyi tur içinde en az 2 kart arayla tekrar sorar (yer
yoksa sormaz, kelime turdan "biten" sayılır); tanıma/karışık oyunlar (Çoktan Seçmeli, Eşleştir,
Boşluğu Doldur, Harfleri Diz, Hızlı Tur karışık) tur içinde tekrar sormaz. Sayaç/ilerleme çubuğu
`kalan = wordCount − finishedWordCount` üzerinden gösterilir; bir kelime doğru bilinerek ya da
yeniden sorma hakkı biterek "biten" sayılır — yanlış cevapla geri gitmez, erken dolmaz.

### 3.2 Diğer tur içi kurallar

- `GameDeck`in "en az 4 kelime" açılma koşulu ham kelime sayısına değil **farklı anlam sayısına**
  bakar (ortak Türkçe anlamlı kelimeler tek kümede sayılır).
- Çeldiriciler (Çoktan Seçmeli, Boşluğu Doldur) anlam-tabanlı seçilir: doğru cevapla ortak Türkçe
  anlamı olan kelime asla çeldirici olmaz.
- Ters Yön'de ortak anlamlı iki kelimeden biri yazılırsa **"Doğru, ama bu kartta aranan: X"**
  mesajı gösterilir, not `hard` sayılır (yeni bir arayüz öğesi eklemeden — proaktif kart ipucu §9/2'de
  karar bekliyor).
- `AnswerChecker`: Türkçe ek listesine (-mek/-mak, -i/-ı/-u/-ü, -de/-da, -ler/-lar, -lik/-lık,
  -siz/-sız vb.) göre kontrol edilir ("kara" "karar"ı karşılamaz); kullanıcının cevabı virgülle
  bölünmez, tek tahmin olarak değerlendirilir.
- Eşleştir'de hata, ilk dokunulan (soru rolündeki) tarafa yazılır.
- Harfleri Diz'de 0 hata `good`, 1–2 hata `hard`, 3+ hata ya da "Göster" `again`; taşlar küçük harfle
  gösterilir; özet ✗/✓ ekrandaki durumla tutarlıdır.
- "Bir Tur Daha" — kodda var olan tek düğme; "Aynı Kelimelerle Tekrar" diye ayrı bir düğme yoktur.
  Düğme metni açacağı akışı söyler.
- Boşluğu Doldur'da kelimenin cümledeki iki geçişi de boşaltılır; "Neredeyse"de yazılan cevap da
  gösterilir; Mac'te "Göster"in kısayolu (⌘↩) ile ekrandaki ipucu metni aynı tuşu gösterir; Hızlı
  Tur kartındaki süre metni gerçek tahminle (~2 dakika, 25 sn/kelime) verilir.

**Aynı gün, aynı desteyi tekrar oynama notu** (§9/3): "Bu tur bugünün diğer cevaplarıyla birlikte
değerlendiriliyor." — bu turun cevapları (30 dakikalık kapı hariç) günün oranına normal şekilde girer.

---

## 4. Tur özeti ve göstergeler

### 4.1 İkon, "önce"/"sonra"

- **İkon**: günün notu `YANLIŞ` ise ✗, değilse (`ZOR` ya da doğru) ✓.
- **"Önce"**: kelimenin turun başladığı andaki önbellek değeri (vade/durum metni) — tur başlamadan
  hemen önce okunan `word.dueDate`/`lapsedAt`.
- **"Sonra"**: turdan sonra `replay` çalıştırılınca çıkan yeni önbellek değeri.
- Yüzde değil, vade/durum metni gösterilir (tur özetinde ve soru kartında sayısal yüzde yok).

### 4.2 Renkler

Kırmızı "Şimdi" etiketi yok; turuncu = zayıf (`lapsedAt != nil`); yeşil = olgun; vade gerçekten
geçmişte kalırsa (kelime uzun süre açılmadıysa) "X gün gecikti" yazar.

### 4.3 Yüzde yalnızca ayrıntı/ilerleme ekranlarında

Tur özetinde ve soru kartında sayısal yüzde gösterilmez ("Öğreniliyor"/"Yeni" durum metni ya da vade
metni gösterilir); sayısal yüzde yalnızca Kelime Ayrıntı sayfasında ve İlerleme (Ayarlar) ekranında.

### 4.4 "Son görülme" (Kelime Ayrıntı sayfası)

`lastReviewedAt`ten değil (o, motorun `anchorAt` önbelleği — tanıma cevabıyla hiç ilerlemez),
doğrudan **kelimenin en güncel `ReviewLog` tarihinden** okunur (tür fark etmeden). İkisi ayrı
kavramlar: biri motorun "S'yi son ne zaman değiştirdim" çıpası, öbürü kullanıcının "bu kelimeyi en
son ne zaman gördüm" bilgisi.

---

## 5. Mac eşitliği

- Hub (`MacGamesView`) `current == nil` olduğunda plana bakmaksızın uygun turu doğrudan başlatır.
- Mac'te de iPhone'daki `RoundSummaryView`in bir eşdeğeri gösterilir; tur bitince kullanıcı "Bir Tur
  Daha"ya basana kadar özet ekranda kalır, kendiliğinden yeniden başlamaz.
- "Hepsi Güçlü" yalnızca gerçekten iş kalmadığında gösterilir (yeni kelime bekleniyorsa ayrı bir
  durum metni).
- Sayaç iPhone'daki ortak bileşenle (`GameProgressHeader`) birebir aynı `kalan` mantığını kullanır.
- "Tanış"tan gelen Günlük Tekrar `MenuBarView`'deki kalıcı `session`'a yönlenir, ayrı bir ikinci tur açmaz.

---

## 6. Göç ve CloudKit

**Tek-kelime göçü** (`MemoryMigration.migrateIfNeeded(word:)`), `replay`e giren **her yol**
(§2.9: cevap kaydı, bütün-defter yeniden hesabı, widget/bildirim süreci) tarafından, o kelimeyi
`replay`den geçirmeden **önce** çağrılır. Yalnızca `word.baseAt == nil` iken çalışır (idempotentlik
bayrağı, ayrı alana gerek yok):

1. **`reviewCount == 0`** (kelime hiç cevaplanmamış, ister eski ister v8'de yeni eklenmiş):
   `baseAt = .distantPast` yazılır, başka hiçbir şey yapılmaz — `replay` bütün logları (varsa) baştan
   işler. (Bu adım, "yeni sürümde ilk kez cevaplanan kelime" ile "hiç göç etmemiş eski kelime"
   ayrımını netleştirir: `reviewCount==0` her zaman "taban gerekmez" demektir.)
2. **`reviewCount > 0`** (eski veri var):
   - **Taban** = kelimenin o anki önbellek değerleri: `baseStability = stability`,
     `baseDifficulty = difficulty`, `baseAnchorAt = lastReviewedAt`, `baseLearnedAt = learnedAt`.
   - **`baseLapsedAt`** = eski "vade geçmişte = zayıf" hilesi (`dueDate < lastReviewedAt`)
     görülüyorsa `DayBoundary.start(of: lastReviewedAt)`, yoksa `nil`.
   - **`baseDueDate`**: zayıf değilse eski `dueDate` aynen taşınır. **Zayıfsa `baseDueDate` = göç
     anı** (eski hileli geçmiş vade değil) — kelime sahte bir "9 gün gecikti" metniyle değil,
     olduğu gibi (seçilebilir, "Bugün"/"Öğreniliyor") görünür.
   - **`baseAt` = `max(kelimenin göç anındaki EN SON ReviewLog'unun tarihi, eski lastReviewedAt)`**
     — ikisinden hangisi daha ileriyse. `now` **değil**.

`replay` yalnızca `date > baseAt` olan logları işler (`>=` değil): `baseAt` zaten "bu tarihe kadarki
her şey tabanda hesaba katıldı" anlamına geldiği için, `baseAt`in kendisiyle aynı tarihli log
**tabanda zaten sayılmış kabul edilir** ve tekrar işlenmez. `baseAt`ten **önceki** loglar da (nadiren
geç senkronize olan eski cevaplar) motor için yok sayılır — istatistik ekranlarında (ham `logs`
okuyan Kelime Ayrıntı geçmişi, oyun sayıları) olduğu gibi kalırlar.

**`baseAt`ten önce tarihli bir log daha sonra gelirse**: `replay`e alınmaz, yok sayılır. Bu yalnızca
göç anında o cihaza henüz eşitlenmemiş ve göç zamanından **önce** tarihli dar bir pencereyi etkiler
(göçten sonraki loglar zaten normal işlenir); etkisi tek bir geçmiş cevabın motor durumuna
yansımaması — cevabın kendisi (log) kaybolmaz, yalnızca hesaba dahil edilmez, sonraki gerçek
cevaplar durumu kendiliğinden düzeltir.

**İki cihaz farklı taban yazarsa** (ikisi de eski sürümle bu kelimeye dokunmuş, ayrı ayrı göç ediyor;
CloudKit'te "son yazan kazanır"): kaybeden cihazın tabanı silinir ama loglar kaybolmaz; yalnızca
kazanan tabanın `baseAt`inden önce tarihli, henüz kazanan cihaza ulaşmamış bir log varsa yukarıdaki
dar pencereye girer. Bu, tek seferlik göç anındaki küçük bir sayısal sapma riski; kabul edilebilir
çünkü (a) yalnızca eski→yeni sürüm geçiş anını etkiler, bir daha tekrarlanmaz, (b) v1–v7'nin kendisi
de zaten cihazlar arasında küçük, geçici tutarsızlıklara açıktı, (c) sonraki gerçek cevaplar durumu
hızla gerçek değerine yaklaştırır.

**`StoreMaintenance` birleştirme**: iki kayıt birleşirken loglar hayatta kalan kelimeye taşınır
(değişmedi). Taban seçimi:
- Biri `baseAt == nil`, öbürü dolu ise → **dolu olan** kazanır (`nil`, "henüz karar verilmedi"
  anlamına gelir, karşılaştırılamaz).
- İkisi de dolu ise → `baseAt`i **daha eski** olan kazanır (daha geniş bir log aralığını kapsar).
- İkisi de `nil` ise → birleşik kelimede de `nil` kalır (bir sonraki göç kontrolünde ele alınır).

Ardından o kelime için önbellek yeniden hesaplanır. `StoreMaintenance`'taki eski "en son çalışılan
kaydın önbelleğini olduğu gibi kopyala" kodu (alan-alan kopyalama) **kaldırılır** — artık taban
seçilir, önbellek `replay`den türetilir.

**Sayaçlar** (`reviewCount`, `correctCount`): `ReviewRecorder` artık bunları **artırmaz**. Mevcut
`Word.answerCount`/`correctAnswerCount` zaten `max(saklanan sayaç, logs.count)` deseniyle
hesaplandığı için (logs her zaman güncel kalır, saklanan sayaç göç öncesi değerde donar) bu alanlarda
kod değişikliği gerekmez; geri alma da otomatik doğru olur (log silinince `logs.count` düşer, `max`
formülü zaten `logs.count`ten okuyacak duruma gelmiştir).

**Bildirimler** (`ReminderPlanner`/`ReminderScheduler`): `word.dueDate`i doğrudan okur, ayrı hesap yapmaz.

**Eski + yeni sürüm birlikte çalışırsa**: eski sürüm hâlâ kendi `isLapsed` hilesiyle çalışır, yeni
sürümün yazdığı gerçek `lapsedAt`i bilmez — zayıf bir kelimeyi Günlük Tekrar'a almaz, S≥21 olan
(ama aslında zayıf) bir kelimeye "Öğrenildi" yazabilir; eski sürümün `fillLearnedDates`i de her
açılışta `learnedAt`i kendi (artık geçersiz) mantığıyla yeniden yazar; eski sürüm yeni `GameMode`
etiketlerini de tanımayıp varsayılana düşürebilir. Bu yüzden iki cihaz aynı görevde güncellenmeli.

**CloudKit:** `Word`e `lapsedAt`, `baseStability`, `baseDifficulty`, `baseDueDate`, `baseLapsedAt`,
`baseAnchorAt`, `baseLearnedAt`, `baseAt` eklenir. `ReviewLog`'a alan eklenmez.

---

## 7. Test planı

### 7.1 Senaryo tablosu

(D=5 başlangıç, hatırlama ağırlığı 1 aksi belirtilmezse; `sim_v7.py` ile doğrulandı.)

| Senaryo | S | D | vade metni | lapsedAt | learnedAt |
|---|---|---|---|---|---|
| Yeni kelime ilk yanlış (hatırlama / tanıma) | 0,40 / 0,30 | 7,0 | "Yarın" | bugün | — |
| Yeni kelime, iki ayrı turda Y→D ya da D→Y | 0,40 | 7,0 | "Yarın" | bugün | — |
| S=30 vadesinde, iki ayrı turda D→Y ya da Y→D (30 dk dışı) | 11,40 | 5,85 | "Yarın" | bugün | — |
| S=30 vadesinde, üç ayrı turda 1 Y (30 dk dışında, her sıra) | 56,05 | 5,34 | "56 gün sonra" | — | bugün *(ön şart: tabanda ya da önceki günde en az 1 üretim günü daha olmalı, toplam 2 farklı gün)* |
| S=30 vadesinde, yanlıştan 10 dk içinde 2 doğru (30 dk kapısı içi) | 11,40 | 5,85 | "Yarın" | bugün | — |
| S=30 vadesinde salt doğru | 82,09 | 5,00 | "82 gün sonra" | — | bugün *(aynı ön şart)* |
| S=30 vadesinde salt yanlış | 11,40 | 5,85 | "Yarın" | bugün | — |
| Dün yanlış, bugün doğru | 13,38 | 5,72 | "13 gün sonra" | temizlenir | — |
| S=30, art arda 2./3. gün yanlış (zaten zayıf, sabit ceza) | 5,70 / 2,85 | 6,57 / 7,19 | "Yarın" | bugün | — |
| S=300 vadesinde yanlış (tavan bağlıyor) | 51,96 | 5,85 | "Yarın" | bugün | değişmez |
| …ertesi gün doğru | 53,43 | 5,72 | "53 gün sonra" | temizlenir | değişmez |
| Tanımada şansla doğru (S=10, vadesinde) | 20,90 (<21) | 5,00 | **"11 gün sonra"** (vade = eski çıpa + 20,9; çıpa hiç ilerlemediği için görsel süre S'den kısa görünür) | — | yazılmaz |
| Zayıf kelime (S<21), tanımada 1. farklı günde doğru | S büyür, **vade değişmez** (`lapsedAt+1 gün` sabit) | — | gerçek zaman geçince metin "Bugün"a döner | kalır | — |
| …2. farklı günde tanıma doğrusu | S büyür, vade artık ileri | — | **"12 gün sonra"** (çıpa hâlâ ilk yanlışın gününde, ilerlemedi) | temizlenir | — |
| Olgun kelime (S≥21) zayıfladıktan sonra, iki farklı günde tanıma doğrusu | **temizlenmez** (§2.5a) — yalnız üretim kurtarabilir | — | "Yarın" (sabit kalır) | kalır | — |
| Olgun kelime (S≥21), yalnızca tanımayla her gün doğru | tamamen donuk (S/D/anchor/vade değişmez) | — | vadesi geldiğinde gerçek zamanla `isDue`, "X gün gecikti" | — | — |
| 23:58 yanlış / 00:02 doğru (04:00 sınırıyla aynı gün) | 11,40 | 5,85 | "Yarın" | bugün | — |
| 03:58 yanlış / 04:02 doğru (farklı gün) | 13,38 | 5,72 | "13 gün sonra" | temizlenir | — |
| İki cihaz: A yanlış yazar, B (görmeden) 2 doğru yazar; loglar eşitlenir | 56,05 (eksiksiz sonuç) | 5,34 | "56 gün sonra" | — | bugün |
| Bir cevap kaydedilip `ReviewLog`u silinir (geri alma) | silmeden önceki duruma birebir döner | | | | |

### 7.2 Zorunlu birim testleri

**A (replay motoru + önbellek + göç):**
- `replay` saf/deterministik; log ekleme sırası sonucu değiştirmez; ikincil sıralama (yanlış→mod→
  not) eşit-zamanlı loglarda belirlenmiş; gelecekteki log oynatılmaz.
- Oran + grup + 30 dk kapısı (saniyeyle; tam 1800 sn sayılır, 1799 sayılmaz).
- Tanıma + S<21: S büyür (20,9 tavanlı), anchorAt DEĞİŞMEZ, vade = eski anchorAt+yeni S.
- Tanıma + S≥21: tamamen donuk.
- Zayıflık temizleme: üretim 1 farklı gün (S seviyesinden bağımsız); tanıma yalnız S<21'de 2 farklı
  gün; **tanıma S≥21'de asla temizlemez**.
- `learnedAt` replay içinde bir kez, deterministik; geri alma = log silme + yeniden `replay`.
- Yeni önbellek okuyucuları: `isLapsed`/`memory(at:)`/`isLearned`/`isDue` doğru okunuyor
  (`StudySession`, `Components.DeckSummary`, `WordsWindow`, `GlanceQuiz`, `MacSettingsView`,
  `SettingsView`, `WeeklySummaryView` üzerinden).
- Göç: `reviewCount==0` kelimede `baseAt=.distantPast`, taban yok; `date > baseAt` (son log iki kez
  işlenmez — bir önceki sürümün hatası); `baseAt = max(son log, eski çıpa)`; bayat önbellekle göç
  (taban sonrası eski tarihli geç log yok sayılır, yeni tarihli log oynatılır); zayıf tabanda
  `baseDueDate = göç anı`; `baseLearnedAt` korunur, "2 farklı gün" şartı baştan sağlanmış sayılır;
  farklı tabanlı `StoreMaintenance` birleştirmede kural (nil kaybeder, dolu-dolu'da eski kazanır).
- `word == nil` bir log sonradan bir kelimeye bağlanınca (gecikmeli eşitleme) o kelimenin önbelleği
  bir sonraki yeniden hesaplamada güncellenir.
- İki cihaz: farklı log kümeleriyle başlayan iki `replay`, birleşik log kümesiyle aynı sonuca yakınsar.
- `reviewCount`/`correctCount` artık `ReviewRecorder`da artmıyor; `answerCount`/`correctAnswerCount`
  loglardan doğru okunuyor (geri almada da).

**B (tur içi oyun mantığı, A bittikten sonra):**
- `GameDeck` farklı anlam sayısı, anlam-tabanlı çeldirici, `AnswerChecker` ek listesi, `MatchBoard`
  hata sahipliği, `LetterPuzzle` eşiği/küçük harf, `ClozeSentence` iki geçiş.
- Bugün yanlış yapılan kelime, ağırlıklı oyunlarda (Çoktan Seçmeli/Eşleştir/Boşluğu Doldur/Hızlı Tur)
  yine seçilebiliyor (§2.8'in kasıtlı davranışı) — filtrelenmediği doğrulanır.

**C (özet/gösterge + Mac):**
- Tur özeti ikonu günün notu `YANLIŞ` mı diye bakar; "önce" tur başı önbellekten, "sonra" tur
  sonrası `replay`den.
- `MemoryRing`: zayıf kelime turuncu (sayısal değere bakmadan).
- Mac hub `current==nil` → doğru tur; düğme metni; Kelimelerim/Ayarlar açılışında bütün defter
  yeniden hesap tetiklendiği.
- Kelime Ayrıntı "son görülme" `logs.max(date)`ten.

**Eski testler:** `LearnedDateTests`, `SameDayMemoryTests`, `ReviewFixesTests`, `LogicFixesTests`
eski artımlı davranışı doğruladıkları için **silinir**. `MemoryMigrationTests` **yeniden yazılır**
(göç davranışını test etmeye devam eder, içeriği §6'ya göre baştan yazılır). `isWeak` kullanan
~20 test **`isDue`'ya uyarlanır** (mekanik değişiklik, silinmez). `KelimeDefteriTests` A'nın dosya
listesindedir.

---

## 8. Uygulama parçaları

**A önce biter**, **B ve C paralel**.

**A — Replay motoru + önbellek + göç + testler (tek başına, en kritik parça):**
`Shared/Word.swift` (`lapsedAt` + 7 `base*` alanı, `isLapsed`/`memory(at:)`/`isLearned`/`isDue`
tanımları, eski `isWeak` kaldırılır), `Shared/Logic/Memory.swift` (`replay`, §2.4–§2.7),
`Shared/Logic/ReviewRecorder.swift` (log ekler + o kelimeyi önce göçten geçirip yeniden hesaplar;
`updatesMemory`/`clearsLapse` parametreleri **kaldırılır** — replay her şeyi loglardan belirlediği
için "bu ilk cevap mı"/"zayıflık temizlensin mi" bilgisini çağırandan almaya gerek yok; gece yarısı
`calendar.isDate(.... inSameDayAs:)` "aynı gün" koruması da kaldırılır, günün notu artık `replay`in
kendi gün gruplamasından geliyor; eski "öğrenilmiş değilse `learnedAt`'i sil" dalı kaldırılır),
`GameRound.record`/`StudySession.record`'daki bu parametrelere bağlı çağrılar sadeleşir (yalnızca
`word, grade, mode, responseTime, now` kalır), `Shared/Logic/MemoryMigration.swift`
(`migrateIfNeeded(word:)` tek-kelime göçü, §6; `fillLearnedDates` kaldırılır),
**`Shared/Logic/MemoryCache.swift`** (yeni dosya: `refreshAll(in:)`, `observeRemoteChanges(context:)`),
`Shared/Logic/StudySession.swift` (geri alma = log sil + yeniden hesapla; Ters Yön "Doğru, ama
aranan: X" mesajının üretimi), `Shared/Logic/GameRound.swift` (`GameRound.summaryEntries` —
`RoundSummaryView.Entry(word:before:correct:)` çağrıları buraya taşınır, B'nin beş görünüm dosyası
bunu artık doğrudan kurmaz), `Shared/Logic/WordPicker.swift` (2 kart aralığı; ekstra "bugün yanlış"
filtresi yok), `Shared/Logic/GameMode.swift` (yalnızca üst kısım: etiketler/`weight`),
`Shared/Logic/StoreMaintenance.swift` (taban seçimi, eski kopyalama kodu kaldırılır),
`ReminderPlanner`/`ReminderScheduler`, `Shared/SharedStore.swift` (tek-kelime göçünün her süreçte
çalıştığından emin olunur), `Shared/Logic/GlanceQuiz.swift` (widget sorusu/cevabı, kendi sürecinde
tek-kelime göç+replay), `KelimeDefteri/Views/WordDetailView.swift` ("son görülme"),
`KelimeDefteri/Views/ContentView.swift` (`scenePhase` → `MemoryCache.refreshAll`),
`Mac/MacGamesView.swift` (menü penceresi açılışı → `refreshAll`), `Mac/WordsWindow.swift`,
`Mac/MacSettingsView.swift` (pencere açılışı → `refreshAll`), `Shared/Components.swift`
(`DeckSummary`/`MemoryRing`in `isDue`/`isLapsed` okuması), `Shared/Logic/WeeklySummary.swift`
(`learnedAt` artık göçte sıfırlanmadığı için doğru sayar), `KelimeDefteri/Views/SettingsView.swift`,
`KelimeDefteriTests` (yukarıdaki eski/yeni test listesi).

**B — Tur içi oyun mantığı + cevap kontrolü + çeldirici (A bittikten sonra):**
`Shared/Logic/ChoiceQuiz.swift`, `Shared/Logic/MatchBoard.swift`, `Shared/Logic/LetterPuzzle.swift`,
`Shared/Logic/QuickMix.swift`, `Shared/Logic/GameMode.swift` (yalnızca alt kısım: `GameDeck`/açılma
koşulu), `Shared/Logic/ClozeSentence.swift`, `Shared/Logic/ReverseChecker.swift`,
`Shared/AnswerChecker.swift`, `Shared/Games/FillBlankGameView.swift`, `MatchGameView.swift`,
`LettersGameView.swift`, `ChoiceGameView.swift`, `QuickMixGameView.swift` — bu beş görünüm dosyası
`RoundSummaryView.Entry`i doğrudan kurmaz, A'nın sağladığı `GameRound.summaryEntries`i okur.

**C — Özet/gösterge + Mac:** `Shared/Games/RoundSummaryView.swift`, `Shared/Games/RecallGameView.swift`,
`Shared/Games/GameScaffold.swift`, `Mac/MacStudyView.swift`, `Mac/MenuBarView.swift`,
`Shared/Logic/MemoryStats.swift`, `KelimeDefteri/Views/WordListView.swift`.

---

## 9. Kullanıcı kararı gereken noktalar

1. **Tanıma oyunlarında yanlış kelime tur içinde yeniden sorulsun mu?**
   Önerilen varsayılan: **Hayır**. Artı: küçük desteyi tekrar döndürme sorunu olmaz. Eksi:
   hatırlama oyunlarıyla tutarsız kalır.

2. **Yeni arayüz öğeleri — Harfleri Diz'e "İpucu" düğmesi ve Ters Yön'e proaktif ayırt edici ipucu
   eklensin mi?**
   Önerilen varsayılan: **Hayır**. Artı: "gereksiz seçenek yok" ilkesiyle uyumlu. Eksi: Harfleri
   Diz'de ince ayrım kaybolur; Ters Yön'deki belirsizlik yalnızca cevap-sonrası mesajla ele alınır.

3. **Aynı gün, aynı desteyi tekrar oynarken not gösterilsin mi?**
   Önerilen varsayılan: **Evet** — "Bu tur bugünün diğer cevaplarıyla birlikte değerlendiriliyor."
   Artı: kullanıcı sayının neden hemen değişmediğini/değiştiğini anlar. Eksi: ekstra metin.

4. **Aynı gün içinde bir kez doğru, bir kez yanlış bildiğin bir kelime: "bilemedin" mi sayılsın,
   "zor bildin" mi?**
   Şu anki kural, gün içindeki cevapların yarısından fazlası yanlışsa (ör. 2 cevaptan 1'i, ya da
   3 cevaptan 2'si) o günü "bilemedin" sayıyor — kelime ertesi güne erteleniyor ve dayanıklılığı
   düşüyor. Bu, günde tam **2 kez** çalışan (ör. sabah bir kez, akşam bir kez) bir kullanıcı için
   biraz sert olabiliyor: aynı doğrulukla günde 1 kez çalışan bir kullanıcı 500 kelimeden 241'ini,
   günde 2 kez çalışan yalnızca 102'sini, günde 3 kez çalışan ise 366'sını 120 günde "Öğrenildi"ye
   taşıyor — yani tam günde-2 en kötü durum.
   Önerilen varsayılan: **Şu anki kural kalsın** ("yarıdan fazla yanlışsa bilemedin"). Artı: kural
   tek ve basit kalır; en yaygın örnek (bir kelimeyi bir kez doğru bir kez yanlış bilmek) kullanıcının
   asıl şikâyetini ("yanlış cevabım hiç işlenmiyordu") en güçlü biçimde çözer. Eksi: günde tam iki
   kez çalışan, iyi bilen bir kullanıcı için beklenmedik bir sertlik — ama vadesi geldiğinde yalnızca
   bir kez çalışan (uygulamanın asıl beklediği kullanım biçimi) kullanıcılarda bu farkın pratik
   etkisi küçük (500'ün 486–499'u zaten "Öğrenildi"ye ulaşıyor).
