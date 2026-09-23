# Çalışma raporu: Oyunlaştırma

`docs/SPEC-OYUN.md` görevlerinin `/loop` ile yürütülmesinin kaydı.

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
