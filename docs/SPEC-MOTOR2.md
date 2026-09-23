# Spec: Hafıza Motoru ve Tur İçi Oyun Mantığı — Yeniden Tasarım (Motor 2)

**Sürüm 7.** v6'nın mimarisi (durum = loglardan yeniden oynatma) doğrulandı: sıra/iki cihaz/geri
alma 300/300, vade–seçim tutarlılığı 0 çelişki (`scratchpad/motor/14-simulasyon-v6.md`). v7,
denetimde bulunan mimariyle-tutarlı-olmayan artıkları kapatıyor: kodda hâlâ olmayan `lapsedAt`
alanı, göçün tek cihazda bayat taban alması, tanıma cevabının S<21 kelimede hâlâ "vade çıpasını"
ilerletip widget kilidini S≥21'in altında sürdürmesi, ve yeniden hesap tetikleyicisinin hiç
yazılmamış olması.

Kaynaklar: `1-ilerleme.md`…`13-denetim-v5.md`, `15-denetim-v6.md`, `14-simulasyon-v6.md`. Kod:
`Shared/Word.swift`, `Shared/ReviewLog.swift`, `Shared/Logic/Memory.swift`, `ReviewRecorder.swift`,
`MemoryMigration.swift`, `StudySession.swift`, `Components.swift`, `Mac/WordsWindow.swift`,
`Shared/Logic/GlanceQuiz.swift`, `Shared/Logic/WeeklySummary.swift`, `Shared/Logic/StoreMaintenance.swift`,
`KelimeDefteri/Views/ContentView.swift`, `Mac/MacGamesView.swift`.

---

## 1. Özet

1. Kelimenin hafıza durumu, kayıtlı bir tabandan sonraki bütün cevapların gün gün yeniden
   oynatılmasıyla hesaplanır (`replay`); `Word` üzerindeki alanlar bu fonksiyonun önbelleği.
2. Tanıma cevapları artık iki farklı davranışa göre ayrılıyor: kelime henüz olgunlaşmadıysa (S<21)
   S'yi büyütebilir (tavan 20,9) ama "çıpayı" (S'nin büyüme hesabındaki başlangıç anı) ve vadeyi
   ilerletmez; kelime zaten olgunsa (S≥21) hiçbir şeyi değiştirmez. Böylece yalnız widget/tanıma
   oynayan biri kelimeyi ne yapay şişirebiliyor ne de sonsuza dek erteleyebiliyor.
3. `lapsedAt` artık gerçek bir alan (önbellek); "vade geçmişte = zayıf" eski hilesi tamamen kalkıyor.
4. Göç deterministik ve kayıpsız: taban, kelimenin göç anındaki **son logunun tarihine** kadar
   sabitleniyor (`now`'a değil) — geç gelen ama o tarihten sonraki loglar hâlâ oynatılıyor, hiçbir
   cevap kaybolmuyor. Eski çıpa ve eski "öğrenildi" tarihi de tabana taşınıyor.
5. Yeniden hesap: uygulama öne gelince (iOS) ya da Mac penceresi açılınca **bütün defter** tek
   sorguyla yeniden oynatılıyor; widget kendi sürecinde yalnızca kendi kelimesini oynatıyor.
6. Sıralama artık tam belirli: eşit zamanlı loglarda önce yanlış, sonra oyun türü, sonra not;
   gelecekteki (saat kaymış) loglar oynatılmıyor; 30 dakikalık kapı saniye hassasiyetinde.

---

## 2. Motor kuralları

### 2.0 Kısa liste

1. Durum = `replay(taban, loglar, now)`; `Word` bu fonksiyonun önbelleği (§2.1).
2. Taban: `baseStability/baseDifficulty/baseDueDate/baseLapsedAt/baseAnchorAt/baseLearnedAt/baseAt`;
   `baseAt`'ten önceki loglar motor için yok sayılır, istatistikte kalır (§2.2, §6).
3. Gün sınırı 04:00, takvim bileşenli gün farkı (§2.3).
4. Günün notu = orana göre (üretim önce, yoksa tanıma); yanlışlar her zaman sayılır, yanlıştan
   sonraki <30 dakika içindeki doğrular sayılmaz (§2.4).
5. Gün işlenmesi: `again` → zayıflat + ertesi gün 04:00'e sabitle; değilse büyüt — **tanıma günü
   çıpayı hiç ilerletmez** (S<21 ise yalnız S/D büyür, S≥21 ise hiçbir şey değişmez); zayıflık
   uygunsa temizlenir (§2.5).
6. Büyüme/ceza formülleri değişmedi, `t` tam gün, çıpa = `anchorAt` (§2.6).
7. `learnedAt` = replay'de §2.7 şartının ilk sağlandığı gün; göç tabanı öğrenilmişse şart baştan
   sağlanmış sayılır (§2.7).
8. Seçim = `word.isDue(at:)` (`dueDate <= now`), tek kural (§2.9).
9. Önbellek: cevap sonrası o kelime; öne gelince/Mac penceresi açılınca **bütün defter**; widget
   kendi sürecinde tek kelime (§2.10).
10. Sıralama: eşit zamanda yanlış→mod→not; gelecekteki log yok sayılır; 30 dk kapısı saniyeyle,
    `<` (§2.11).

### 2.1 Mimari — değişmedi

    func replay(base: BaseState, logs: [ReviewLog], now: Date) -> MemoryState

`logs`, `date >= base.at` ve `date <= now` olanlar, §2.11'deki sırayla işlenir, `DayBoundary` gününe
göre kümelenir; her gün §2.4/§2.5 uygulanır. `MemoryState = { stability, difficulty, dueDate,
lapsedAt: Date?, learnedAt: Date?, anchorAt: Date }`.

### 2.2 Alanlar (CloudKit yalnızca ekleme)

| Alan | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `lapsedAt` | `Date?` | `nil` | **Önbellek**: `replay`in son çıktısındaki zayıflık günü. Artık gerçek bir alan; eski "vade geçmişte = zayıf" hilesi (`dueDate < lastReviewedAt`) tamamen kalkıyor. |
| `baseStability` | `Double` | `0` | Taban S. |
| `baseDifficulty` | `Double` | `5` | Taban D. |
| `baseDueDate` | `Date` | `.distantPast` | Taban vade. |
| `baseLapsedAt` | `Date?` | `nil` | Taban zayıflık. |
| `baseAnchorAt` | `Date?` | `nil` | Taban çıpa (eski `lastReviewedAt`) — büyüme formülünün ilk `t` hesabı için gerekli; yoksa göç sonrası ilk tekrar "göçten bu yana" gibi (yanlış) sayılır. |
| `baseLearnedAt` | `Date?` | `nil` | Taban `learnedAt` (eski öğrenilme tarihi). |
| `baseAt` | `Date?` | `nil` | Tabanın "kadar" geçerli olduğu an (göç anındaki son log tarihi, §6). `nil` = kelime henüz göç etmedi/hiç cevaplanmadı. |

`stability`, `difficulty`, `dueDate`, `lastReviewedAt` (= `anchorAt` önbelleği), `learnedAt` mevcut
alanlar, artık `replay` çıktısının önbelleği.

**Yeni tanımlar** (`Word` üzerinde, tüm okuyucular bunları kullanır):

    isLapsed        = lapsedAt != nil
    memory(at:)      = isNew ? nil : (isLapsed ? min(R(gerçek t, S), 0.5) : R(gerçek t, S))   // gerçek t = now − anchorAt
    isLearned        = stability >= 21 && !isLapsed        // canlı, learnedAt'ten ayrı
    isDue(at: date)  = dueDate <= date                     // TEK seçim/zayıflık kuralı

— *neden:* 15-denetim-v6 Yüksek #1: kodda `lapsedAt` diye bir alan yoktu, `isLapsed` hâlâ eski
`dueDate < lastReviewedAt` hilesine bağlıydı; v6'nın önbelleğinde zayıf kelimenin vadesi çıpadan
**sonra** geldiği için bu hile hep `false` dönüyor, S=300'den 52'ye düşmüş bir kelime "Öğrenildi"
görünüyordu. `lapsedAt`i gerçek bir alan yapmak ve bütün okuyucuları (aşağıda §8/A) ona/`isDue`'ya
geçirmek bunu kapatıyor.

### 2.3 Gün sınırı — değişmedi

    DayBoundary.start(of: date) = 04:00 (saat < 04:00 ise bir önceki günün 04:00'ü), takvim bileşenli gün farkı.

### 2.4 Günün notu — değişmedi

    birincilCevaplar(gün) = o günün logları: bütün yanlışlar + öyle bir doğru ki, kendisinden önce
      aynı gün içinde 30 dakikadan AZ önce (< 1800 sn, §2.11) gelmiş bir yanlış YOKTUR.
    grup = birincilCevaplar içinde üretim (hatırlama/Ters Yön/Harfleri Diz) varsa üretim, yoksa tanıma
    dayRatio = grup içindeki yanlış sayısı / grup içindeki toplam sayı
    dayGrade = dayRatio > 1/3 → again · 0 < dayRatio ≤ 1/3 → hard (kaynak: grup içindeki en iyi
               ağırlıklı cevap) · dayRatio == 0 → grup içindeki en iyi doğru
    `again`in kaynağı (yanlış formülündeki `yanlış_tür` için): grup içindeki en sert (en küçük
      yanlış_tür'lü) yanlış cevabın oyunu.

Grup boşsa (o gün hiç birincil cevap yoksa) o gün motor için hiçbir şey değişmez.

### 2.5 Günün işlenmesi — tanıma artık çıpayı hiç ilerletmiyor

    if dayGrade == again:
        (değişmedi) S'/D' = yanlış formülü (§2.6, "zaten zayıf mı" GÜNÜN BAŞINDAKİ lapsedAt'e bakar);
        anchorAt = bugün; lapsedAt = bugün; dueDate = bugün + 1 gün (04:00), lapsedAt kalkana kadar SABİT.
    else:  // hard ya da en iyi doğru
        isTanıma = grup == tanıma
        if isTanıma && stability ≥ 21:
            // olgun kelimede tanıma günü TAMAMEN donuk: S/D/anchorAt değişmez
        else:
            S'/D' = büyüme formülü (§2.6; tanıma + S<21 ise 20,9 tavanlı)
            if isTanıma:
                anchorAt DEĞİŞMEZ (yalnızca S/D güncellenir — tanıma "çıpayı" hiçbir zaman ilerletmez)
            else:  // üretim
                anchorAt = bugün
        // zayıflık temizleme (§2.5a) HER İKİ daldan sonra da ayrıca değerlendirilir (S≥21-donuk
        // dahil — donukluk yalnızca S/D/anchorAt'i kapsar, temizlemeyi engellemez):
        if lapsedAt != nil VE temizleme şartı (§2.5a) sağlanıyorsa: lapsedAt = nil
        dueDate = lapsedAt == nil ? anchorAt + stability gün : (değişmeden kalır, zaten sabit)

§2.5a (zayıflık temizleme) değişmedi: üretim + farklı gün → temizlenir; tanıma + `lapsedAt`ten sonra
`again` olmayan en az 2. farklı gün → temizlenir.

— *neden:* 14-simulasyon-v6 Y1: v6'da tanıma günü S<21'de büyürken **vadeyi de** `bugün + yeni S`ye
yazıyordu; kelime vadesine geldiği sabah widget'ta cevaplanınca vade yeniden 20 gün ileri gidiyor,
kelime hiç `isDue` olmuyor, S 21'i hiç geçemiyordu (%100/%90 widget kullanıcısında 41/300 "Öğrenildi").
Çıpayı hiç ilerletmeyip vadeyi **eski çıpa + yeni S** ile hesaplamak (denendi, simülasyonda 41→299/300)
bunu kapatıyor: kelime hâlâ büyüyor ama "ne zaman sorulacağı" gerçek zamandan kopmuyor, sonunda
vadesi gelip `isDue` oluyor ve hatırlama pratiğine düşüyor. Olgun (S≥21) kelimedeki tam donukluk
(v6'dan devam eden kural) değişmedi — o hâlâ Y2/Y5'in (widget'ın S=30'u 1216'ya şişirmesi) çözümü.

### 2.6 Büyüme/ceza formülleri — değişmedi

    t = DayBoundary(bugün) − DayBoundary(anchorAt)   (tam gün)
    R(t,S) = (1+19/81·t/S)^−0.5
    Doğru: büyüme=e^1.5·(11−D)·S^−0.2·(e^{1.2(1−R)}−1); çarpan hard 0.5·good 1.0·easy 1.5
           S'=S·(1+büyüme·çarpan·ağırlık); ağırlık: hatırlama/Ters Yön 1.0·Harfleri Diz 0.8·tanıma 0.6
           Tanıma tavanı: S<21 iken S'=min(S',20.9)
    Yanlış: ceza(R)=0.65−0.30R, tavan=3√S, yanlış_tür: hatırlama/Ters Yön 1.0·Harfleri Diz 0.85·tanıma 0.7
            İlk zayıflama: S'=max(0.3,min(S·ceza(R)·yanlış_tür,tavan)); Zaten zayıf: S'=max(0.3,S·0.5·yanlış_tür)
    Zorluk: again +1.0·hard +0.4·good 0·easy −0.6; %15 ile 5'e yaklaştır; 1…10. S tavanı 3650 gün.

Ekranda gösterilen anlık yüzde gerçek zamanla (`now − anchorAt`); yalnızca büyüme formülündeki `t`
tam gün.

### 2.7 `learnedAt`

    learnedAt = replay boyunca, şu şart İLK KEZ sağlandığı günün tarihi:
      stability ≥ 21 VE lapsedAt == nil VE bugüne kadar `again` OLMAYAN en az 2 FARKLI günde üretim
      (hatırlama/Ters Yön/Harfleri Diz) katkısı var — bu iki gün **ardışık olmak zorunda değil**,
      yalnızca ikisi de farklı günlerde ve o günün notu `again` değilse yeterli.
    Şart bir kez sağlanınca bir daha kontrol edilmez (o günün tarihinde sabit kalır).
    isLearned (canlı rozet) = stability ≥ 21 && lapsedAt == nil — learnedAt'ten AYRI, replay'in son
    gündeki durumundan doğrudan okunur.

Taban öğrenilmişse (`baseLearnedAt != nil`), replay bu tarihle başlar ve "2 farklı gün" şartı
**taban itibarıyla zaten sağlanmış** sayılır (bkz. §6) — göç sonrası yeniden sıfırdan 2 gün
biriktirmesi gerekmez.

`ReviewRecorder.swift`'teki eski "öğrenilmiş değilse `learnedAt`'i sil" dalı ve
`MemoryMigration.fillLearnedDates` **tamamen kaldırılır**: `learnedAt` artık yalnızca `replay`in
çıktısı, hiçbir yerde ayrıca yazılmaz/silinmez.

— *neden ("ardışık" netleştirmesi):* 15-denetim-v6 Düşük: "art arda ikisi de `again` olmayan"
ifadesi ardışık günler mi yoksa herhangi iki gün mü sorusunu açık bırakıyordu; simülasyon "herhangi
iki farklı gün" okumasıyla koşuldu ve sağlıklı sonuç verdi (D1 vb.), bu okuma resmileştirildi.

### 2.8 Değişmeyenler

Not türetme tablosu, süre eşikleri, yeni kelime sınırı (`bugünTanıtılan = words.count { en eski
ReviewLog'unun günü == bugün }`, bütçe `max(0,5−bugünTanıtılan)`) — v6 ile aynı.

### 2.9 Seçim — tek kural, değişmedi

    isDue(word, now) = word.dueDate <= now

Ayrı bir "bugün yanlış yapılan hiçbir yerde seçilmesin" filtresi yok. "Vadeye bakan" akışlar
(Günlük Tekrar, Yine de Çalış, widget, bildirim) `isDue`e bakar; "ağırlıklı, bütün defterden seçen"
oyunlar (Çoktan Seçmeli, Eşleştir, Boşluğu Doldur, Hızlı Tur, Ters Yön) bakmaz — bugün yanlış
yapılan kelimeyi yine alabilirler, bu kasıtlı (oran kuralının kendini düzeltme şansı, §2.9 v6 gerekçesi).

### 2.10 Önbellek — yeniden hesap tetikleyicisi

- **Bir cevap kaydedildiğinde**: yalnızca o kelime.
- **iOS: uygulama öne gelince** (`scenePhase == .active`): **bütün defter**, tek sorguyla — tüm
  `ReviewLog`lar bir kerede çekilip `word`e göre gruplanır, her kelime için `replay` çalıştırılır
  (kelime başına ayrı ayrı ilişki yüklemek yerine).
- **Mac: menü penceresi açılınca** (`MenuBarExtra`in kendisi "öne gelme" bildirimi vermediği için
  ayrıca): **bütün defter**, aynı toplu sorgu. Ayrıca menü çubuğunda uzun süre açık kalabilen
  pencere için periyodik bir yenileme (ör. saatte bir) düşünülür.
- **iCloud (uzak) değişiklik bildirimi**: `NSPersistentStoreRemoteChangeNotification`/SwiftData
  eşdeğeri gözlemlenir, geldiğinde bütün defter yeniden hesaplanır. *[Cihazda doğrulanacak: SwiftData'nın
  CloudKit içe aktarımında bu bildirimi güvenilir yolladığı gerçek cihazda teyit edilmeli.]*
- **Widget**: kendi sürecinde, yalnızca cevapladığı kelime için `replay` (zaten `ReviewRecorder`
  yolunu kullanıyor).

Maliyet: bütün defter (birkaç yüz kelime × onlarca log) tek toplu sorgu + kelime başına ucuz bir
döngü — gözle görülür gecikme yaratmaz (bir kez, öne geliş/pencere açılışı anında).

— *neden ("yalnızca değişen kelimeler" yerine hepsi):* 15-denetim-v6 Yüksek #4 ve "sadelik" notu:
"hangi kelimenin logs'u değişti"yi saptayacak bir alan/mekanizma şemada yoktu, eklemek ayrı bir
karmaşıklık getirirdi. Bütün defteri yeniden hesaplamak zaten ucuz olduğu için bu ihtiyacı tamamen
ortadan kaldırıyor — daha basit ve daha sağlam.

### 2.11 Sıralama ve zaman belirsizlikleri

- Loglar tarihe göre artan sırada işlenir; **tarihleri tam eşit** olan loglarda ikincil sıralama:
  önce yanlış (`correct == false`), sonra oyun türü (`mode.rawValue` alfabetik), sonra not
  (`grade` küçükten büyüğe) — herhangi bir belirsizlik kalmasın diye tamamen keyfi ama sabit bir kural.
- `now`dan **ileri tarihli** loglar (cihaz saati ileri kaymışsa) `replay`e alınmaz.
- 30 dakikalık kapı saniye hassasiyetinde: "yanlıştan sonraki doğru" `deltaSaniye < 1800` ise
  sayılmaz; tam `1800` saniye (30. dakika) **sayılır** (`<`, `<=` değil).

---

## 3. Seçim, sayaç ve tur içi akış — v6 ile aynı

§2.9'daki tek kural, tur içi yeniden sorma (2 kart arayla), `GameDeck` farklı anlam sayısı, çeldirici,
Ters Yön mesajı, `AnswerChecker`, Eşleştir/Harfleri Diz kuralları, "Bir Tur Daha" (kodda var olan tek
düğme) — değişmedi.

**Aynı gün, aynı desteyi tekrar oynama notu** (§9/3): "Bu tur bugünün diğer cevaplarıyla birlikte
değerlendiriliyor." — değişmedi.

---

## 4. Tur özeti ve göstergeler — v6 ile aynı

İkon = `dayGrade==again` mi; "önce" = tur başı önbellek, "sonra" = tur sonrası `replay`; yüzde
yalnızca ayrıntı/ilerleme ekranında; "son görülme" `logs.max(date)`ten (§4.4, değişmedi).

---

## 5. Mac eşitliği — değişmedi

---

## 6. Göç ve CloudKit

Yalnızca **`reviewCount > 0`** olan (yani daha önce en az bir kez cevaplanmış) kelimeler göç eder;
hiç cevaplanmamış kelimede taban gerekmez, `baseAt` `nil` kalır, ilk gerçek cevap S=0'dan başlar.

1. **Taban = kelimenin göç anındaki mevcut önbellek değerleri**: `baseStability = stability`,
   `baseDifficulty = difficulty`, `baseAnchorAt = lastReviewedAt`, `baseLearnedAt = learnedAt`.
2. **`baseLapsedAt`**: eski "vade geçmişte = zayıf" hilesi (`dueDate < lastReviewedAt`) görülüyorsa
   `DayBoundary.start(of: lastReviewedAt)`, yoksa `nil`.
3. **`baseDueDate`**: zayıf değilse eski `dueDate` aynen taşınır. **Zayıfsa `baseDueDate` = göç
   anı** (eski hileli geçmiş vade değil) — böylece kelime "9 gün gecikti" gibi sahte bir metinle
   değil, olduğu gibi (seçilebilir, "Bugün"/"Öğreniliyor") görünür.
4. **`baseAt` = kelimenin göç anındaki EN SON `ReviewLog`unun tarihi** (log hiç yoksa `lastReviewedAt`,
   o da yoksa göç anı). **`now` değil.** Bu tarihten **önceki** loglar taban değerlerine zaten
   yansımış kabul edilir ve motor için bir daha işlenmez (istatistik ekranlarında kalırlar); bu
   tarihten **sonraki**, henüz o cihaza eşitlenmemiş loglar geldiğinde normal şekilde `replay`e girer
   — hiçbir cevap kalıcı olarak kaybolmaz.
5. `baseAt` doluysa bu adım bir daha çalışmaz (idempotent, ayrı bayrağa gerek yok).

**Baseat'ten önce tarihli bir log daha sonra gelirse** (nadir: göç anında o cihaza henüz
eşitlenmemiş, ama tarihi `baseAt`ten **önce** olan bir log): bu log `replay`e alınmaz, yok sayılır.
Bu yalnızca "göç anında eşitlenmemiş ve göç zamanından önce tarihli" dar bir pencereyi etkiler
(göçten sonraki loglar zaten normal işlenir); etkisi tek bir geçmiş cevabın motor durumuna
yansımaması — cevabın kendisi (log) kaybolmaz, yalnızca hesaba dahil edilmez, ve sonraki gerçek
cevaplar durumu zaten kendiliğinden düzeltir.

**İki cihaz farklı taban yazarsa** (ikisi de eski sürümle bu kelimeye dokunmuş, ayrı ayrı göç
ediyor; CloudKit'te "son yazan kazanır"): kaybeden cihazın tabanı silinir, ama loglar (CloudKit'e
ekleme olarak yazıldıkları için) kaybolmaz — yalnızca kazanan tabanın `baseAt`inden önceki, henüz
kazanan cihaza ulaşmamış bir log varsa yukarıdaki paragraftaki dar pencereye girer. Bu, **tek
seferlik göç anındaki** küçük bir sayısal sapma riski; kabul edilebilir çünkü (a) yalnızca eski
sürümden yeni sürüme geçiş anını etkiler, bir daha tekrarlanmaz, (b) v1–v5'in kendisi de zaten
cihazlar arasında küçük, geçici tutarsızlıklara açıktı, (c) sonraki gerçek cevaplar durumu hızla
gerçek değerine yaklaştırır.

**`StoreMaintenance` birleştirme**: iki kayıt birleşirken loglar hayatta kalan kelimeye taşınır
(değişmedi); **taban olarak ikisinden `baseAt`i daha ESKİ olanın tam taban seti** (`base*`, hepsi
birlikte) alınır — daha geniş bir log aralığını kapsadığı için veri kaybı riski daha düşük. Ardından
o kelime için önbellek yeniden hesaplanır.

**Bildirimler** (`ReminderPlanner`): `word.dueDate`i okur, ayrı hesap yapmaz.

**Eski + yeni sürüm birlikte çalışırsa**: eski sürüm hâlâ kendi `isLapsed` hilesiyle çalışır —
yeni sürümün yazdığı gerçek `lapsedAt`i **bilmez**, dolayısıyla zayıf bir kelimeyi Günlük Tekrar'a
almaz ve S≥21 olan (ama aslında zayıf) bir kelimeye "Öğrenildi" yazabilir; eski sürümün
`fillLearnedDates`i de her açılışta `learnedAt`i kendi (artık geçersiz) mantığıyla yeniden yazar.
Bu yüzden iki cihaz aynı görevde güncellenmeli (mevcut kurulum süreci zaten bunu sağlıyor).

**CloudKit:** `Word`e `lapsedAt`, `baseStability`, `baseDifficulty`, `baseDueDate`, `baseLapsedAt`,
`baseAnchorAt`, `baseLearnedAt`, `baseAt` eklenir. `ReviewLog`'a alan eklenmez.

---

## 7. Test planı

### 7.1 Senaryo tablosu

v6'nın satırları büyük ölçüde aynı kalıyor; **gösterim metinleri gün sınırına göre düzeltildi**
(çıpa 04:00 olduğu için bazı vadeler bir önceki sürümde yazılandan görsel olarak bir gün kısa/uzun
görünebiliyordu — bu artık gerçek `DayBoundary` hesabıyla tutarlı):

| Senaryo | S | D | vade metni | lapsedAt | learnedAt |
|---|---|---|---|---|---|
| Yeni kelime ilk yanlış (hatırlama/tanıma) | 0,4 / 0,3 | 7,0 | "Yarın" | bugün | — |
| S=30 vadesinde, iki ayrı turda D→Y ya da Y→D | 11,40 | 5,85 | "Yarın" | bugün | — |
| S=30 vadesinde, üç ayrı turda 1 Y (30 dk dışında, her sıra) | 56,05 | 5,34 | "56 gün sonra" | — | bugün |
| S=30 vadesinde salt doğru | 82,09 | 5,0 | "82 gün sonra" | — | bugün |
| Dün yanlış, bugün doğru | 13,38 | 5,72 | "13 gün sonra" | temizlenir | — |
| S=300 yanlış → ertesi gün doğru | 51,96 → 53,43 | 5,85 → 5,72 | "Yarın" → "53 gün sonra" | bugün → — | değişmez |
| Tanımada şansla doğru (S=10) | 20,90 (<21) | 5,0 | **"20 gün sonra"** (çıpa 04:00'e oturduğu için tam 21 değil) | — | yazılmaz |
| Zayıf kelime, tanımada 1. farklı günde doğru | S büyür, **vade değişmez** (`lapsedAt+1 gün` sabit) | — | ertesi gün gerçek zaman geçince metin **"Bugün"**a döner (bu, aynı sabit tarihin bugüne denk gelmesinden; "Yarın" yalnızca henüz o tarihe ulaşılmamışken) | kalır | — |
| …2. farklı günde tanıma doğrusu | S büyür, vade artık ileri | — | "13 gün sonra" | temizlenir | — |
| Olgun kelime (S≥21), yalnızca tanımayla her gün doğru | **tamamen donuk** (S/D/anchor/vade değişmez) | — | vadesi geldiğinde gerçek zamanla `isDue` olur, "X gün gecikti" | — | — |
| Olgun-olmayan (S<21) kelime, yalnızca widget'la her gün doğru | S büyür (20,9'a kadar), **çıpa ilerlemez**, vade eski çıpa+yeni S | — | vadesi gerçek zamanda gelir, `isDue` olur, akşam hatırlamaya düşer | — | — |
| İki cihaz: A yanlış, B (görmeden) 2 doğru; eşitleme sonrası | 56,05 (eksiksiz sonuç) | 5,34 | "56 gün sonra" | — | bugün |
| Log silme (geri alma) | silmeden önceki duruma birebir | | | | |

### 7.2 Zorunlu birim testleri

**A (replay motoru + önbellek + göç):**
- `replay` saf/deterministik; log ekleme sırası sonucu değiştirmez; ikincil sıralama (yanlış→mod→not)
  eşit-zamanlı loglarda belirlenmiş; gelecekteki log oynatılmaz.
- Oran + grup + 30 dk kapısı (saniyeyle, tam 1800 sn sayılır).
- **Tanıma + S<21**: S büyür (20,9 tavanlı), anchorAt DEĞİŞMEZ, vade = eski anchorAt+yeni S (v7'nin
  ana testi — 14-simulasyon-v6 Y1'in kapandığını doğrular).
- **Tanıma + S≥21**: tamamen donuk (S/D/anchorAt/dueDate değişmez).
- Zayıflık temizleme (üretim 1 farklı gün, tanıma 2 farklı gün); donuk günde de temizleme çalışır.
- Yeni önbellek okuyucuları: `isLapsed`/`memory(at:)`/`isLearned`/`isDue` doğru okunuyor
  (`StudySession`, `Components.MemoryRing`, `WordsWindow`, `GlanceQuiz`, `MacSettingsView`,
  `SettingsView`, `WeeklySummaryView` üzerinden — bunların hepsi `Word`in yeni tanımını otomatik
  doğru okur, ayrı kod değişikliği gerektirmez; testler bunu doğrular).
- Göç: `reviewCount==0` kelime göçe girmez; **bayat önbellekle göç** (taban alındıktan sonra gelen
  eski tarihli bir log yok sayılır, yeni tarihli bir log oynatılır); `baseAt` idempotent; zayıf
  tabanda `baseDueDate = göç anı` (sahte "gecikti" metni yok); `baseLearnedAt` korunur ve "2 farklı
  gün" şartı baştan sağlanmış sayılır; farklı tabanlı `StoreMaintenance` birleştirmede en eski taban
  kazanır.
- `word == nil` bir log sonradan bir kelimeye bağlanınca (ör. paylaşım eklentisinden gecikmeli
  eşitleme) o kelimenin önbelleği bir sonraki yeniden hesaplamada güncellenir.
- İki cihaz: farklı log kümeleriyle başlayan iki `replay`, birleşik log kümesiyle aynı sonuca yakınsar.
- Geri alma = log sil + yeniden `replay`.

**B/C:** v6 ile aynı (`GameDeck`, çeldirici, `AnswerChecker`, `MatchBoard`, `LetterPuzzle`,
`ClozeSentence`; tur özeti ikonu/"önce"-"sonra", `MemoryRing` turuncu kuralı, Mac hub, "son görülme").

---

## 8. Uygulama parçaları

**A önce biter**, **B ve C paralel**.

**A — Replay motoru + önbellek + göç + testler:** `Shared/Word.swift` (`lapsedAt` + 7 `base*` alanı,
`isLapsed`/`memory(at:)`/`isLearned`/`isDue` yeni tanımları), `Shared/Logic/Memory.swift` (`replay`,
§2.4–§2.7), `Shared/Logic/ReviewRecorder.swift` (log ekler + o kelimeyi yeniden hesaplar; eski
"öğrenilmiş değilse `learnedAt`'i sil" dalı kaldırılır), `Shared/Logic/MemoryMigration.swift`
(`fillLearnedDates` kaldırılır, göç §6'ya göre yeniden yazılır), `Shared/Logic/StudySession.swift`
(geri alma = log sil + yeniden hesapla; `isWeak` çağrıları `isDue`'ya döner — satır 124/147/213/366),
`Shared/Logic/GameRound.swift` (`GameRound.summaryEntries`), `Shared/Logic/WordPicker.swift`,
`Shared/Logic/GameMode.swift` (yalnızca üst kısım), `Shared/Logic/StoreMaintenance.swift`
(en eski taban), `ReminderPlanner`/`ReminderScheduler`, `KelimeDefteri/Views/WordDetailView.swift`
("son görülme"), `KelimeDefteri/Views/ContentView.swift` (`scenePhase` → bütün defter yeniden hesap),
`Mac/MacGamesView.swift` (menü penceresi açılışı → bütün defter yeniden hesap), **`Shared/Components.swift`**
(`MemoryRing`in okuduğu `isWeak`→`isDue`/`isLapsed`), **`Mac/WordsWindow.swift`** (satır 37,
`isWeak`→`isDue`), **`Shared/Logic/GlanceQuiz.swift`** (widget sorusu ve kilit ekranı özeti, kendi
sürecinde tek-kelime `replay`), **`Shared/Logic/WeeklySummary.swift`** (`learnedAt` artık göçte
sıfırlanmadığı için "bu hafta öğrenildi" sayımı doğru okur), **`Mac/MacSettingsView.swift`**,
**`KelimeDefteri/Views/SettingsView.swift`** — bu sonuncu beşi `Word`in yeni tanımını otomatik,
kod değişikliği gerekmeden doğru okur; burada yalnızca kapsamda olduklarını ve ayrı bir sahibe
ihtiyaç duymadıklarını belirtmek için listeleniyor (15-denetim-v6 Orta).

**B — Tur içi oyun mantığı:** v6 ile aynı dosya listesi (A bittikten sonra).

**C — Özet/gösterge + Mac:** v6 ile aynı dosya listesi.

---

## 9. Kullanıcı kararı gereken noktalar

1. **Tanıma oyunlarında yanlış kelime tur içinde yeniden sorulsun mu?** Varsayılan: **Hayır**.

2. **Yeni arayüz öğeleri — Harfleri Diz "İpucu", Ters Yön proaktif ipucu?** Varsayılan: **Hayır**.

3. **Aynı gün, aynı desteyi tekrar oynarken not gösterilsin mi?** Varsayılan: **Evet** — "Bu tur
   bugünün diğer cevaplarıyla birlikte değerlendiriliyor."

4. **Günde tam 1 doğru + 1 yanlış (oran tam 1/2) `again` mi `hard` mı sayılsın?**
   Güncel sayılar (%90 bilen kullanıcı, her gün k oyun, 120 gün, 500 tohum, canlı "Öğrenildi"):
   **1 oyun → 241/500, 2 oyun → 102/500, 3 oyun → 366/500** (2 oyun belirgin biçimde en kötü durum;
   3 oyunda oran kuralı zaten toparlanma şansı veriyor).
   Önerilen varsayılan: **`again`de kalsın** (eşik değişmesin). Artı: kural tek ve basit kalır; en
   yaygın örnek (S=30, iki cevaptan biri yanlış) kullanıcının asıl şikâyetini en güçlü şekilde çözer.
   Eksi: günde tam iki kez çalışan, iyi bilen bir kullanıcı için beklenmedik bir sertlik — ama
   "vadesi geldiğinde 1 oyun" kullanıcısında bu etkinin pratik karşılığı küçük (486–499/500 zaten
   Öğrenildi'ye ulaşıyor); asıl fark yalnızca "her gün zorla 2 kez çalışan" nadir bir kullanım
   deseninde görülüyor.
