# Çalışma raporu: Oyunlaştırma

`docs/SPEC-OYUN.md` görevlerinin `/loop` ile yürütülmesinin kaydı (23 Eylül 2026).

## Özet

Bütün görevler bitti (A1, B1–B4, C1–C7); hiçbiri `[~]` kalmadı. 109 birim testin hepsi geçiyor.
Her görev `main`'e ayrı commit olarak gitti. B3'ten sonra her görev iPhone 14'e ve Mac'e kuruldu; yalnızca
C1 turunda telefon bağlı değildi, C2 ile birlikte kuruldu.

**Uygulamada ne değişti**
- **Kutu sistemi yerine hafıza.** Her kelimenin hatırlama ihtimali (%) var ve zamanla azalıyor; %90'ın altına
  inen kelime tekrara geliyor. "Kutu" hiçbir ekranda kalmadı; her yerde renkli hafıza halkası var.
- **Not sorulmuyor.** Cevaptan çıkarılıyor: hız, cevaba bakma, "Doğru Say", yazım hatası. Tanıma oyunları
  (seçenekli) hatırlama oyunlarından daha az etki ediyor.
- **Her cevap kaydediliyor** (`ReviewLog`); kelime ayrıntısında geçmiş ve istatistik bunlardan geliyor.
- **Çalış sekmesi oyun merkezi oldu:** Günlük Tekrar kartı ve 6 oyun (Hızlı Tur, Çoktan Seçmeli, Eşleştir,
  Boşluğu Doldur, Harfleri Diz, Ters Yön). Her tur ortak bir özetle biter.
- **Sıra karışık:** zayıf kelime öne gelme eğiliminde, aynı kelime art arda gelmiyor, yeni tur öncekinin ilk
  kelimesiyle başlamıyor.
- **Mac:** hafıza halkası, sıralanabilir "Hafıza" sütunu, "Hepsi Güçlü / Yine de Çalış", karışık sıra ve kayıt.
  Oyunlar Mac'e henüz gelmedi (spec böyle istiyordu).
- **Eski veri korunuyor:** ilk açılışta kutu bilgisi bir kere hafıza değerlerine çevrildi; iCloud şemasında
  hiçbir alan silinmedi ya da adı değişmedi.

**Önemli kararlar (ayrıntısı görev bölümlerinde)**
- Tur özetinde "sonraki hafıza" cevaptan hemen sonra ölçüldüğü için hep ~%99 görünüyor (tanım gereği).
  Spec'e sadık kalındı; ileride yerine "sıradaki tekrar: 5 gün sonra" göstermek daha bilgilendirici olabilir.
- Karışık Hızlı Tur'da her soru kendi oyununun adıyla ve ağırlığıyla kaydediliyor; Eşleştir karışık tura girmiyor.
- Harfleri Diz'de 3+ hata cevabı açmakla aynı sayılıyor; yanlış dolu diziliş kırmızı kalıyor.
- Boşluğu Doldur ekli hâlleri kabul ediyor ("tombstones"), kelime içi eşleşmeyi kabul etmiyor ("start" ≠ "art").
- Kelimelerim süzgecinde Zayıf / Güçlü / Yeni birbirini dışlıyor; Günlük Tekrar ise yenileri de sayıyor.

**Bilinen eksikler ve sonraki adımlar**
- Oyunlar yalnızca iPhone/iPad'de; Mac menü penceresinde yalnızca hatırlama çalışması var.
- CloudKit şeması hâlâ geliştirme ortamında; `ReviewLog` ve yeni alanlar TestFlight/App Store öncesi üretime
  aktarılmalı (Apple Developer hesabında işlem, onay gerekir).
- Güncellenmemiş bir cihazdan iCloud'la gelen eski kayıtlar bir sonraki açılışta geçirilir.
- Kutu aralıkları (`Leitner.intervalsInDays`) yalnızca geçiş için kodda duruyor; bütün cihazlar geçtikten sonra
  kaldırılabilir. `Word.box` alanı CloudKit kuralı gereği silinmedi.
- Test sırasında görülen tuzak: `xcodebuild test` bir test başarısız olunca `simctl diagnose` ile dakikalarca
  bekleyebiliyor; `-collect-test-diagnostics never` bunu önlüyor.

## Görevler

### A1 · Karışık sıra (23 Eylül 2026)
- `Shared/Logic/WordPicker.swift`: ağırlıklı, tekrarsız sıra (Efraimidis–Spirakis), tohumlanabilir
  `SeededGenerator` (SplitMix64), geçici gecikme ağırlığı (yeni 1.0, diğerleri `min(1, gecikme/7) + 0.1`),
  kelime sayısı ve yeni kelime sınırı, önceki turun ilk kelimesinden kaçınma, yanlış kelimenin yeniden giriş yeri.
- `StudySession` artık sırayı `WordPicker`'dan alır (iOS ve Mac aynı sınıfı kullanıyor). Yanlış bilinen
  kelime arada 2 kelime olacak şekilde yeniden girer; önceki turun ilk kelimesi `UserDefaults`'ta.
- Testler: `WordPickerTests` (8) ve `StudySessionTests`'e 3 yeni test; 58 testin hepsi geçti. iOS ve Mac derlendi.

**Verilen kararlar**
- Önceki turun ilk kelimesi kimlik yerine `AnswerChecker.fold(english)` ile saklanır: iCloud'dan gelen
  kayıtta da aynı kalır, testte depoya eklemeden denenebilir. Aynı yazılışlı iki kayıt varsa ikisi de aynı sayılır.
- Turda tek kelime kaldıysa yanlış bilinen kelime hemen yeniden gelir (spec: "yeterli kelime yoksa en sona").
- Günlük Tekrar'ın 20/5 sınırı `WordPicker.order(limit:maxNew:)` olarak hazır ve testli; ekrana C1'de bağlanacak.
  A1'de mevcut "zamanı gelenler" turu sınırsız kaldı, davranışı bozmamak için.
- Tur ortasında zamanı gelen yeni kelimeler (`sync`) kendi aralarında ağırlıklı sırayla sona eklenir.

**Bilinen eksikler**
- Çalış kartında "Kutu 0/5" hâlâ görünüyor; B3'te `MemoryRing` ile değişecek.

### B1 · Kayıt modeli ve geçiş (23 Eylül 2026)
- `Word`'e `stability`, `difficulty`, `lastReviewedAt` ve `logs` (silinince loglar da silinir) eklendi.
  Yeni model `Shared/ReviewLog.swift`. `box` ve `dueDate` duruyor; hiçbir alan silinmedi ya da yeniden adlandırılmadı.
- Ortak şema `SharedStore.schema` (`Word` + `ReviewLog`); uygulama, eklenti, örnek veri ve testler bunu kullanıyor.
- `Shared/Logic/MemoryMigration.swift`: kutu ve doğru oranından hafıza değerleri (saf fonksiyon) ve
  `migrateIfNeeded(context:)`. Uygulama açılışında çalışır; `-demo` örnek verisi de geçirilir.
- Testler: `MemoryMigrationTests` (4): geçiş değerleri, zorluğun sınırlanması, ikinci çalıştırmada değişiklik yok,
  kelime silinince logların silinmesi. 62 testin hepsi geçti. iOS ve Mac derlendi; simülatörde yeni şemayla açıldı.

**Verilen kararlar**
- Geçiş, `SharedStore.container` kurulurken yapılır; böylece iOS ve Mac tek yerden geçer. Paylaş eklentisi geçiş
  yapmaz (yalnızca yeni kelime ekler, onların `reviewCount`'u 0).
- İki cihaz aynı kelimeyi ayrı ayrı geçirse de sonuç aynıdır (değerler yalnızca eski alanlardan hesaplanıyor),
  iCloud çakışması zararsız.
- Görünür ekran değişikliği olmadığı için ekran görüntüsü gönderilmedi.

**Bilinen eksikler**
- Güncellenmemiş bir cihazdan geçişten sonra iCloud'la gelen eski kayıt bir sonraki açılışta geçirilir.

### B2 · Hafıza motoru (23 Eylül 2026)
- `Shared/Logic/Memory.swift`: FSRS-4.5 unutma eğrisi (`retrievability`), `review(...)` ile dayanıklılık, zorluk
  ve sıradaki tekrar; `nextDifficulty`. `Shared/Logic/GameMode.swift`: `AnswerGrade` (1–4) ve `GameMode`
  (Türkçe adı ve ağırlığı; `rawValue` `ReviewLog.mode`'a yazılacak).
- `Word` uzantısı: `isNew`, `memory(at:)`, `isWeak` / `isWeak(at:)`, `isLearned` artık `stability ≥ 21`.
- Testler: `MemoryTests` (8, zorunlu listenin hepsi + `Word` uzantısı). 70 testin hepsi geçti. iOS ve Mac derlendi.

**Verilen kararlar**
- Büyüme formülünde güncellemeden **önceki** zorluk kullanılır (FSRS'teki gibi).
- Son tekrar zamanı bilinmeyen (geçişte `dueDate`'i olmayan) kelime: motor onu tam vaktinde soruluyor sayar
  (R = 0.9); ekranda gösterilen hafıza ise eklenme tarihinden hesaplanır, yani zayıf görünür ve tekrara gelir.
- `isLearned` tanımı bu görevde değişti (Ayarlar'daki "Öğrenilen" ve Kelimelerim süzgeci onu kullanıyor);
  çalışmanın motoru güncellemesi B3'te bağlanıyor. Cihaza kurulum B3'ten sonra olduğu için arada kullanıcıya etkisi yok.
- Ekran değişmediği için ekran görüntüsü alınmadı.

### B3 · Motoru bağla (23 Eylül 2026)
- Her cevap not çıkarır (`AnswerGrade.recall` / `.recognition`, spec §2 tablosu), `ReviewRecorder` motoru uygular,
  sayaçları artırır ve `ReviewLog` yazar. Cevap süresi kartın gösterildiği andan cevabın açıldığı ana kadar ölçülür.
  `StudySession.mode` cevabın hangi oyun adına yazılacağını tutar (şimdilik Günlük Tekrar). iOS ve Mac aynı sınıfı kullanır.
- `WordPicker` hafıza ağırlığına geçti (yeni 1.0, diğerleri `1 − R + 0.1`); tur zayıf kelimelerle (yeni ya da R < %90) başlar.
- `MemoryRing` (`BoxRing`'in yerine): R oranında dolar, yeşil/turuncu/kırmızı, yeni kelimede kesik gri; yazı yanda ya da ortada.
  Çalış kartı (iOS, Mac), Kelimelerim satırı, ayrıntı, tekrar kelime uyarısı (Ekle formu ve Paylaş eklentisi), Mac tablosu
  ("Hafıza" sütunu, sıralanabilir) ve İlerleme (hafıza dağılımı + "Ortalama hafıza") güncellendi. "Kutu" hiçbir ekranda kalmadı.
- Sekme rozeti, menü çubuğu sayısı ve uygulama simgesi rozeti zayıf kelime sayısını gösterir. Hatırlatma metinleri güncellendi.
- `Leitner.review` ve kutu açıklaması silindi; geriye yalnızca geçişin okuduğu aralıklar ve "Yarın / 3 gün sonra" anlatımı kaldı.
- Testler: `ReviewRecorderTests` (3), `StudySessionTests`'e 3 yeni test, `WordPickerTests` güncellendi. 71 testin hepsi geçti.
- iPhone'a (Debug) ve Mac'e (`/Applications`, Release) kuruldu. Mac'te gerçek defter geçişle yüzde aldı; Kelimelerim tablosu
  ve "Hepsi Güçlü" ekranı kontrol edildi. Kullanıcının kelimelerine not verilmedi.

**Verilen kararlar**
- Yüzde aşağı yuvarlanır (%89,9 → %89): zayıflamış kelime %90 görünüp "neden sorulmuş" dedirtmesin.
- Bitiş ekranı iOS'ta da Mac'teki gibi "Hepsi Güçlü" / **Yine de Çalış** (en zayıf 10 kelime) oldu; iOS'taki hâli C1'de oyun
  merkezine dönüşecek. "Hepsini Çalış" kalktı.
- Kelimelerim süzgecindeki "Sırada" seçeneği "Zayıf" oldu; tam süzgeç/sıralama B4'te.
- Hatırlatma planı `dueDate`'e bakmaya devam ediyor: motor `dueDate`'i tam R = %90 anına koyduğu için "o gün zayıflayacak
  kelime sayısı" ile aynı şey. Simge rozeti ise o anki zayıf kelime sayısı.
- `DeckSummary` "12 sırada" yerine "12 zayıf" der.
- İlerleme dilimlerindeki halkalar dilimin ortasına yakın bir değerle çizilir (renk anlatsın diye).

**Bilinen eksikler**
- Günlük Tekrar'ın 20/5 sınırı C1'de bağlanacak.

### B4 · Kelime istatistiği (23 Eylül 2026)
- Ayrıntı sayfası: "Hafıza" bölümü (56 pt halka ortasında yüzde; yanında durum: Yeni / Zayıfladı / Güçlü / Öğrenildi
  ve tek satır açıklama; Sıradaki tekrar, Görülme, Doğru bilme, Son görülme (göreli), Ortalama cevap süresi, Eklendi).
  "Geçmiş" bölümü: son 30 gösterim yeşil/kırmızı nokta, altında oyunlara göre sayılar.
- `Shared/Logic/WordStats.swift` (saf, testli): son 30 kayıt, oyun sayıları, ortalama süre. `WordStatsTests` (3).
- Kelimelerim: süzgeç Tümü / Zayıf / Güçlü / Yeni; sıralama Eklenme Tarihi / A–Z / Hafıza / En Zor.
- Örnek veriye (`-demo`) cevap geçmişi eklendi. 74 testin hepsi geçti. iPhone'a ve Mac'e kuruldu.

**Verilen kararlar**
- Halka yüzdeyi zaten gösterdiği için ayrıntıdaki başlık "Hafıza %78" yerine kelimenin durumunu söyler ("Zayıfladı").
- "Görülme" ve "Doğru bilme" kayıt sayısı yerine `reviewCount`/`correctCount`'tan gelir: kayıtlar B3'te başladı,
  sayaçlar eski çalışmaları da içerir. Her yeni cevap ikisini birlikte artırdığı için ileride fark kapanmaz ama doğru kalır.
- Süzgeçte Zayıf, Güçlü ve Yeni birbirini dışlar (Zayıf = çalışılmış ve %90 altı). Günlük Tekrar ise yenileri de sayar.
- "Hafıza" ve "En Zor" sıralamalarında yeni kelimeler sona konur; hafızası ve zorluğu henüz ölçülmedi.
- Eşleştir gibi süre ölçülmeyen oyunların cevapları ortalama süreye katılmaz.
- Mac'te ayrıntı sayfası yok (tablo zaten sıralanabilir "Hafıza" sütunu taşıyor); ayrıntı istatistiği yalnızca iOS'ta.
- Ayarlar'daki eski "Sırada" süzgeci kaydı yeni seçeneklere uymadığı için "Tümü"ye döner.

### C1 · Oyun merkezi, Günlük Tekrar, Hızlı Tur, tur özeti (23 Eylül 2026)
- Çalış sekmesi oyun merkezi oldu: alt başlık "Hafıza %86 · 2 kelime zayıfladı", Günlük Tekrar kartı (başlık, satır,
  56 pt ortalama hafıza halkası, Başla / Yine de Çalış), "Oyunlar" başlığı ve 2 sütunlu oyun kartları (şimdilik Hızlı Tur).
  Boş defterde eski "Defterin Boş" görünümü.
- `RecallGameView`: eski Çalış kartı ve cevap çubuğu aynen, tam ekran; solda ✕ (`role: .close`), üstte ince ilerleme ve "1/5".
  Kapatınca o ana kadarki cevaplar kayıtlı kalır.
- `RoundSummaryView` (bütün oyunlarda ortak): "Tur Bitti", "4/5 doğru · 20 sn", her kelime için ilk cevabın doğruluğu ve
  "%59 → ◯ %99"; Bir Tur Daha / Bitti.
- `StudySession.Plan`: `.daily` (zayıflar, en fazla 20, en fazla 5 yeni), `.extraPractice` (en zayıf 10), `.quick` (5 kelime,
  bütün defterden ağırlıklı), `.weak` (Mac menü penceresi, sınırsız). Tur özeti için `roundEntries`, süre için `startedAt/finishedAt`.
- `RoundText` (tahmini süre, süre, özet satırı), `GameMode` kart bilgileri ve `GameDeck` ile oynanabilirlik koşulları (bütün
  oyunlar için, testli). `SettingsIcon`'a boyut parametresi.
- Testler: `RoundTextTests`, `GameCatalogTests`, `StudyPlanTests` (3). 82 testin hepsi geçti. Mac'e kuruldu.

**Verilen kararlar**
- Günlük Tekrar satırı yeni kelimeleri ayrı söyler: "2 kelime zayıfladı · 2 yeni · yaklaşık 2 dk"; yalnızca yeni varsa
  "3 yeni kelime". Alt başlıktaki sayı yalnızca çalışılmış zayıf kelimeler.
- Satır parçaları ("yaklaşık 2 dk") bölünmez boşlukla yazılır; satır yalnızca " · " aralarında kırılır.
- Tur özetinde her kelime için ilk cevap sayılır (yanlış bilinip sonra bilinen kelime "yanlış"). Satırın başına ✓/✕ simgesi kondu.
- Cevaptan hemen sonra hafıza tanım gereği %99–100 görünür; spec'teki "önce → sonra" gösterimi korundu. İleride "sonra" yerine
  sıradaki tekrar günü göstermek daha bilgilendirici olabilir.
- "Bir Tur Daha" aynı türde yeni tur açar; Günlük Tekrar'da zayıf kelime kalmadıysa en zayıf 10 kelimeyle devam eder.
- Eski bitiş ekranındaki "Her Gün Hatırlat" kısayolu kalktı; hatırlatma Ayarlar'da.
- Oyun merkezindeki sayılar her dakika ve oyun kapanınca tazelenir.
- Mac menü penceresi değişmedi (spec: oyunlar Mac'e sonra gelecek); karışık sıra ve `ReviewLog` orada da çalışıyor.

**Bilinen eksikler**
- iPhone bu turda bağlı değildi (`devicectl`: unavailable); C2 ile birlikte kuruldu.

### C2 · Çoktan Seçmeli (23 Eylül 2026)
- `ChoiceGameView`: 10 soru (defterde daha az kelime varsa hepsi), üstte serif kelime + telaffuz + cümle, altta 4 tam
  genişlik cam düğme. Doğru: yeşil + ✓, 0,8 sn sonra geçer. Yanlış: seçilen kırmızı + ✕, doğrusu yeşil, altta **Devam**.
  Titreşim doğruda `.success`, yanlışta `.warning`. Kayıt tanıma notuyla (`good`/`again`, ağırlık 0.6).
- `ChoiceQuiz` (saf, testli): ilk anlam, seçenek üretimi (önce aynı kaynak, aynı katlanmış anlam asla yanlış seçenek olmaz).
- `GameRound`: soru soru ilerleyen oyunların ortak turu (ağırlıklı seçim, önceki turun ilk kelimesinden kaçınma, kayıt,
  özet girdileri). Sonraki oyunlar da bunu kullanacak. Ortak parçalar: `GameWordCard`, `ChoiceButtons`, `ContinueButton`.
- Testler: `ChoiceQuizTests` (5), `GameRoundTests` (2). 89 testin hepsi geçti. iPhone (C1 ile birlikte) ve Mac'e kuruldu.

**Verilen kararlar**
- Defterde 10'dan az kelime varsa tur o kadar soru sorar.
- Aynı katlanmış anlamı taşıyan iki kelime varsa seçeneklerde yalnızca biri çıkar; farklı seçenek yetmezse 4'ten az seçenek gösterilir
  (en az 4 kelime koşulu olduğundan pratikte nadir).
- Düğme yüksekliği ilk denemede fazla geldi; dikey boşluk azaltıldı.

### C3 · Eşleştir (23 Eylül 2026)
- `MatchGameView`: 5 çift (defterde 4 kelime varsa 4), solda serif İngilizce, sağda karışık ilk anlamlar. Üstte süre (m:ss) ve
  hata sayısı, ince ilerleme çubuğu. Seçili kutu vurgu rengi çerçeveli; doğru çift yeşil olup `.snappy` ile kaybolur; yanlış
  çift sallanır, kırmızı yanıp söner, hata sayılır, seçim sıfırlanır. Hepsi eşleşince tur özeti.
- `MatchBoard` (saf, testli): karışık sağ sütun, eşleştirme, hata ve yanlış çifte giren kelimeler; not `good`/`again`.
- `GameRound`: `distinctBy` (aynı anlamlı iki kelime aynı tahtaya düşmez), `timed: false`, `finish()`.
- Testler: `MatchBoardTests` (2). 91 testin hepsi geçti. iPhone ve Mac'e kuruldu.

**Verilen kararlar**
- Eşleşen kutular yerinde görünmez olur; diğer kutular kaymaz, kullanıcı yerini kaybetmez.
- Yanlış çiftte **iki** kelime de "yanlış çifte girdi" sayılır (soldaki kelime ve sağdaki anlamın sahibi).
- Eşleştir'de cevap süresi kaydedilmez (ortalama cevap süresine katılmaz); tur süresi özette görünür.
- Sağ sütun hiçbir zaman sol sütunla aynı sırada gelmez.
- Başlıkta "3/10" sayısı yok (soru sırası olmayan oyun); yalnızca çubuk ve altında süre/hata.

### C4 · Boşluğu Doldur (23 Eylül 2026)
- `FillBlankGameView`: 10 soru, yalnızca cümlesinde kelimenin kendisi geçen kelimeler. Cümle serif, kelimenin yeri `_____`;
  altında ampul simgesiyle Türkçe ilk anlam, soluk kitap adı. 4 serif İngilizce cam seçenek; davranış Çoktan Seçmeli ile aynı.
- `ClozeSentence` (saf, testli): büyük/küçük harf ve aksan gözetmeden kelimeyi bulur, önünde harf olmamalı, arkasından ek gelebilir.
  Oyun merkezindeki koşul (`GameDeck.withSentence`) da artık aynı kuralı kullanıyor.
- Testler: `ClozeSentenceTests` (3). 94 testin hepsi geçti. iPhone ve Mac'e kuruldu.

**Verilen kararlar**
- "tombstone" ↔ "tombstones" gibi ekli hâller kabul edilir; boşluk yalnızca kelimeyi kaplar, ek görünür kalır ("_____s").
  Böylece çoğul/çekimli cümleler de oyuna girer. "art" ↔ "start" gibi kelime içi eşleşme kabul edilmez.
- Boşluk yalnızca doğru seçimde değil, yanlış seçimde de doğru kelimeyle dolar: kullanıcı doğrusunu cümle içinde görsün.
- Yanlış seçenekler cümlesi olmayan kelimelerden de gelebilir (yalnızca sorulan kelimenin cümlesi gerekli).
- Kitap adı kartta soluk küçük satır olarak kaldı (Çalış kartındaki kaynak satırının karşılığı).

### C5 · Harfleri Diz (23 Eylül 2026)
- `LettersGameView`: 8 soru, ≤ 14 harfli kelimeler. Üstte Türkçe anlamlar, altında alt çizgili cevap yuvaları (serif harf),
  en altta ortalanmış cam harf taşları. Taşa dokununca ilk boş yuvaya gider, yuvadaki harfe dokununca geri döner. Yuvalar
  dolunca kendiliğinden kontrol: doğru yeşil ve 0,8 sn sonra geçer; yanlışta yuvalar sallanır, harfler yerinde kalır.
  **Göster** cevabı açar (`again`), ardından **Devam**.
- `LetterPuzzle` (saf, testli): sabit karakterler (boşluk, tire), karışık taşlar (asla doğru sırada gelmez), yerleştirme,
  kontrol, hata sayısı, cevabı açma ve not. `FlowLayout`'a `centered` seçeneği eklendi.
- Testler: `LetterPuzzleTests` (6). 100 testin hepsi geçti. iPhone ve Mac'e kuruldu.

**Verilen kararlar**
- Not: 0 hata `good`, 1–2 hata `hard`; spec 3+ hatayı söylemiyor, cevabı açmakla aynı sayıldı (`again`).
- Yanlış diziliş yalnızca sallanmakla kalmaz: yuvalar dolu ve yanlışken harfler ve çizgiler kırmızı durur, bir harf
  çıkarılınca normale döner. Sallanma kaçırılırsa kullanıcı neden ilerlemediğini anlasın diye.
- Kartta yalnızca Türkçe anlamlar var (spec); İngilizce tanım ilk denemede gösterildi, kaldırıldı.
- Taşlar ve yuvalar büyük/küçük harfi korur ("API"), karşılaştırma harf büyüklüğü ve aksan gözetmez.
- Açılan cevap ve doğru diziliş soluk görünmesin diye yuvalar `disabled` yerine `allowsHitTesting` ile kilitlenir.
- Yuva genişliği harf sayısına göre küçülür; 14 harf tek satıra sığar.

### C6 · Ters Yön (23 Eylül 2026)
- Hatırlama ekranı (`RecallGameView`) ve `StudySession` Türkçeden İngilizceye de çalışıyor (`Plan.reverse`, 10 kelime,
  bütün defterden ağırlıklı). Kartta Türkçe anlamlar büyük; alan "İngilizcesi". Cevap açılınca serif İngilizce kelime
  (vurgu rengi), telaffuz ve kitaptaki cümle görünür. Göster / ↑ ve `GradeOption` mantığı aynen.
- `ReverseChecker` (saf, testli): sadeleştirilmiş eşitlik ya da 5+ harfli kelimede en fazla 1 harf fark (Levenshtein).
  Yazım hatasıyla doğru: yeni `Verdict.almost`, turuncu "Neredeyse: doğrusu “idempotent”", tek **Devam**, not `hard`.
- Testler: `ReverseCheckerTests` (4), `ReverseSessionTests` (1). 105 testin hepsi geçti. iPhone ve Mac'e kuruldu.

**Verilen kararlar**
- Soru anında İngilizce cümle ve telaffuz düğmesi gizli (ikisi de cevabı ele verir); cevapla birlikte açılır.
- Yanlış cevapta "Doğru Say" korunur ve açıklama "Eşanlamlıysa Doğru Say'a bas." olur (İngilizce eşanlamlıyı kontrol tanımaz).
- 5 harften kısa kelimelerde yazım hatası kabul edilmez (spec); "stal" → "stale" 5 harfli olduğu için kabul.
- Mac'teki sonuç satırı yeni durumu tanır ("Neredeyse"); Mac'te Ters Yön henüz yok.

### C7 · Hızlı Tur karışık (23 Eylül 2026)
- `QuickMixGameView`: Hızlı Tur'un 5 sorusu oynanabilir türlerden rastgele (hatırlama, Çoktan Seçmeli, Boşluğu Doldur,
  Harfleri Diz, Ters Yön); aynı tür art arda en fazla iki kez. Oyun merkezindeki Hızlı Tur kartı bunu açar.
- Soru ekranları ayrı parçalara ayrıldı ve oyunlar onları kullanıyor: `RecallQuestionView`, `ChoiceQuestionView`
  (Çoktan Seçmeli + Boşluğu Doldur, `ClozeCard`), `LettersQuestionView`. Davranış değişmedi.
- `QuickMix` (saf, testli): tür seçimi ve kelime başına oynanabilir türler. `GameRound`'a türe göre kayıt ve `adopt`.
- Testler: `QuickMixTests` (4). 109 testin hepsi geçti. iPhone ve Mac'e kuruldu.

**Verilen kararlar**
- Eşleştir karışık tura girmez: tek soruluk değil, 4–5 kelimelik bir tahta.
- Her soru kendi oyununun adıyla ve ağırlığıyla kaydedilir (ör. Çoktan Seçmeli sorusu 0.6); İngilizceden Türkçeye hatırlama
  soruları "Hızlı Tur" adıyla. Böylece hafıza hesabı doğru, kelime geçmişi de gerçek oyun türünü gösterir.
- Türler kelime bazında seçilir: cümlesi olmayan kelimeye Boşluğu Doldur, 14 harften uzun kelimeye Harfleri Diz gelmez.
- Hatırlama sorusunun cevap süresi soru ekrana geldiğinde başlar (oturum o an kurulur).

### İnceleme düzeltmeleri (23 Eylül 2026)
Oyunlaştırma işinin eleştirel incelemesinde bulunan sorunlardan 1–8 düzeltildi:
- Hatırlama ekranında cevap açıldıktan sonra ✕ ile kapatınca sonuç kaybolmuyor: öne çıkan düğmeyle kaydediliyor
  (`StudySession.gradePendingAnswer`). Yalnızca cevaba bakıldıysa kaydedilmiyor (ne bilindiği belli değil).
- Yanlış seçenek, sorulan kelimenin herhangi bir anlamını taşıyamaz (ör. "stale: bayat, eskimiş" sorulurken
  "outdated: eskimiş" çıkmaz); Eşleştir'de ortak anlamlı iki kelime aynı tahtaya düşmez (`ChoiceQuiz.shareMeaning`).
- Uygulama arka plandayken geçen süre cevap süresine sayılmıyor (`pauseClock` / `resumeClock`; iOS'ta `scenePhase`,
  Mac'te pencere kapanınca).
- Uygulama açıkken iCloud'dan eski biçimde gelen kelime ilk cevaptan önce geçiriliyor (`ReviewRecorder`); geçiş iOS'ta
  uygulama öne gelince, Mac'te menü penceresi açılınca da çalışıyor.
- Mac menü penceresi de Günlük Tekrar sınırını (20 kelime, 5 yeni) kullanıyor; tur bitince zayıf kelime kaldıysa yenisi başlıyor.
- Günlük Tekrar turu önce çalışılmış zayıfları, kalan yere yenileri alıyor; kartta yazan dağılımla aynı. Çalış alt başlığı
  20 sınırı olmadan kaç kelimenin zayıfladığını söylüyor. Defter özetindeki "N zayıf" yeni kelimeleri saymıyor (Zayıf süzgeci gibi).
- Boşluğu Doldur önce kelimenin tek başına geçtiği yeri arıyor, yoksa bilinen bir eki kabul ediyor
  ("art" artık "Artificial"da bulunmuyor).
- Hatırlama ekranında doğru/yanlış titreşimi çalışıyor ("Neredeyse" doğru sayılıyor, cevaba bakınca titreşim yok).
- Testler: `ReviewFixesTests` (8). 117 testin hepsi geçti.

**İncelemenin kalan maddeleri (9–12)**
- İki cihazda aynı anda artan sayaçta biri kaybolabiliyordu (iCloud'da son yazan kazanır). "Görülme", "Doğru bilme" ve
  Ayarlar'daki toplamlar artık sayaç ile cevap kayıtlarından büyük olanı gösteriyor (`Word.answerCount`,
  `correctAnswerCount`); kayıtlardan önceki Leitner dönemi cevapları yalnızca sayaçta olduğu için ikisine de bakılıyor.
- Karar: hafızayı turdaki **ilk** cevap değiştirir. Aynı turda aynı kelimeye verilen sonraki cevaplar yalnızca sayaçlara ve
  geçmişe yazılır (`ReviewRecorder.record(updatesMemory:)`). Önceden turda iki kez bilinmeyen 20 günlük kelime 2,5 güne
  düşüyordu; şimdi bir kez düşer (~7 gün) ve orada kalır.
- Karar: eski sürüm cihazın geçirilmiş kelimeleri eskitmesi için kod yazılmadı; defteri kullanan iki cihaz da (iPhone, Mac)
  güncel. Yeni bir cihaz eklenirse önce güncellenmeli.
- Testler düzeltildi: `GameRoundTests` ağırlığın ve ilk-cevap kuralının etkisini kontrol ediyor, karışık turun türe göre
  kaydı test ediliyor; `WordPickerTests`'teki yanıltıcı "art arda" kontrolü kaldırıldı. Yeni: `RepeatAnswerTests` (2).
  120 testin hepsi geçti.

- Cevap açıkken uygulama kapatılırsa da cevap kaybolmuyor: arka plana geçerken (Mac'te pencere kapanınca ya da
  uygulamadan çıkılınca) sonucu belli cevap öne çıkan düğmeyle hemen kaydedilir, kart yerinde kalır
  (`StudySession.commitPendingAnswer`). Dönünce aynı düğmeye basılırsa yalnızca ilerlenir; başka düğmeye basılırsa
  (ör. "Doğru Say") ilk kayıt geri alınıp yenisi yazılır. Testler: `CommitPendingAnswerTests` (3). 123 testin hepsi geçti.

### iPhone düzeltmeleri (23 Eylül 2026)
- Kelimelerim'de sola kaydırınca çıkan silme düğmesi yalnızca simge (altındaki "Sil" yazısı kalktı; VoiceOver adı duruyor).
  Satırın kaydırılırken köşelerinin yuvarlanması iOS 26'nın kendi animasyonu, değiştirilmedi.
- Karar: **yanlış bilinen kelime doğru bilinene kadar zayıf sayılır.** Önceden hafıza "şu an hatırlama ihtimali" olduğu için
  yanlış cevaptan hemen sonra da %99 görünüyordu: yanlış yapınca defterin ortalaması yükseliyor, kelime günlerce
  Günlük Tekrar'a gelmiyordu. Şimdi yanlış cevapta sıradaki tekrar geçmişe konur (`Memory.lapseDue`); hafıza oradan
  sayılır ve cevaptan önceki değeri, en fazla %50'yi gösterir (`Word.isLapsed`). Kelime hemen zayıf, rozete ve Günlük
  Tekrar'a girer. Doğru cevapla (aynı turda olsa da) tekrar zamanı normale döner. Dayanıklılık ve son tekrar zamanı motorun
  kendi değerleri olarak kalır; yeni alan yok, CloudKit şeması değişmedi.
- Karar: tur özetinde "sonra" sütunu hafıza yüzdesi yerine sıradaki tekrarı gösterir ("%59 → 35 gün sonra",
  yanlışta kırmızı "Şimdi"). Cevaptan hemen sonra hafıza hep ~%100 olduğu için ikinci yüzde bir şey anlatmıyordu.
- Testler: `LapseTests` (6). 129 testin hepsi geçti.
- Çalış başlığının altındaki "Hafıza %85 · 2 kelime zayıfladı" satırı kaldırıldı; aynı bilgi hemen altındaki Günlük Tekrar kartında.
- Tur ilerlemesi kelime sayısıyla gösterilir (`StudySession.wordCount`, `finishedWordCount`): bilinmeyen kelime sıraya
  yeniden girse de "1/4" "2/5" olmaz; kelime bilinince ilerler.
- Hatırlama sorularında klavye her kartta açık gelir; yazmadan bakmak için "Göster" duruyor.
- Eşleştir'de yanlış çiftte yalnızca soldaki (anlamı aranan) kelime yanlış sayılır; anlamı yanlış yere verilen kelime sayılmaz.
- Testler: `RoundProgressTests` (1), `MatchBoardTests` güncellendi. 130 testin hepsi geçti.

### Genel inceleme düzeltmeleri (23 Eylül 2026)
iPhone ekranları simülatörde tek tek denendi, mantık ve ekran kodu yeniden incelendi; bulunanların hepsi düzeltildi.

**Kararlar**
- Sekme ve simge rozeti ile hatırlatma bildirimi Günlük Tekrar'ın soracağı sayıyı gösterir (zayıflar + en fazla 5 yeni,
  toplam en fazla 20; `StudySession.dailyCount`, `ReminderPlanner`). Önceden yeni kelimelerin hepsini sayıyordu.
- Kelimelerim özeti süzgeçlerle birebir: "9 kelime · 2 zayıf · 4 güçlü · 3 yeni" (`DeckSummary.group`). "Öğrenildi" Ayarlar'da.
- Halka rengi "zayıf" sınırında değişir: %90 ve üstü yeşil (`Memory.targetRetention`); İlerleme dilimleri de %90'da bölünür.
- Arama süzgeçten bağımsız, bütün defterde yapılır.

**Mantık**
- Duraklatılmış saat yeni kart/tur başlayınca silinmiyor; tur süresi de arka planı saymıyor (`resumeClock` `startedAt`'i kaydırır).
- Mac: çalışma oturumu Çalış ↔ Ekle geçişinde korunuyor (`MenuBarView`); pencere yeni bir günde açılırsa açık cevap kaydedilip
  yeni tur başlıyor; tur bitince kendiliğinden yeni tur yalnızca çalışılmış zayıf kelime kaldıysa başlıyor.
- Bir kelimenin başka bir günde verilen cevabı turda yeniden "ilk cevap" sayılır.
- Yanlış bilinen kelime hemen arkasından (arada başka kart olmadan) doğru yazılırsa zayıf kalır; lapse ancak araya başka kart
  girince kalkar (`ReviewRecorder.record(clearsLapse:)`).
- Yanlış cevaptan sonra hafıza %50 görünür (%49 değil; `Memory.lapseTarget`). Yanlış bilinen kelime "öğrenildi" sayılmaz.
- Eski biçimli kelime seçimden ve özetten önce geçirilir. Silinmiş kelimeye cevap yazılmaz.

**Ekranlar**
- Klavye her kartta açık; alan boşken "Bitti" ya da karta dokunmak yalnızca klavyeyi kapatır (cevabı açmaz).
- Tur ortasında (ör. başka cihazdan) silinen kelimenin sorusu atlanır, Eşleştir'de kutuları kalkar, özetten çıkar.
- Eşleştir saati arka planda durur; Hızlı Tur'da arka planda kurulan soru duraklatılmış başlar.
- Ters Yön'de "Neredeyse" etiketi doğru kelimeyi tekrar yazmaz. Tur özeti Türkçe anlamı kesmiyor (kendi kartı, iki satır).
- Oyun kartı alt yazıları kısaldı ("Anlamıyla eşle", "Cümleyi tamamla"), küçülmüyor, satırdaki kartlar eşit boyda.
- Sekme rozeti dakikada bir ve uygulama öne gelince tazelenir.
- Ekle/Paylaş: "Zaten defterinde" uyarısı klavyenin altında kalmaz; geç gelen çeviri başka kelimeye yazılmaz; Türkçe alanı
  küçük harfle başlar, Return kaydeder; çeviri hata yazısı Türkçe yazılınca kalkar; düzenleme varsayılan kitabı değiştirmez;
  "Bugün Eklenenler" satırına dokununca düzenlenir, sola kaydırınca silinir.
- Düzenleme formu değişiklik varken aşağı çekilerek kapanmaz, ✕'te "Değişiklikleri at?" sorar.
- Ayarlar: hatırlatma kapalıyken açıklama buna göre; rozet metni yeni tanımla.
- Simülatörde sürekli çıkan "PosterBoard beklenmedik şekilde kesildi" uyarısı simülatörün kendi bozuk duvar kâğıdı kaydından
  geliyordu (uygulamayla ilgisi yok); simülatör sıfırlandı (`xcrun simctl erase`).
- Testler: `LogicFixesTests`, `GameViewFixesTests`, `FormFixesTests`. 150 testin hepsi geçti.

### Kaynak kitap kaldırıldı (23 Eylül 2026)
- Karar (kullanıcı): kitaplar çoğunlukla PDF'ten okunuyor, kitap adı hiç dolmuyordu; alan işlevsizdi. Ekle/Paylaş/Düzenle
  formlarındaki "Kaynak kitap" alanı, önceki kitaplar menüsü ve varsayılan kitap (`lastSource`) kaldırıldı. Kartlarda, ayrıntı
  sayfasında ve Mac tablosunda kitap adı gösterilmez; Çoktan Seçmeli / Boşluğu Doldur yanlış seçenekleri aynı kitabı tercih
  etmez, bütün defterden seçilir. Apple Books alıntısındaki "Alıntı Kaynağı" satırı cümleden yine ayıklanır.
- `Word.source` modelde duruyor (CloudKit şemasından alan silinemez), hiçbir yerde kullanılmıyor.

### İngilizce anlamı kaldırıldı (23 Eylül 2026)
- Karar (kullanıcı): elle yazılması gerekiyordu, hiçbir oyunda/hafızada kullanılmıyordu, pratikte boş kalıyordu. Formlardaki
  "İngilizce anlamı" / "Anlamı" alanı, ayrıntı sayfasındaki ve Hatırla/Mac kartındaki tanım gösterimi kaldırıldı; "Ayrıntılar"da
  yalnızca "Kitaptaki cümle" kalır. `Word.definition` modelde duruyor (CloudKit alanı silinemez), kullanılmıyor.

### iCloud sağlamlaştırma (23 Eylül 2026)
- Depo açılamazsa uygulama çökmez: iOS ve Mac'te "Veritabanı açılamadı" ekranı (`StoreGate`), eklentide istek hatayla kapanır;
  hata `Logger` (com.burakalemdar.KelimeDefteri / store) ile yazılır. `SharedStore.container` artık opsiyonel.
- Paylaş/Ekle formunda kaydetme başarısız olursa "Kaydedilemedi" uyarısı çıkar, form açık kalır, değişiklik geri alınır.
- Bütün `try? context.save()` yerleri `ModelContext.saveLogging()` ile hatayı günlüğe yazıyor.
- Çift kayıt: iki cihazda eşitlenmeden eklenen aynı kelime, uygulama öne gelince (iOS) / menü penceresi açılınca (Mac)
  `StoreMaintenance.run` ile birleşir: en eski kayıt kalır, anlamlar birleşir, boş cümle dolar, cevap kayıtları taşınır, sayaçlar
  toplanır, hafıza en son çalışılan kayıttan gelir. Deterministik (iki cihaz aynı sonucu verir). Düzenlemede İngilizce
  değişmediyse "başka kayıt var" uyarısı kaydetmeyi engellemez.
- Sahipsiz cevap kayıtları (kelimesi olmayan) silinir; iCloud bir cevabı kelimesinden önce getirebildiği için yalnızca en az
  1 saat arayla iki kez sahipsiz görülenler.
- Mac kartı başka cihazdan silinen kelimeyi göstermez (`aliveIDs`/`isGone` artık `Shared/`'da).
- Artıklar: kullanılmayan `SharedStore.defaults` ve boş `Assets.xcassets` katalogları silindi.
- Testler: `StoreMaintenanceTests`; 161 testin hepsi geçti.

### Motivasyon ve telefona yayılma (23 Eylül 2026)
- Günlük hedef halkası (varsayılan 30 cevap, Ayarlar › Hedef), seri, "Öğrenildi" mührü (liste ve ayrıntı), "Bu Hafta" özeti.
  Hepsi ReviewLog'lardan hesaplanır (`DailyGoal`, `WeeklySummary`); hedef App Group ayarlarında, widget da okur. Hedef
  değişince geçmiş günler yeni hedefe göre sayılır.
- `KelimeWidget` eklentisi: etkileşimli soru widget'ı (küçük/orta, StandBy), kilit ekranı "Hafıza" özeti, Denetim Merkezi /
  Eylem düğmesi "Hızlı Tur" kontrolü, `kelimedefteri://quick` bağlantısı. Widget cevapları "Çoktan Seçmeli" olarak yazılır.
- Hatırlatma bildiriminde soru: basılı tutunca 4 seçenek, cevap arka planda hafızaya yazılır.
- 189 testin hepsi geçti.

### Mac oyunları, kilit ekranı halkası, Paylaş kısayolları (23 Eylül 2026)
- Oyunlar `Shared/Games/`'e taşındı (iOS davranışı aynı, platform farkı `GameScaffold`'da). Mac menü penceresinde oyun
  merkezi (`MacGamesView`): Günlük Tekrar, hedef halkası/seri (tıklayınca Bu Hafta), 6 oyun. Klavye: Return başlat,
  1–6 oyun, 1–4 seçenek, Esc merkeze dön (menü penceresinde SwiftUI kısayolu Esc'i almadığı için yerel olay yakalayıcı),
  Harfleri Diz'de harf yazma, Eşleştir'de tıklama/sürükle-bırak. Mac hedefi kendi ayarlarında (Ayarlar › Genel › Hedef).
  Mac'te de `-demo` (DEBUG). Ekranda denendi: oyun merkezi, Çoktan Seçmeli, Harfleri Diz, Eşleştir sürükleme. Esc otomasyonla
  gönderilemediği için denenmedi.
- Kilit ekranı: yuvarlak widget günlük hedef halkası, dikdörtgen "12/30 · 4 gün seri"; gece yarısı yenilenir.
  Oyun açıkken `kelimedefteri://quick` açık ekranı kapatıp Hızlı Tur'u açar.
- `KelimeEylem` eylem eklentisi: Paylaş sayfasının alt listesinde "Kelime Defteri'ne Ekle" (yalnızca metin), KelimeEkle ile
  aynı form (`AddWordExtensionController`). Seçili metin `loadItem` yedeğiyle okunur.
- "Panodaki Kelimeyi Ekle" App Intent'i: uygulamayı açıp Ekle sekmesini panodaki metinle doldurur; Kısayollar / Eylem
  düğmesi / Arkaya Vurma ile kullanılır.
- 198 testin hepsi geçti.
