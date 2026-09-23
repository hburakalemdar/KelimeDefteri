# Spec: Hafıza Motoru ve Tur İçi Oyun Mantığı — Yeniden Tasarım (Motor 2)

**Sürüm 10 — kodlamadan önceki son sürüm, kendi başına yeterli.** Motor, kelimenin durumunu artımlı
alanlar yerine bir tabandan sonraki bütün cevapların gün gün yeniden oynatılmasıyla hesaplayan bir
mimari kullanır (`replay(taban, loglar, now) -> MemoryState`). Bu sürüm, v9 denetiminin bütün
maddelerini (1 Yüksek, 7 Orta, 3 Düşük) kapatır: tur özeti veri yapısının parça sınırı (mevcut
`StudySession.RoundEntry`/`RoundSummaryView.Entry` zaten doğru tasarlanmış, yeniden kurulmuyor —
bkz. §4.1), tanıma yanlışında çıpanın davranışı (§1.3/§2.5), Ters Yön eşanlam kontrolünün A/B sınırı
(§3.2), `dailyCount`in tek yerde uygulanması (§2.6), widget/bildirimin `isDue(at:)` kullanımı ve yeni
kelime davranışı (§2.8), kullanıcıya görünen değişikliklerin ayrı listesi (§4.5), `learnedAt`in taban
sınırındaki belirsizlikler ve `dueDate` biriminin netleştirilmesi (§2.7), kod adı düzeltmeleri (§2.9)
ve §7.1'deki doğrulama iddiasının kapsamı. §9, sorulardan **kararlara** çevrildi. Bu belge önceki
sürümlere referans vermeden tek başına uygulanabilir.

Kaynaklar (tarihçe): `scratchpad/motor/1-ilerleme.md` … `19-denetim-v8.md`, `18-simulasyon-v8.md`,
`20-denetim-v9.md`.
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
3. Tanıma cevapları **doğru/zor bilindiğinde çıpayı hiçbir zaman ilerletmez** (büyüme hesabının
   başlangıç anını): kelime henüz olgunlaşmadıysa (S<21) S'yi büyütebilir (tavan 20,9) ve vade eski
   çıpadan yeniden hesaplanır (zaman ilerletilmeden, yalnızca S değiştiği için değişebilir); kelime
   zaten olgunsa (S≥21) hiçbir şeyi değiştirmez. **Tanımada yanlış bilinen gün bu kuralın dışındadır:**
   yanlış her zaman güçlü bir sinyaldir (hangi oyunda olursa olsun kelime o gün gerçekten
   hatırlanamamıştır), bu yüzden çıpayı üretimdeki gibi bugüne ilerletir (§2.5, YANLIŞ dalı — grup
   ayrımı yalnızca "kaynak" cevabın notu/oyunu için değil, bu dalda hiç bakılmaz). Olgun bir kelime
   zayıflarsa (S≥21 kalarak), zayıflığını **yalnız üretim** kaldırabilir — tanıma tek başına
   kaldıramaz.
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
5. Gün işlenmesi: yanlış → zayıflat + çıpayı bugüne ilerlet + ertesi gün 04:00'e sabitle (kaynak
   üretim mi tanıma mı olduğuna bakılmaz — yanlış her zaman çıpayı ilerletir); değilse büyüt —
   tanıma günü (yalnız doğru/zor bilinen gün) çıpayı hiç ilerletmez (S<21'de yalnız S/D büyür, S≥21'de
   hiçbir şey değişmez); zayıflık üretimle (S seviyesi fark etmez) ya da (yalnız S<21'de) iki farklı
   günde tanımayla temizlenir (§2.5).
6. Büyüme/ceza formülleri sabit, `t` tam gün, çıpa = `anchorAt`; **yeni kelimenin ilk cevabı** ayrı,
   sabit bir tabloyla belirlenir (S=0'dan büyüme formülü tanımsız olduğu için) (§2.6).
7. `learnedAt` = replay'de şartın ilk sağlandığı **günün 04:00'ü**; göç tabanı öğrenilmişse şart
   baştan sağlanmış sayılır (§2.7).
8. Vade formülü tek kural (`word.isDue(at:)`); hangi seçicinin bunu nasıl kullandığı §2.8'de tek tek
   listelenir — Günlük Tekrar yalnızca `isDue`, widget/bildirim önce `isDue` sonra (boşsa) ağırlıklı
   yedek (yeni hariç, §9 Kararlar/3), "ağırlıklı" oyunlar ve Yine de Çalış `isDue`e hiç bakmaz.
9. Önbellek: cevap sonrası o kelime; öne gelince/Mac penceresi açılınca bütün defter; widget kendi
   sürecinde tek kelime — hepsi önce o kelimenin göçünü tetikler (`MemoryMigration.migrateBaseIfNeeded`,
   kutu göçünden farklı bir fonksiyon, §2.9, §6).
10. Sıralama: eşit zamanda yanlış→mod→not; gelecekteki log oynatılmaz; 30 dk kapısı saniyeyle, `<` (§2.10).

### 2.1 Mimari: taban + loglardan yeniden oynatma

    func replay(base: BaseState, logs: [ReviewLog], now: Date) -> MemoryState

- `logs`, `date > base.at` VE `date <= now` olanlar, §2.10'daki sırayla işlenir, `DayBoundary`
  gününe göre kümelenir.
- Her gün için §2.4 (günün notu) ve §2.5 (günün işlenmesi) sırayla uygulanır; çıkan `MemoryState`
  bir sonraki günün girdisidir; son günün çıktısı `replay`in sonucudur.
- `MemoryState = { stability, difficulty, dueDate, lapsedAt: Date?, learnedAt: Date?, anchorAt: Date }`.
  **`dayGrade` alanı yok** — v9 taslağı tur özeti ikonu için `MemoryState`e bir `dayGrade` alanı
  eklemeyi planlıyordu, ama §4.1'de açıklandığı gibi tur özeti ✓/✗'i günün notundan değil turdaki ilk
  cevaptan okuyor (kod zaten böyle), bu yüzden `replay`in dışarı taşıması gereken ekstra bir "son
  günün notu" değeri yok; günün notu yalnızca `replay`in **içinde**, §2.4/§2.5'in bir günden diğerine
  geçerken kullandığı geçici bir değerdir.

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
**`!isNew && isDue(at: now)`** kullanır (yeni kelime `dueDate = .distantPast` olduğu için, `isNew`
hariç tutulmazsa yanlışlıkla "zayıf" sayılırdı) — Günlük Tekrar'ın seçtiği kümeyle (yeniler hariç)
birebir aynı kelimeler. "Güçlü" = `!isNew && !isDue(at: now)`. "Yeni" = `isNew`; üçü birbirini dışlar.
**Not:** bu sayaç `isDue` kullanır, `isLapsed` DEĞİL — kelime rozeti/halkasının turuncu olması
(`isLapsed`) için bkz. §4.2 ve §4.5'teki "zayıf" kelimesinin tek tanımı; ikisi kasıtlı olarak farklı
kümeler olabilir (bir kelime zayıf olup vadesi henüz gelmemiş olabilir).

`anchorAt`in ve `learnedAt`in "gün" değeri her zaman o günün **04:00'üdür** (cevabın gerçek saati
değil) — `DayBoundary.start(of:)`in kendisi. Bu, §2.6'daki `t` hesabının (iki `anchorAt` arasındaki
tam gün farkının) ve §2.7'deki "learnedAt" tarihinin gösterimde her zaman 04:00'a denk gelmesini
sağlar; ayrıntı sayfasında/testte kıyaslama yaparken bu sabit kullanılmalı.

### 2.3 Gün sınırı

    DayBoundary.start(of: date) = 04:00 (saat < 04:00 ise bir önceki günün 04:00'ü)

Gün farkı takvim bileşeniyle alınır (`Calendar.dateComponents([.day], ...)`), `timeInterval/86400` ile değil.

### 2.4 Günün notu

    birincilCevaplar(gün) = o günün logları: bütün yanlışlar + öyle bir doğru ki, kendisinden önce
      aynı gün içinde 30 dakikadan AZ önce (< 1800 sn, §2.10) gelmiş bir yanlış YOKTUR.
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

**Yeni kelimenin ilk günü** (henüz hiç `stability` yok, tabanı da yok — `baseStability == 0`
`baseAt == .distantPast`): büyüme/ceza formülleri `S=0`da tanımsız olduğu için (`S^−0.2` vb.) ilk
gün ayrı, sabit bir tablodan başlar; bu tablo günün notuna göre seçilir (yukarıdaki §2.4'teki
"kaynak" cevabının notu ve grubu):

    S₀ = [again: 0.4, hard: 1.2, good: 3.0, easy: 8.0][not] × ağırlık   (en az 0.3)
    D₀ = [again: 7.0, hard: 6.0, good: 5.0, easy: 3.5][not]
    anchorAt₀ = o günün 04:00'ü

(Bu değerler koddaki `Memory.firstStability`/`Memory.firstDifficulty` dizileriyle birebir.) İlk gün
yalnızca tanıma cevabı içerse bile (grup=tanıma, ör. widget bir kelimeyi ilk kez soruyor) `anchorAt₀`
yine o günün 04:00'ü olarak yazılır — `MemoryState.anchorAt` hiçbir zaman `nil` olamayan, zorunlu bir
alandır; "tanıma çıpayı ilerletmez" kuralı (§2.5, aşağıda) yalnızca **var olan** bir çıpayı korumakla
ilgilidir, çıpanın hiç var olmaması durumuyla değil. İlk günden sonraki her gün normal kurala (aşağıda) döner.

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

— *neden (S≥21 zayıf kelimede yalnız üretim):* Bu kural olmadan, S=300'den 51,96'ya düşmüş bir
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

**Yeni kelime sınırı — tek yerde uygulanır, ikinci bir sınır eklenmez:** günde en fazla 5 yeni
kelimenin tanıtılması, mevcut `Shared/Logic/StudySession.swift`teki `dailyCount(weak: Int, new: Int)
-> (weak: Int, new: Int)` fonksiyonunun `min(new, dailyNewLimit, ...)` satırıyla **zaten** sağlanır;
imzası değişmez, yeni bir `alreadyIntroducedToday` parametresi **eklenmez**. Bu, ayrı bir sayaç
gerektirmez çünkü kelime bir kez cevaplandığında `isNew` false olur ve `dailyNewWords`in seçtiği
havuzdan kendiliğinden çıkar — "bugün kaç tanesi tanıtıldı" sorusunun cevabı zaten `!word.isNew`
durumunda saklıdır, ayrıca sayılmaz.

`ReminderPlanner.plan` bu sınırı **gelecek 7 gün için de** kullanır (§2.8), ama yeni kelime yalnızca
**bugünün** (offset 0) planına girer: `offset > 0` olan (yarından itibaren) günler için `dailyCount`e
verilen `new` parametresi **0**dır (`newCount` yalnızca `offset == 0`da geçirilir, sonraki günlerde
`0`). Gerekçe: yeni kelime tanıtımı yalnızca Günlük Tekrar'ın bugün açılmasıyla gerçekleşir; ileri
günler için "kaç yeni kelime sorulacak" sorusunun anlamlı bir cevabı yoktur (kullanıcı yarın açmadan
kaç yeni kelimenin tanıtılacağı bugünden bilinemez), bu yüzden ileri günlerin bildirim sayısı yalnızca
o güne kadar vadesi gelecek çalışılmış (zayıf) kelimeleri sayar.

### 2.7 `learnedAt`

    learnedAt = replay boyunca, şu şart İLK KEZ sağlandığı günün tarihi:
      stability ≥ 21 VE lapsedAt == nil VE bugüne kadar YANLIŞ olmayan en az 2 FARKLI günde üretim
      katkısı var (bu iki gün ardışık olmak zorunda değil).
    Şart bir kez sağlanınca bir daha kontrol edilmez (o günün tarihinde sabit kalır).
    isLearned (canlı rozet) = stability ≥ 21 && lapsedAt == nil — replay'in son gündeki durumundan
    doğrudan okunur, learnedAt'ten AYRI.

**"Üretim katkısı" ZOR günü de sayar:** şart "YANLIŞ olmayan" diyor, yani hem ZOR (0<oran≤1/3, doğru
sayılır ama zayıflatmaz) hem EN İYİ DOĞRU günü, grup üretimse "1 farklı gün" olarak sayılır — yalnızca
dayGrade == YANLIŞ olan günler bu sayıma hiç girmez.

**Taban, "kaç farklı gün" sayısını değil yalnızca "şart sağlandı mı"yı taşır:** `baseLearnedAt`
ikili bir bayraktır (dolu/boş), "1/2 farklı gün" gibi kısmi bir ilerlemeyi saklayan ayrı bir alan
**yok** — 7 taban alanına yeni bir sayaç eklenmez. Taban öğrenilmişse (`baseLearnedAt != nil`),
replay bu tarihle başlar ve "2 farklı gün" şartı **taban itibarıyla zaten sağlanmış** sayılır. Taban
öğrenilmemişse (`baseLearnedAt == nil`), "farklı gün" sayımı **sıfırdan**, yalnızca `replay`in
işlediği (`date > baseAt`) loglardan başlar — tabandan önceki günlerde varsa bile hiçbir kısmi
ilerleme taşınmaz. Bu, göçten hemen sonraki birkaç günde (taban öncesinde zaten 1 üretim günü
gerçekleşmiş bir kelimenin) `learnedAt`in gerçekte olması gerekenden bir gün geç görünmesine yol
açabilir; kabul edilebilir bir yaklaşıklık (bkz. §6'daki genel göç yaklaşıklığı ilkesi, aynı
kategoride bir sadeleştirme).

**`dueDate` birimi ve S<1 durumu:** `dueDate = anchorAt + stability gün` ifadesindeki "gün" 86.400
saniyelik sabit bir birimdir (`anchorAt + stability × 86400` saniye, kesirli S'yi de doğru ekler —
ör. S=20,9); bu, `t`nin hesaplandığı takvim-bileşenli gün farkından (§2.3) **farklı** bir birimdir,
ikisi karıştırılmamalı. Bu dalda (`lapsedAt == nil`, yani ZOR/EN İYİ DOĞRU) S'nin 1'in altına inmesi
**mümkün değildir**: dal yalnızca doğru/zor bilinen günlerde çalışır, ilk günün en düşük büyüme
değeri (hard) 1,2'dir ve sonraki her büyüme çarpanı ≥1'dir (tanıma tavanı da `min(S',20,9)` olduğu
için hep ≥ önceki S0); S<1 yalnızca "again" (yanlış) durumunda üretilir, o da her zaman sabit
`dueDate = bugün + 1 gün` dalına girer (§2.5, YANLIŞ dalı), S-tabanlı formüle hiç girmez. Dolayısıyla
`anchorAt + stability gün` ifadesinde S her zaman ≥1 gündür.

`ReviewRecorder`deki eski "öğrenilmiş değilse `learnedAt`'i sil" dalı ve
`MemoryMigration.fillLearnedDates` **tamamen kaldırılır**: `learnedAt` yalnızca `replay`in çıktısı.

### 2.8 Seçim

    isDue(word, now) = word.dueDate <= now

Üç tür seçici var (widget/bildirim, §9 Kararlar/3 kararıyla, ikisi arasında bir karma seçici oldu);
hangi kelimenin **hangi tür** seçiciye ait olduğu tek tek:

**"Vadeye bakan" seçiciler** — yalnızca `isDue(at: now)` olan kelimeler arasından seçer, bugün
zayıflayan kelimeyi doğal olarak yarına kadar bir daha almaz:
- **Günlük Tekrar**: `words.filter { !$0.isNew && $0.isDue(at: now) }` (+ en fazla 5 yeni kelime, §2.6).
- **Yeni Eklenenler**: Günlük Tekrar'ın almadığı yeni kelimeler (`isNew`, `isDue`e bakılmaz — yeni
  kelime zaten her zaman "vadeli").
- **Widget** (`GlanceQuiz.question`) ve **bildirim** (`ReminderPlanner`in planladığı soru): **yeni
  kelimeler hiçbir zaman sorulmaz** (`!$0.isNew` her iki aşamada da uygulanır). Sıra: **önce**
  `words.filter { !$0.isNew && $0.isDue(at: now) }` içinden `WordPicker`in mevcut ağırlıklandırma
  fonksiyonuyla (`WordPicker.weight(memory:)`, Çoktan Seçmeli/Eşleştir gibi diğer ağırlıklı seçicilerin
  kullandığı aynı fonksiyon) seçim yapılır. Bu küme boşsa `words.filter { !$0.isNew }` (yeni hariç
  bütün defter) içinden yine ağırlıklı seçilir — **widget/bildirim asla boş kalmaz**, "Bütün kelimeler
  güçlü" durumu yalnızca `!isNew` kümesi tamamen boşsa (defterde yeni olmayan hiç kelime yoksa) ya da
  seçenek üretimi başarısız olursa (`GlanceQuiz.minimumWords`in altında kalırsa) görünür. Bildirim
  için bu seçim, `word.dueDate <= reminder.fireDate` şartıyla, **`ReminderScheduler` planlama anında**
  (bildirimin gönderilmesinden önceki gün) yapılır — yani `isDue(at: fireDate)` kullanılır, `now`
  değil: `ReminderScheduler.refresh` her arka plana geçişte 7 gün ilerisi için plan kurar
  (`ReminderPlanner.plan`), her bir `reminder.fireDate` için `GlanceQuiz.question(..., now:
  reminder.fireDate, ...)` çağrılır (`ReminderScheduler.swift:75-77`); kullanıcı bildirime günler sonra
  dokunsa bile soru o anda sabitlenmiş kalır (mevcut davranış, değişmedi).
  **Yeni kelimenin dışlanması bir davranış değişikliği:** önceki sürümde yeni kelimenin vadesi hep
  `.distantPast` olduğu için (`isDue` her zaman true) widget/bildirim neredeyse hep yeni kelime
  sorardı ve günlük 5 yeni kelime bütçesini tüketirdi; artık widget/bildirim yalnızca çalışılmış
  (zayıf ya da güçlü) kelimeler arasından sorar, yeni kelime tanıtımı yalnızca Günlük Tekrar/Yeni
  Eklenenler üzerinden olur (bkz. §4.5).
- **Yine de Çalış**: `isDue` kullanmaz — kelimeler zaten güçlü olduğu senaryo için tasarlandığından
  `isStruggling` (son 14 günde en az %40 yanlış) ve `weakest` (hafızası en düşük) sıralamasıyla
  seçer; bu **kasıtlı bir istisna** (aşağıdaki "ağırlıklı, bütün defterden seçen" seçicilerle aynı
  mantık: kelimeler vadeli olmasa da tekrar sunulabilir).

**"Ağırlıklı, bütün defterden seçen" oyunlar** — `isDue`e bakmadan bütün defterden ağırlıklı seçer,
bugün yanlış yapılan kelimeyi de alabilir (kasıtlı, §2.4'ün oran kuralına toparlanma şansı verir; 30
dakikalık kapı hile riskini zaten kapatıyor): **Hızlı Tur, Çoktan Seçmeli, Eşleştir, Boşluğu Doldur,
Ters Yön**.

Ayrı bir "bugün yanlış yapılan hiçbir yerde seçilmesin" filtresi yoktur.

### 2.9 Önbellek — ne zaman ve nasıl yeniden hesaplanır

Tek-kelime göç fonksiyonunun adı **`MemoryMigration.migrateBaseIfNeeded(word:)`** — kodda zaten var
olan, kutudan hafıza değerlerine geçişi yapan `MemoryMigration.migrateIfNeeded(context:)` ve
`migrate(_:)` (Leitner kutusu göçü, farklı bir iş) ile **isim çakışmasın diye kasıtlı olarak farklı
ad**. İki göç ayrı ve sıralı: bir kelime önce (varsa) kutu göçünden (`migrate(_:)`, mevcut kod,
değişmedi) geçer — bu, `stability`/`difficulty`/`lastReviewedAt`i Leitner kutusundan türetir — ancak
ondan **sonra** `migrateBaseIfNeeded(word:)` çalışır (taban göçü, §6); böylece taban göçü, kutu
göçünün ürettiği güncel önbellek değerlerini (varsa) doğru okur. Kutu göçü zaten yıllardır çalışan,
idempotent bir adım; sırası değişmez.

- **Bir cevap kaydedildiğinde**: önce o kelime için `migrateBaseIfNeeded(word:)`, sonra `replay` ile
  önbellek güncellenir.
- **iOS: `scenePhase == .active` olunca** (`ContentView.swift:70`, mevcut kutu-göçü çağrısının
  yanına eklenir): **bütün defter**. `MemoryCache.refreshAll(in: ModelContext)` (yeni dosya
  `Shared/Logic/MemoryCache.swift`) bütün `ReviewLog`ları tek sorguyla çekip kelimeye göre gruplar,
  her kelime için önce `migrateBaseIfNeeded`, sonra `replay` çalıştırır — ama **yalnızca hesaplanan
  yeni değer eskisinden farklıysa** ilgili alanlara yazar (gereksiz iCloud yazımı/çakışma
  olmasın diye; çoğu kelimenin önbelleği zaten güncel olduğu için bu, pratikte defterin küçük bir
  kısmına yazma anlamına gelir).
- **Mac: menü penceresi açılınca (`MacGamesView.swift:47`), Kelimelerim (`WordsWindow`) ya da
  Ayarlar (`MacSettingsView`) penceresi açılınca**: aynı `MemoryCache.refreshAll`. Periyodik (ör.
  saatte bir) bir zamanlayıcı **eklenmez** — pencereler zaten sık açılıp kapanıyor, gözlemci
  (aşağıda) CloudKit tarafını kapsıyor, ek bir zamanlayıcı gereksiz karmaşıklık olurdu.
- **Uzak (iCloud) değişiklik bildirimi**: `MemoryCache.observeRemoteChanges(context:)`
  (`Shared/Logic/MemoryCache.swift`), `Shared/SharedStore.swift`teki **`SharedStore.result`**in
  `.success` dalında, **yalnızca `!isExtension` iken** eklenir (kod adı düzeltmesi: `SharedStore`de
  `makeContainer()` diye bir fonksiyon ya da `KelimeDefteriApp.init`/`KelimeDefteriMacApp.init`e özel
  bir kurulum noktası yok — hem iOS uygulaması hem Mac uygulaması hem de eklenti/widget aynı
  `SharedStore.result`i çağırıyor, `!isExtension` koruması zaten mevcut kod deseni, §2.9'daki
  tek-kelime göçünden farklı olarak). **`!isExtension` widget'ı da kapsar** (widget'lar da bir uzantı
  paketidir, `Bundle.main.bundlePath.hasSuffix(".appex")`), bu yüzden gözlemci ana uygulamada ve
  Mac'te çalışır, **Paylaş eklentisinde de widget sürecinde de çalışmaz** — ayrı bir widget-özel bayrağa
  gerek yok. SwiftData'nın uzak değişiklik bildirimini dinler, gelince `refreshAll` çağırır (yine
  yalnızca değişen alanlara yazarak). *[Cihazda doğrulanacak: bu bildirimin CloudKit içe aktarımında
  güvenilir geldiği gerçek cihazda teyit edilmeli.]*
- **Widget/bildirim**: kendi sürecinde (`GlanceQuiz`/`ReminderQuiz`), yalnızca cevapladığı kelime
  için önce `migrateBaseIfNeeded(word:)`, sonra `replay`. `SharedStore`'un bazı kurulum adımlarını
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

Hatırlama/Ters Yön oyunları yanlış bilinen kelimeyi tur içinde en az 2 kart arayla tekrar sorar (yer
yoksa sormaz, kelime turdan "biten" sayılır); Çoktan Seçmeli, Eşleştir, Boşluğu Doldur, Harfleri Diz
ve Hızlı Tur karışık tur içinde tekrar sormaz. (Bu, tur-içi-yeniden-sorma davranışı; §2.4a'daki
üretim/tanıma ayrımından bağımsız bir kural — Harfleri Diz günün notu hesabında **üretim** sayılır,
ama tur içinde Günlük Tekrar gibi yeniden sormaz; ikisi farklı sorulara cevap veriyor.) Sayaç/ilerleme çubuğu
`kalan = wordCount − finishedWordCount` üzerinden gösterilir; bir kelime doğru bilinerek ya da
yeniden sorma hakkı biterek "biten" sayılır — yanlış cevapla geri gitmez, erken dolmaz.

### 3.2 Diğer tur içi kurallar

- `GameDeck`in "en az 4 kelime" açılma koşulu ham kelime sayısına değil **farklı anlam sayısına**
  bakar (ortak Türkçe anlamlı kelimeler tek kümede sayılır).
- Çeldiriciler (Çoktan Seçmeli, Boşluğu Doldur) anlam-tabanlı seçilir: doğru cevapla ortak Türkçe
  anlamı olan kelime asla çeldirici olmaz.
- Ters Yön'de ortak anlamlı iki kelimeden biri yazılırsa **"Doğru, ama bu kartta aranan: X"**
  mesajı gösterilir, not `hard` sayılır (yeni bir arayüz öğesi eklemeden — proaktif kart ipucu için
  bkz. §9 Kararlar/1: eklenmeyecek). Sınır, imza değişikliğiyle birlikte **A'ya** verilir, mantık
  **B'ye**:
  - **A** (`Shared/Logic/ReverseChecker.swift`ın imzasını genişletir + `StudySession.swift`):
    `Verdict`e yeni bir `.synonymOf(String)` durumu ekler, `check`in imzasını
    `check(_:expected:in words: [Word]) -> Verdict` yapar (kodda bugün `check(_:expected:)` var, `in:`
    parametresi yeni). A bu aşamada eşanlam tespitini **saplama (stub)** olarak bırakır — `in:` alır
    ama kullanmaz, hiçbir zaman `.synonymOf` döndürmez (mevcut exact/typo/wrong davranışı aynen
    kalır); A'nın `StudySession`'daki "hangi `Verdict`e karşılık hangi mesaj/not" eşlemesi testleri bu
    saplamayla tam çalışır ve B'yi beklemez.
  - **B** (`Shared/Logic/ReverseChecker.swift`ın gövdesini doldurur): saplamanın yerine gerçek eşanlam
    tespitini yazar (defterde aynı Türkçe anlama sahip başka bir İngilizce kelime var mı, `words`
    üzerinde saf bir arama) — yalnızca `check`in **gövdesini** değiştirir, imzayı ya da `Verdict`
    durumlarını bir daha değiştirmez, A'nın zaten geçen testleri bozulmaz.
  Test: A tarafında mesaj/not eşlemesi (saplamayla), B tarafında gerçek eşanlam tespiti ayrı ayrı.
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

**Aynı gün, aynı desteyi tekrar oynama notu** (§9 Kararlar/1): "Bu tur bugünün diğer cevaplarıyla
birlikte değerlendiriliyor." — bu turun cevapları (30 dakikalık kapı hariç) günün oranına normal
şekilde girer.

---

## 4. Tur özeti ve göstergeler

### 4.1 İkon, "önce"/"sonra" — mevcut yapı korunuyor, yeniden kurulmuyor

**Bu bölüm, v9'da planlanan `dayGrade`/`EntrySnapshot` tabanlı yeniden tasarımı iptal eder.** v9
denetimi, bu yeniden tasarımın (`RoundSummaryView.Entry`i `GameRound.summaryEntries`e taşımak) A'nın
tek başına derlenmesini engellediğini ve B/C'nin beş oyun görünümünü kırdığını tespit etti (Yüksek
bulgu). İncelemede ortaya çıktı ki **mevcut kod zaten kullanıcı kararı §9 Kararlar/4'ün istediği davranışı
uyguluyor** — yeni bir veri yapısına gerek yok:

- Kodda bugün **iki** paralel özet-satırı türü var: `StudySession.RoundEntry(word:memoryBefore:
  firstCorrect:)` (hatırlama akışı — Günlük Tekrar, Ters Yön, Hızlı Tur'un hatırlama sorusu) ve
  `RoundSummaryView.Entry(word:before:correct:)` (özetin kendi görünüm tipi). İkisi de **kelime
  başına yalnızca turdaki ilk cevabın doğruluğunu** (`firstCorrect`/`correct`) tutar — günün notunu
  (`dayGrade`) değil. **Bu, §9 Kararlar/4'ün istediği tam olarak budur** ("✓/✗ = bu turdaki ilk
  cevap, günün notu değil"), dolayısıyla `Entry`e yeni bir `dayGrade` alanı **eklenmez**.
- "Sonraki tekrar" metni zaten `entry.word.dueDate`den, yani **canlı** (turdan sonra, o kelime için
  o günün gerçek notuyla `replay`den hesaplanmış) değerden okunuyor (`RoundSummaryView.swift`
  `memory(_:)` fonksiyonu, `let due = entry.word.dueDate`) — bu da §9 Kararlar/3'ün ikinci
  şartını ("sonraki tekrar metni günün sonucunu yansıtır", §9 Kararlar/4) zaten karşılıyor, ayrı bir
  `after` alanına gerek yok.
- Üstteki "x/y doğru" sayısı (`RoundText.summary(correct: entries.count(where: \.correct), ...)`)
  zaten `correct` (=turdaki ilk cevap) üzerinden sayılıyor — "bu turdaki ilk cevaplar" şartını
  karşılıyor, ayrıca bir hesap eklenmez.
- **Sonuç: `RoundSummaryView.Entry`, `StudySession.RoundEntry` ve `GameRound.record`/
  `StudySession.record`'ın bunları dolduran kodu DEĞİŞMEZ.** Mimariyi değiştirmediği için A/B/C
  parça sınırı da basitleşir: her görünüm dosyası (`RecallGameView`, `QuickMixGameView`,
  `ChoiceGameView`, `MatchGameView`, `FillBlankGameView`, `LettersGameView`, `MacStudyView`) kendi
  `RoundEntry`/`round.entries`ini olduğu gibi `RoundSummaryView.Entry`ye çevirir; A'nın diğer parçalar
  (§8) tarafından hiçbir dosyada beklenmesi gerekmez, bu yüzden **A gerçekten tek başına derlenip
  testleri geçer**.
- **"Önce"** (`before`): kelimenin **turdaki ilk cevaptan önceki** önbellek hafızası (`word.memory(at:
  now)`, cevap kaydedilmeden hemen önce okunur — bugün de böyle).
- Yüzde değil, vade/durum metni gösterilir (tur özetinde ve soru kartında sayısal yüzde yok) — bu
  kural değişmedi, `MemoryRing` ve `Leitner.dueDescription` zaten böyle kullanılıyor.

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

### 4.5 Kullanıcıya görünen değişiklikler (v9→v10, sade Türkçe)

Bu liste, motorun iç kurallarından değil, kullanıcının ekranda **göreceği** farklardan oluşur; ayrı
tutulmasının sebebi denetimde bu değişikliklerin belgede dağınık kalması (§9 Kararlar'daki kullanıcı
kararlarıyla karıştırılmamalı, onlar zaten karar; bunlar kararların doğal sonucu):

1. **"Zayıf" artık tek anlama geliyor: `lapsedAt != nil`.** Bir kelime yanlış bilindiğinde hem
   listede hem ayrıntı sayfasında turuncu halka, "Tekrar edilecek" etiketi ve ne zaman tekrar
   sorulacağı ("Yarın" vb.) **her zaman** görünür — bu, kelimenin vadesi henüz gelmemiş olsa bile
   değişmez. Ama "N zayıf" sayacı (Kelimelerim özeti) ve Günlük Tekrar'ın seçtiği küme yalnızca
   **vadesi gelmiş** zayıf kelimeleri sayar/seçer (`isDue`, §2.2). Yani kullanıcı, vadesi henüz
   gelmemiş zayıf bir kelimeyi listede turuncu görebilir ama o kelime "N zayıf" sayısına girmez ve
   Günlük Tekrar'da sorulmaz — bu kasıtlı (kelime zaten ertesi güne kadar sorulmayacak, §2.5).
2. **Tur özetindeki ✓/✗ ve üstteki "x/y doğru" değişmedi** (mevcut kod zaten §9 Kararlar/4'ü
   uyguluyor, bkz. §4.1) — bunu ayrıca belirtmek gerekiyordu çünkü v9 taslağı bunu yanlışlıkla
   "günün notu"na çevirmeyi planlıyordu; v10 bu planı iptal etti.
3. **Widget ve bildirim artık yeni kelime sormuyor** (§2.8, §9 Kararlar/3): önceden widget/bildirim
   genelde yeni kelime sorup günlük 5 yeni kelime bütçesini tüketiyordu; artık yalnızca çalışılmış
   kelimeler arasından soruyor, hiçbir zaman boş kalmıyor (önce vadesi gelenler, yoksa ağırlıklı
   rastgele — yine yeni hariç).
4. **Vadesi geçmiş ve S<21 olan bir kelime, tanımada doğru bilinse bile vadesi hemen değişmeyebilir**
   (§2.5: zayıf kelimede vade `lapsedAt + 1 gün`e sabittir, yalnızca zayıflık temizlenince — üretimle
   1 gün, tanımayla S<21'de 2 farklı günde — normal S-tabanlı vadeye döner). Kullanıcı böyle bir
   kelimeyi tanımada doğru bilse de "Yarın" yazısının hemen değişmediğini görebilir; bu bir hata değil
   (bkz. §7.1 tablosundaki "Zayıf kelime (S<21), tanımada 1. farklı günde doğru" satırı).

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

**Tek-kelime göçü** (`MemoryMigration.migrateBaseIfNeeded(word:)` — kutu göçünü yapan mevcut
`migrateIfNeeded(context:)`/`migrate(_:)`den **kasıtlı olarak farklı adlandırılmıştır**, isim
çakışması olmasın diye; bkz. §2.9), `replay`e giren **her yol** (§2.9: cevap kaydı, bütün-defter
yeniden hesabı, widget/bildirim süreci) tarafından, o kelimeyi kutu göçünden (varsa) **sonra**,
`replay`den **önce** çağrılır. Yalnızca `word.baseAt == nil` iken çalışır (idempotentlik bayrağı,
ayrı alana gerek yok):

1. **`reviewCount == 0`** (kelime hiç cevaplanmamış, ister eski ister v9'da yeni eklenmiş, `logs`u
   ve `lastReviewedAt`i de olmayan kelime dahil): `baseAt = .distantPast` yazılır, **diğer `base*`
   alanlarına dokunulmaz** (varsayılan değerlerinde kalırlar: `baseStability=0`, `baseDifficulty=5`,
   `baseDueDate=.distantPast`, `baseLapsedAt=nil`, `baseAnchorAt=nil`, `baseLearnedAt=nil`) —
   `replay` bütün logları (varsa) baştan işler. **`baseAt == .distantPast` okunduğu her yerde, diğer
   `base*` alanlarının o anki değeri ne olursa olsun yok sayılır** ve taban varsayılan (boş) kabul
   edilir; bu, CloudKit/SwiftData birleştirmesi kayıt bütünüyle değil **alan bazında** olduğunda (bir
   cihaz yalnızca `baseAt=.distantPast` yazarken öbür cihaz aynı ana tam bir taban yazmışsa, ikisi
   karışık birleşebilir) tutarlılığı garantiler — `baseAt` "boş taban" anlamına geldiğinde diğer
   alanlardaki olası "yabancı" değerler hesaba hiç girmez. *[Cihazda doğrulanacak: SwiftData'nın
   CloudKit birleştirme politikasının gerçekte alan mı kayıt mı bazında çalıştığı.]* (Bu adım, "yeni
   sürümde ilk kez cevaplanan kelime" ile "hiç göç etmemiş eski kelime" ayrımını netleştirir:
   `reviewCount==0` her zaman "taban gerekmez" demektir.)
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
çünkü (a) yalnızca eski→yeni sürüm geçiş anını etkiler, bir daha tekrarlanmaz, (b) eski (artımlı)
motor da zaten cihazlar arasında küçük, geçici tutarsızlıklara açıktı, (c) sonraki gerçek cevaplar
durumu hızla gerçek değerine yaklaştırır.

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
açılışta `learnedAt`i kendi (artık geçersiz) mantığıyla yeniden yazar. (Not: bu sürümde yeni bir
`GameMode` etiketi **eklenmiyor** — widget/bildirim cevapları önceki sürümlerde olduğu gibi
`.multipleChoice` adıyla kaydedilmeye devam ediyor, mevcut 7 `GameMode` durumu zaten ağırlıkları
taşıyor; dolayısıyla eski sürümle bu konuda bir uyumsuzluk yok.) Bu yüzden iki cihaz aynı görevde güncellenmeli.

**CloudKit:** `Word`e `lapsedAt`, `baseStability`, `baseDifficulty`, `baseDueDate`, `baseLapsedAt`,
`baseAnchorAt`, `baseLearnedAt`, `baseAt` eklenir. `ReviewLog`'a alan eklenmez.

---

## 7. Test planı

### 7.1 Senaryo tablosu

(D=5 başlangıç, hatırlama ağırlığı 1 aksi belirtilmezse. İlk 10 satır — yeni kelime ilk cevap, S=30/
S=300 senaryoları, 04:00 sınırı, iki cihaz eşitleme, geri alma — `sim_v8.py` ile doğrulandı. **v8/v9'da
eklenen satırlar (aşağıda `*` işaretli: olgun-zayıf kelime ve tanıma-S<21 satırları) `sim_v8.py`
kapsamında DEĞİL — bunlar `sim_v8.py`nin yazıldığı tarihten sonra eklendi; bu satırlar
`sim_v8.py`yle değil, §7.2'deki A'nın `replay` birim testleriyle, uygulamada koşularak
doğrulanacak.**)

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
| *Tanımada şansla doğru (S=10, vadesinde) | 20,90 (<21) | 5,00 | **"11 gün sonra"** (vade = eski çıpa + 20,9; çıpa hiç ilerlemediği için görsel süre S'den kısa görünür) | — | yazılmaz |
| *Zayıf kelime (S<21), tanımada 1. farklı günde doğru | S büyür, **vade değişmez** (`lapsedAt+1 gün` sabit) | — | gerçek zaman geçince metin "Bugün"a döner (§4.5/4'teki kullanıcıya görünen davranış) | kalır | — |
| *…2. farklı günde tanıma doğrusu | S büyür, vade artık ileri | — | **"12 gün sonra"** (çıpa hâlâ ilk yanlışın gününde, ilerlemedi) | temizlenir | — |
| *Olgun kelime (S≥21) zayıfladıktan sonra, iki farklı günde tanıma doğrusu | **temizlenmez** (§2.5a) — yalnız üretim kurtarabilir | — | vade sabit kalır (`lapsedAt+1 gün`); metin gerçek zamana göre değişir: o gün "Bugün", ertesi gün "1 gün gecikti", sonra artan sayıyla | kalır | — |
| *Olgun kelime (S≥21), yalnızca tanımayla her gün doğru | tamamen donuk (S/D/anchor/vade değişmez) | — | vadesi geldiğinde gerçek zamanla `isDue`, "X gün gecikti" | — | — |
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

**Eski testler:** `LearnedDateTests`, `SameDayMemoryTests`, `ReviewFixesTests`, `LogicFixesTests`,
`MemoryTests`, `StoreMaintenanceTests`, `ReviewRecorderTests`, `GameRoundTests` eski artımlı
davranışı (alan alan güncelleme, `updatesMemory`/`clearsLapse` parametreleri, eski `isLapsed`
hilesi) doğrudan test ettikleri için **silinir**; yerlerine A'nın yukarıdaki `replay`-tabanlı
testleri yazılır. `MemoryMigrationTests` **yeniden yazılır** (göç davranışını test etmeye devam
eder, içeriği §6'ya göre baştan yazılır). `MotivationTests:189` (haftalık/günlük hedef sayımı,
eski `learnedAt` sıfırlanma varsayımına dayanıyor) **güncellenir** (artık göçte `learnedAt`
korunduğu için beklenen sayı değişir, bkz. `WeeklySummary`).

`isWeak` kullanan ~20 test **tek bir kurala göre değil, hangi soruyu sorduklarına göre** uyarlanır:
- "Bu kelime **seçilmeli mi** (Günlük Tekrar'a girer mi)?" sorusunu test ediyorsa → **`isDue`**a
  geçer. (Dikkat: bir yanlıştan **hemen sonra** eski testler `isWeak == true` bekliyordu; yeni
  düzende aynı an `isDue == false`tür çünkü vade ertesi güne sabitlenmiştir — bu testler `isDue`nun
  **ertesi gün** `true` olacağını doğrulayacak şekilde güncellenmeli, "hemen" değil.)
- "Bu kelime **şu an zayıf mı görünüyor** (rozet/renk)?" sorusunu test ediyorsa → **`isLapsed`**e
  geçer (bir yanlıştan hemen sonra da `true`dur, `isDue`den farklı olarak zamanla değişmez).

`KelimeDefteriTests` A'nın dosya listesindedir.

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
(`migrateBaseIfNeeded(word:)` tek-kelime taban göçü, §6, kutu göçünden ayrı isim; `fillLearnedDates` kaldırılır),
**`Shared/Logic/MemoryCache.swift`** (yeni dosya: `refreshAll(in:)`, `observeRemoteChanges(context:)`),
`Shared/Logic/StudySession.swift` (geri alma = log sil + yeniden hesapla; `RoundEntry` **değişmeden**
kalır, §4.1; Ters Yön "Doğru, ama aranan: X" mesajının üretimi ve `ReverseChecker`in genişletilmiş
imzasını çağırma, §3.2), `Shared/Logic/ReverseChecker.swift` (**yalnızca imza**: `Verdict.synonymOf`
durumu + `check(_:expected:in:)` parametresi eklenir, gövde saplama kalır — gerçek eşanlam tespiti
B'de, §3.2), `Shared/Logic/GameRound.swift` (`RoundEntry`i dolduran `record`/`adopt` **değişmeden**
kalır, §4.1 — A bu dosyada yeni bir `summaryEntries` fonksiyonu KURMAZ), `Shared/Logic/WordPicker.swift`
(2 kart aralığı; ekstra "bugün yanlış" filtresi yok), `Shared/Logic/GameMode.swift` (yalnızca üst
kısım: etiketler/`weight`), `Shared/Logic/StoreMaintenance.swift` (taban seçimi, eski kopyalama kodu
kaldırılır), `Shared/Logic/ReminderPlanner.swift`/`ReminderScheduler.swift` (`isDue(at: fireDate)`,
§2.8; ileri günlerde `new: 0`, §2.6), `Shared/SharedStore.swift` (tek-kelime göçünün her süreçte
çalıştığından emin olunur; `MemoryCache.observeRemoteChanges` `SharedStore.result`in `.success`
dalına, `!isExtension` korumasıyla eklenir, §2.9), `Shared/Logic/GlanceQuiz.swift` (widget
sorusu/cevabı, kendi sürecinde tek-kelime göç+replay; yeni kelime hariç tutma + boş kalmama, §2.8),
`KelimeDefteri/Views/WordDetailView.swift` ("son görülme"), `KelimeDefteri/Views/ContentView.swift`
(`scenePhase` → `MemoryCache.refreshAll`), `KelimeDefteri/Views/StudyView.swift` (yalnızca
`StudySession.dailyCount`/`averageMemory` okuyan sayaç kısımları — Mac'teki eşdeğeri `MacGamesView`
zaten A'da olduğu için tutarlılık amacıyla buraya eklendi; bu dosyada `RoundSummaryView.Entry` inşası
yok), `Mac/MacGamesView.swift` (menü penceresi açılışı → `refreshAll`), `Mac/WordsWindow.swift`,
`Mac/MacSettingsView.swift` (pencere açılışı → `refreshAll`), `Shared/Components.swift`
(`DeckSummary`/`MemoryRing`in `isDue`/`isLapsed` okuması), `Shared/Logic/WeeklySummary.swift`
(`learnedAt` artık göçte sıfırlanmadığı için doğru sayar), `KelimeDefteri/Views/SettingsView.swift`,
`PreviewData.swift` (`migrateBaseIfNeeded` çağrısı, mevcut kutu-göçü çağrısının yanına — satır 65),
`KelimeDefteriTests` (yukarıdaki eski/yeni test listesi).

**Tur özeti mimarisi değişmediği için (§4.1) burada A→B/C arasında bir devir yok**: her görünüm
dosyası kendi `RoundEntry`/`round.entries`ini bugünkü gibi `RoundSummaryView.Entry`ye çevirir. A'nın
aşağıdaki B/C dosyalarında yapması gereken tek şey, `Word`/`GameMode` alanlarındaki değişikliklerin
(`isWeak` kaldırılması gibi) bu dosyalarda **derlemeyi bozmamasını** sağlamaktır (ör. `word.isWeak
(at:)` çağrıları `word.isDue(at:)`e dönmeli) — A bu dosyaların iş mantığını değiştirmez.

**B — Tur içi oyun mantığı + cevap kontrolü + çeldirici (A bittikten sonra):**
`Shared/Logic/ChoiceQuiz.swift`, `Shared/Logic/MatchBoard.swift`, `Shared/Logic/LetterPuzzle.swift`,
`Shared/Logic/QuickMix.swift`, `Shared/Logic/GameMode.swift` (yalnızca alt kısım: `GameDeck`/açılma
koşulu), `Shared/Logic/ClozeSentence.swift`, `Shared/Logic/ReverseChecker.swift` (**yalnızca gövde**:
A'nın eklediği saplamanın yerine gerçek eşanlam tespiti, §3.2 — imzayı bir daha değiştirmez),
`Shared/AnswerChecker.swift`, `Shared/Games/FillBlankGameView.swift`, `MatchGameView.swift`,
`LettersGameView.swift`, `ChoiceGameView.swift`, `QuickMixGameView.swift` (bu beş görünüm dosyası
kendi `RoundEntry`lerini bugünkü gibi doğrudan `RoundSummaryView.Entry`ye çevirmeye devam eder,
§4.1 — A'dan yeni bir tip beklemez).

**C — Özet/gösterge + Mac:** `Shared/Games/RoundSummaryView.swift`, `Shared/Games/RecallGameView.swift`,
`Shared/Games/GameScaffold.swift`, `Mac/MacStudyView.swift`, `Mac/MenuBarView.swift`,
`Shared/Logic/MemoryStats.swift`, `KelimeDefteri/Views/WordListView.swift`.

---

## 9. Kararlar

Aşağıdakiler soru değil, verilmiş kullanıcı kararlarıdır; belge boyunca ilgili bölümler bunlara göre
yazıldı (§2.4 [karar 2], §2.8/§4.5 [karar 3], §4.1/§4.5 [karar 4], §2.2/§4.2/§4.5 [karar 5]).

1. **Tur içi yeniden sorma ve yeni arayüz öğeleri.** Tanıma oyunlarında (Çoktan Seçmeli, Eşleştir,
   Boşluğu Doldur, Hızlı Tur karışık) yanlış bilinen kelime tur içinde yeniden **sorulmaz** (§3.1 —
   yalnızca hatırlama/Ters Yön tur içi yeniden sorar). Harfleri Diz'e "İpucu" düğmesi ve Ters Yön'e
   proaktif ayırt edici ipucu **eklenmez** (Ters Yön'deki belirsizlik yalnızca cevap-sonrası
   "Doğru, ama aranan: X" mesajıyla ele alınır, §3.2). Aynı gün, aynı desteyi tekrar oynarken tek
   satırlık bir not **gösterilir**: "Bu tur bugünün diğer cevaplarıyla birlikte değerlendiriliyor."
   (§3.2, son paragraf).

2. **Aynı gün içinde bir kez doğru, bir kez yanlış bilinen kelime "bilemedin" sayılır.** 1/3 eşiği
   değişmedi (§2.4): gün içindeki cevapların üçte birinden fazlası yanlışsa gün "bilemedin"
   (kelime ertesi güne erteleniyor, dayanıklılığı düşüyor); azsa "zor bildin" (kelime zayıflamıyor).
   Günde tam 2 cevaptan biri yanlışsa (1/2 oranı) bu her zaman "bilemedin"e düşer — kural tek ve
   basit kalır, en yaygın örneği ("yanlış cevabım hiç işlenmiyordu") en güçlü biçimde çözer.

3. **Widget ve bildirimin soru seçimi:** önce vadesi gelmiş (`isDue`) ve **yeni olmayan** kelimeler
   arasından; bu küme boşsa yeni hariç bütün defterden ağırlıklı rastgele — widget/bildirim hiçbir
   zaman boş kalmaz (§2.8). Yeni kelimeler widget'ta ya da bildirimde **hiç sorulmaz**; yeni kelime
   tanıtımı yalnızca Günlük Tekrar/Yeni Eklenenler üzerinden olur.

4. **Tur özetinde ✓/✗ = bu turdaki ilk cevap** (günün notu değil); "sonraki tekrar" metni turdan
   sonraki günün gerçek sonucunu yansıtır (§4.1 — mevcut `RoundEntry`/`Entry` yapısı zaten böyle
   çalışıyor, yeniden kurulmadı). Üstteki "x/y doğru" sayısı da bu turdaki ilk cevaplardan sayılır.

5. **"Zayıf" kelimesinin tek tanımı: `lapsedAt != nil`.** Yanlış bilinen kelime, listede ve ayrıntı
   sayfasında turuncu halka, "Tekrar edilecek" etiketi ve ne zaman tekrar sorulacağı ("Yarın" vb.)
   ile gösterilir — bu, kelimenin vadesi henüz gelmemiş olsa bile geçerlidir. Günlük Tekrar ve "N
   zayıf" sayacı ise yalnızca **vadesi de gelmiş** (`isDue`) zayıf kelimeleri sayar/seçer; bu ikinci
   kısıtlama "zayıf"ın anlamını değiştirmez, yalnızca "ne zaman sorulur/sayılır"ı belirler (§2.2,
   §4.5).
