# PLAN — İŞ 4 (anlam–cümle modeli) ve İŞ 5 (Günlük Tekrar'da oyunlar)

Durum (2026-09-26): taslak plan + Codex değerlendirmesi. Uygulamadan önce aşağıdaki 'Codex düzeltmeleri' bölümü planın üstüne geçerlidir.

## Codex düzeltmeleri (özet karar)

- Sıra: İŞ 5 (daraltılmış: Çoktan Seçmeli ısınma → Harfleri Diz/yazma; Boşluğu Doldur ve QuickMix refaktörü yok) → İŞ 4'ün yalnız cümle modeli/göç/arayüz kısmı → gerçek iki cihaz eşitleme testi → gerekirse ayrı anlam tanıtımı (sabit anlam kimliğiyle, ayrı tasarım).
- İŞ 5: yarıda bırakılan turda üretim sorusu kalan kelimeyi loglardan bulup sonraki Günlük Tekrar'a al; kayıt ve ilerleme stepID ile doğrulansın (gecikmiş onNext); kuyruk tasarımında tek yol seç (üretim ısınmadan sonra eklenir); ilerleme/sync benzersiz kelimeyle; Harfleri Diz Türkçe→İngilizce sorar, SPEC-MOTOR2 kararından sapma belgelenmeli.
- İŞ 4: newMeanings ve tanıtım kuyruğu ilk aşamadan çıkar; anlam metni kimlik değil; göç 'eksikse ekle' değil, işlenmiş sürüm/silme politikasıyla; tekrarlı cümle temizliği anlam bağlantısını korusun, eşitlikte UUID; sahipsiz cümle otomatik silinmesin; birleştirmede önce iki kelimenin example'ı cümleye dönüşsün, sonra ilişki taşınsın; openSerialized veri göçünü korumuyor.

---

# Plan: İŞ 4 (anlam–cümle modeli) ve İŞ 5 (Günlük Tekrar'da oyunlar)

Önerilen sıra: **önce İŞ 5**. Şemaya dokunmuyor ve riski düşük. İŞ 4'teki "yeni anlamı tanıtma" adımı, İŞ 5'in ısınma sorusunu kullanacak. Paralel ajanın (a), (b) ve (c) işlerinin bittiğini varsaydım.

---

## İŞ 5 — Günlük Tekrar'da oyunlar

**Bugünkü durum**
- iPhone'da Günlük Tekrar `RecallGameView(plan: .daily, mode: .dailyReview)` ile açılıyor (StudyView.swift:97). Her kelime yalnız yazarak soruluyor (RecallGameView.swift:47-48).
- Mac'te tur `MenuBarView`'de yaşayan kalıcı `StudySession` üzerinde dönüyor (MenuBarView.swift:15, MacStudyView.swift:30).
- Kuyruk `[Word]` (StudySession.swift:92). Yanlış bilinen kelime 2 kelime sonrasına yeniden giriyor (StudySession.swift:367, WordPicker.swift:77-79). Tur, kuyruk boşalınca bitiyor (StudySession.swift:436-437).

**Motorla uyum (doğruladım)**
- Aynı gün üretim cevabı varsa günün notu yalnız ondan çıkıyor (Memory.swift:193-195). Isınmada doğru, üretimde yanlış olursa kelime zayıflıyor (letters ceza katsayısı 0.85). Doğru–doğru olursa not üretimden geliyor.
- Isınmada yanlıştan sonra 30 dakika içinde gelen üretim doğrusu sayılmıyor (Memory.swift:187-190). Günün notu yalnız ısınmadaki yanlış kalıyor, yani "again". Tanıma yanlışının ceza katsayısı 0.7, bugünkü "cevaba baktı" durumundan biraz yumuşak. Bu kasıtlı ve kabul edilebilir.
- Zayıflığı Harfleri Diz de kaldırıyor, çünkü o da üretim sayılıyor (Memory.swift:275-276, 304).
- Yan etki: yeni kelime ilk gün Harfleri Diz ile iyi bilinirse dayanıklılığı 3.0 yerine 2.4 gün başlıyor (ağırlık 0.8).

**Veri modeli:** değişmiyor. Yeni şema alanı yok, göç yok.

**Mantık**
1. Yeni dosya `Shared/Logic/DailyMix.swift` (nonisolated, saf fonksiyonlar):
   - `enum StepKind { warmup(GameMode), production(GameMode) }`
   - `steps(for:deckMeanings:)` kelimenin adımlarını çıkarır:
     - Kelime yeni ya da zayıfsa (`isNew || isLapsed`) önce ısınma: Çoktan Seçmeli. Kelimenin cümlesinde boşluk açılabiliyorsa bazen Boşluğu Doldur. İkisi arasında seçim `QuickMix.modes` ile yapılır, aynı tür art arda en fazla iki kez gelir (QuickMix.swift:11-21).
     - Sonra üretim: kelime en fazla 14 harfliyse Harfleri Diz, değilse yazarak cevap (`.dailyReview`).
     - Vadesi gelmiş ama zayıf olmayan kelime: bugünkü gibi yalnız yazarak cevap (ağırlık 1.0, büyüme bozulmaz).
   - Geri dönüşler: farklı anlam sayısı 4'ten azsa ısınma yok, doğrudan üretim. Uzun ifadede üretim yazarak cevap. Oynanabilir türler `QuickMix.allowedModes` ile bulunur (QuickMix.swift:24-30).
   - `productionIndex(queueCount:)` üretim adımını en az 2–3 kelime sonraya koyar.
2. `StudySession` değişiklikleri:
   - Kuyruk `[Step]` olur (StudySession.swift:92). `current: Word?` hesaplanan özellik olarak kalır, böylece `RecallQuestionView` ve sayaçlar bozulmaz. Yeni `currentStep` eklenir.
   - `start` (132-165): kelime seçimi hiç değişmez (`dailyWords`, `dailyCount` 191-195 ve 259-270), yani 20 zayıf / 5 yeni sınırı korunur. Seçilen kelimeler adımlara açılır. Isınma adımları mümkünse son iki sıraya düşmez.
   - Karışım yalnız `.daily`, `.recent` (Tanış) ve `.extraPractice` turlarında açık. `.quick` ve `.reverse` aynen kalır; QuickMix'in ayrı oturumu da bu turları kullanıyor (QuickMixGameView.swift:161-163).
   - Yeni `answer(grade:)`: her cevabı gerçek oyun türüyle `ReviewRecorder.record(... mode: step.mode)` üzerinden kaydeder (GameRound.swift:72-84'teki desen). Isınmadan sonra üretim adımı kuyruğa girer. Üretimde yanlış olursa aynı üretim adımı `reinsertionIndex` ile yeniden girer.
   - `finishedWordCount` yalnız üretim adımı bitince artar. İlerleme göstergesi kelime sayısıyla kalır ("3/5"). Tur bitişi bugünkü gibi kuyruğun boşalmasıyla olur. Böylece her kelime turdan en az bir üretim cevabıyla çıkar.
   - `grade(known:)` ve `record` (348-389): yazarak cevapta değişmez, tür adımdan alınır.
   - `sync` (396-418): adımlar kelime kimliğiyle ayıklanır.
   - Tur özeti kaydı (`RoundEntry`, 384-386): "doğru" sayılması için hem ısınma hem ilk üretim cevabı doğru olmalı.
   - `stepAnswered` bayrağı: Mac'te seçmeli cevap verildikten sonra pencere kapanırsa, yeniden açılınca aynı soru ikinci kez kaydedilmesin; doğrudan sonraki adıma geçilir.

**Mevcut altyapıdan ne kullanılır**
- `QuickMixGameView`'deki soru tipi (7-18), soru üretimi `makeQuestion` ve `options(for:)` (127-153) ve görünüm seçimi `question(_:at:)` (74-110) `Shared/Games/MixQuestionView.swift` olarak dışarı alınır. Hızlı Tur da bunu kullanmaya devam eder.
- Olduğu gibi kullanılır:
  - `ChoiceQuestionView` (ChoiceGameView.swift:99-140; Mac'te 1–4 tuşları zaten var)
  - `LettersQuestionView` (LettersGameView.swift:83-285; klavyeyle yazma 153)
  - `ClozeCard` (FillBlankGameView.swift:105)
  - `GameWordCard` (ChoiceGameView.swift:146)
- `GameRound` kullanılmaz. Yeniden sorma, `sync`, açık cevabı saklama ve Mac'te kalıcı oturum onda yok; bunlar `StudySession`'da var.

**Arayüz**
- Yeni `Shared/Games/DailyStepView.swift`: adım türüne göre `RecallQuestionView`, `ChoiceQuestionView`, cloze kartı ya da `LettersQuestionView` gösterir. Her adımın kendi kimliği (`.id`) olur, böylece iç durum sıfırlanır.
- iPhone: RecallGameView.swift:47-48'de kullanılır. Mac: MacStudyView.swift:30'da kullanılır.
- Ayar düğmesi yok, yeni seçenek yok. Tahmini süre metni yeni hesaba göre değişir (StudyView.swift:131, MacGamesView.swift:134).

**Tur uzunluğu**
- Soru sayısı: 2 × (yeni + zayıf) + vadesi gelen (+ yeniden sorulanlar).
- Örnek: 5 yeni + 3 zayıf + 12 vadesi gelen → soru sayısı 20'den 28'e çıkar (+%40).
- Süre varsayımları: seçmeli 8 sn, Harfleri Diz 18 sn, yazma 25 sn. Bunlarla örnek tur yaklaşık 508 sn; bugün 500 sn. Sebep: ısınan kelimelerde yazma yerine daha kısa Harfleri Diz geliyor.
- En kötü durum (20 kelimenin hepsi ısınmalı): 40 soru, yaklaşık 520 sn.
- Harfleri Diz de 25 sn sürerse: örnek tur +64 sn (+%13), en kötü durum +160 sn (+%32).
- `RoundText.estimate` (RoundText.swift:9-12) tür başına saniyeyle hesaplar hâle gelir. Saniyeler kullanıcının kendi kayıtlarındaki cevap sürelerinden (`ReviewLog.responseTime`) ölçülüp ayarlanabilir.

**Testler**
- StudySessionTests:
  - Her kelimenin son cevap kaydı üretim türünde olmalı.
  - Isınan kelimenin kayıt türleri sırasıyla `choice` sonra `letters` olmalı.
  - Kuyruk izin verdiğinde üretim sorusu ısınmanın hemen arkasından gelmemeli.
  - 20/5 sınırı değişmemeli.
  - Uzun ifade ve 4'ten az anlamlı defter geri dönüşleri çalışmalı.
  - Silme `sync` ile adımlardan düşmeli.
  - `stepAnswered` ile aynı cevap iki kez kaydedilmemeli.
- DailyMixTests: saf kurallar.
- SameDayMemoryTests: seçmeli doğru + Harfleri Diz doğru → not Harfleri Diz'den; seçmeli yanlış + 5 dk sonra Harfleri Diz doğru → again.
- QuickMixTests: dışarı alınan kodla Hızlı Tur aynı davranmalı.

**Riskler**
- Mac'te cevap verildikten sonra pencerenin kapanması (bayrakla çözülüyor).
- `commitPendingAnswer` yalnız yazma sorusunu kapsıyor; seçmeli sorular cevap anında kaydedildiği için sorun yok.
- Son sıradaki ısınmalı kelimede ara kalmayabilir.

**İş sırası:** DailyMix → StudySession adımları → testler → MixQuestionView'i dışarı alma → DailyStepView → iPhone ve Mac → süre metni → iki cihazda deneme.

**Kullanıcıya sorulacaklar**
1. Isınma yalnız yeni ve zayıf kelimelere mi (önerim), yoksa vadesi gelen bütün kelimelere mi?
2. Vadesi gelen ama zayıf olmayan kelimeler yalnız yazarak mı sorulsun (önerim), yoksa ara sıra Harfleri Diz de gelsin mi?
3. Boşluğu Doldur da ısınma sorusu olarak gelsin mi?
4. Tanış turu da aynı karışımı kullansın mı?

---

## İŞ 4 — Anlam–cümle modeli

**Ayrı model mi, Word üzerinde JSON alan mı?**
- **JSON / Codable alan:** Basit; sıra ve eşleşme tek alanda duruyor. Ama iCloud alanı bütün olarak "son yazan kazanır" diye çözüyor: iki cihazda aynı anda cümle eklenirse biri kaybolur. Anlam adı değiştirmek ya da sıralamak da bütün alanı yeniden yazıyor.
- **Ayrı `@Model`:** Her cümle ayrı iCloud kaydı olduğu için eşzamanlı eklemelerin ikisi de kalıyor. Bedeli:
  - Tekrarlanan kopyaları temizlemek gerekiyor.
  - Sahipsiz kayıt süresi gerekiyor (cümle, kelimesinden önce gelebilir; cevap kayıtlarında bu zaten yapılıyor, StoreMaintenance.swift:51-66).
  - İçe aktarma sırası bazen karışabilir.
- **Öneri: ayrı model.** Eşzamanlı ekleme şartını ancak bu sağlıyor.

**Veri modeli**
- Yeni `Shared/WordSentence.swift`:
  - `text: String = ""`
  - `meaning: String = ""` (`Word.turkish` içindeki anlamın yazılışı; boşsa "anlamı belirsiz")
  - `createdAt: Date = .now`
  - `word: Word?`
- `Word`'e eklenecek alanlar (Word.swift:50 yanına):
  - `@Relationship(deleteRule: .cascade, inverse: \WordSentence.word) var sentences: [WordSentence]?`
  - `var newMeanings: String = ""` — çalışılmış kelimeye sonradan eklenen anlamlar; yalnız ekleme anında yazılır.
- `ReviewLog`'a eklenecek alan (ReviewLog.swift:17): `var meaning: String = ""` — sorunun hedef anlamı.
- `SharedStore.schema`'ya `WordSentence` eklenir (SharedStore.swift:20).
- Hiçbir alan silinmez, adı değişmez. `example` ilk cümlenin kopyası olarak kalır.

**Mantık**
- Yeni `Shared/Logic/WordSentences.swift`:
  - Değer tipi `ExampleSentence` ve `Word.exampleSentences`: kayıtlar `createdAt` sırasıyla döner. Hiç kayıt yoksa ve `example` doluysa tek bir "belirsiz" cümle döner. Böylece göçten önce de her şey çalışır.
  - `sentence(for:)`, `clozeSentences`, `addSentence`.
- `example` alanına yalnız kullanıcının kendi işlemi yazar: ilk cümle silinirse ya da düzenlenirse. Değer farklıysa yazılır (MemoryCache.swift:46-61'deki gibi), gereksiz iCloud yazımı olmaz.
- Göç: `SentenceMigration.migrateIfNeeded`, SharedStore.swift:45-48'de ve öne gelişteki bakımda çalışır (iPhone'da ContentView, Mac'te MacGamesView.swift:45-51).
  - Kural yalnız ekleme yapar: `example` dolu ve hiçbir cümle ona eşit değilse (sadeleştirilmiş metinle), `example` bölünmeden "belirsiz" cümle olarak eklenir; `createdAt` kelimeninki olur, böylece ilk sırada durur.
  - Böylece göç tekrar çalışsa da bir şey bozulmaz.
  - Eski sürümdeki bir cihazın düzenlediği `example` de yeni cümle olarak gelir.
  - Veri göçü kilide gerek duymaz; şema göçü zaten `openSerialized` içinde yapılıyor (SharedStore.swift:36).
- Tekrarlanan cümleler: `StoreMaintenance.run` (StoreMaintenance.swift:44-49 sonrası) aynı kelimede aynı metinli cümleleri tek kayda indirir. Anlamı dolu olan, sonra en eski olan kalır. İki cihazda aynı anda göç olursa sonuç böyle toparlanır.
- Sahipsiz cümleler: cevap kayıtlarındaki süre mantığı (StoreMaintenance.swift:51-66) cümlelere de uygulanır.
- Çift kelime birleştirme (`merge`, StoreMaintenance.swift:129-137): cümleler kalan kayda taşınır. Paralel ajanın `mergedExamples` kodu (satır 131) yalnız cümle kaydı olmayan kelimelere uygulanmalı. Yoksa satır sonuyla birleştirilmiş metin göçte ayrı bir kopya olarak geri gelir.
- `absorb` (paralel ajanın yeni WordMatcher.swift:63-68 kodu):
  - Gelen cümle kelimede yoksa eklenir; yeni eklenen anlama bağlanır.
  - Kelime çalışılmışsa eklenen anlam `newMeanings`'e yazılır.
  - (a)'daki "mevcut ya da yeni cümleden birini seç" seçimi gereksizleşir; varsayılan "ikisini de tut" olur.
- Sorularda ipucu:
  - `StudySession.advance` (StudySession.swift:436-444) hedef anlamı seçer: tanıtılmayı bekleyen anlam önce, yoksa (c)'deki sırayla dönüş.
  - İpucu cümlesi o anlamın cümlesidir. Anlamın cümlesi yoksa, "belirsiz" cümle yalnız kelimede anlama bağlı cümle hiç yoksa gösterilir.
  - Değişecek yerler: RecallGameView.swift:229-233 ve 246; `GameWordCard` (ChoiceGameView.swift:168) hedef anlamın cümlesini parametre olarak alır.
- Boşluğu Doldur, cümlelerde boşluk açılabilenler arasından rastgele seçer: FillBlankGameView.swift:65-68, QuickMix.swift:27, QuickMixGameView.swift:133. `GameDeck` girdisi cümle yerine "boşluk açılabilir mi" bilgisi alır (GameMode.swift:119-121, StudyView.swift:118, MacGamesView.swift:228).

**Açık sorun: yeni anlam eski hafıza yüzdesini devralıyor — seçenekler**
1. Hiçbir şey yapma, yalnız (c)'deki dönüş. Güçlü kelimede yeni anlam haftalarca sorulmaz.
2. Anlam eklenince hafızayı sıfırla. Bilinen anlamı cezalandırır.
3. Anlam başına ayrı hafıza (`ReviewLog.meaning` ile motoru anlam başına oynatmak). Motor ve istatistikler bölünür; ağır iş.
4. **Önerim: basit tanıtım kuyruğu.**
   - Bekleyen anlamlar = `newMeanings` eksi, o anlamla doğru cevaplanmış kayıtlar. Durum eklemeye açık cevap kayıtlarından çıkar; aynı alana iki cihazın yazması sorun olmaz.
   - Bekleyen anlamı olan kelime, İŞ 5'in ısınma sorusuyla Günlük Tekrar'a girer (o anlam doğru şık olur) ve 5 yeni kelime sınırından yer kullanır (`dailyCount`, StudySession.swift:259-270).
   - Yanlış cevap kelimeyi zayıflatır; bu doğru bir sonuç, çünkü kelime tam bilinmiyor. Motor değişmez.

**Arayüz**
- `WordFormView` (iPhone ve Mac düzeni `macFields`): "Cümleler" bölümü. Her satırda cümle ve anlam seçici (anlamlar + "Belirsiz"). Anlam seçici yalnız kelimenin 2 ya da daha fazla anlamı varsa görünür. Silme: iPhone'da kaydırarak, Mac'te – düğmesiyle. Mac'te düğmeler formun altında.
- `WordDetailView.swift:49-57`: "Kitaptaki Cümleler" başlığı altında anlama göre gruplanmış liste; anlam vurgu renginde. Belirsiz olanlar "Anlamı belirtilmemiş" altında.
- Mac tablosu (WordsWindow.swift:23-40): "Cümle" sütunu — ilk cümle tek satır, yanında "+2" gibi sayı.

**Testler**
- SentenceMigrationTests:
  - Göç iki kez çalışınca sonuç değişmemeli.
  - Çok satırlı alıntı tek parça taşınmalı.
  - İki cihaz aynı anda göç yapınca kopya temizliği tek cümlede birleşmeli.
  - `example` alanına yazma kuralları doğru çalışmalı.
- WordMatcherTests: `absorb` cümle ve `newMeanings` ekliyor mu.
- StoreMaintenanceTests: birleştirmede cümleler taşınıyor mu; sahipsiz cümle süresi doluncaya kadar silinmiyor mu.
- Bekleyen anlam hesabı; boşluk açılabilir cümle seçimi; `GameDeck` sayımı.
- Elle deneme: eski depo üstüne kurulum yaparken widget açık olsun (göç kilidi denenmiş olur).

**Riskler**
- CloudKit şemasındaki yeni kayıt türü ve alanlar TestFlight / App Store öncesi üretim ortamına aktarılmalı.
- Eski sürümdeki bir cihaz `example`'ı silerse cümle kayıtları silinmez; kural yalnız ekleme yapıyor.
- Anlamın adı değişince bağlantı kopar ve cümle belirsize düşer. Form, adı değişen anlamı yeniden bağlamayı önermeli.
- Mac tablosunda cümle sayısını göstermek her kelimenin ilişkisini yükler; yüzlerce kelimede sorun olmaz.

**İş sırası:** model ve şema → WordSentences + göç + bakım + birleştirme → `absorb` → testler → ipucu, Boşluğu Doldur ve GameDeck → form, ayrıntı, Mac tablosu → tanıtım kuyruğu (İŞ 5'ten sonra) → iki cihazda eşitleme denemesi.

**Kullanıcıya sorulacaklar**
1. Yazarak cevapta, ipucu cümlesi başka bir anlamı gösterirken yazılan anlam da doğru sayılsın mı? (Önerim: evet.)
2. Yeni anlam tanıtımı 5 yeni kelime sınırından yer kullansın mı?
3. Yeniden eklemede cümle seçimi yerine "ikisini de tut" varsayılan olsun mu? (Bu, (a)'daki seçimi kaldırır.)

---

### Critical Files for Implementation
- Shared/Logic/StudySession.swift
- Shared/Games/QuickMixGameView.swift
- Shared/Word.swift
- Shared/Logic/StoreMaintenance.swift
- Shared/Games/RecallGameView.swift
---

## Ek: Codex değerlendirmesinin tam metni

**İŞ 5 değişiklikle uygulanabilir; İŞ 4 mevcut hâliyle sorunlu.** Önce daraltılmış İŞ 5 mantıklı; ancak “şemaya dokunmuyor, dolayısıyla düşük riskli” sonucu doğru değil. Çalışma ağacını ve geri bildirim dosyasını okudum; dosya değiştirmedim, test çalıştırmadım.

**İŞ 5 — Değişiklikle uygulanabilir**

- **Motor yorumunda cezanın yönü ters:** `0.7`, kalan dayanıklılığı küçültür; tanıma yanlışı, yazma yanlışından **daha serttir**. “Cevaba baktı” da tek başına yanlış değildir: ardından “Bildim” seçilirse `hard` olur. Bkz. [Memory.swift:242](/Shared/Logic/Memory.swift:242), [GradeOption.swift:47](/Shared/Logic/GradeOption.swift:47).
- **30 dakika açıklaması koşullu doğru:** seçmeli yanlış → beş dakika sonra üretim doğrusu, başka cevap yoksa `again` bırakır. Fakat günün daha önceki geçerli üretim doğrusu varsa sonuç değişebilir; motor bütün günü değerlendirir. Harfleri Diz’in zayıflığı kaldırması da farklı gün koşuluna bağlıdır. [Memory.swift:179](/Shared/Logic/Memory.swift:179), [Memory.swift:273](/Shared/Logic/Memory.swift:273).
- **En önemli eksik: yarıda bırakma.** Yeni kelimeye yalnız ısınmada doğru cevap verilip çıkılırsa dayanıklılık/vade oluşur; yeniden açılan Günlük Tekrar o kelimeyi seçmeyebilir. Dolayısıyla “her kelime üretimle çıkar” ancak tamamlanan oturum için geçerli. Yeniden girişte tamamlanmamış üretimi loglardan bulma veya oturumu sürdürme kuralı gerekli. [Memory.swift:223](/Shared/Logic/Memory.swift:223), [StudySession.swift:191](/Shared/Logic/StudySession.swift:191).
- **`stepAnswered` tek başına yeterli değil.** Seçmeli ve harf sorularının 0,8 saniye sonra çalışan görevleri, pencere yeniden açıldıktan sonra eski `onNext` çağrısını çalıştırabilir. Hem kayıt hem ilerleme `stepID` ile doğrulanmalı; soru/şıklar oturumda sabitlenmeli. QuickMix’te ilerleme koruması zaten var. [ChoiceGameView.swift:131](/Shared/Games/ChoiceGameView.swift:131), [QuickMixGameView.swift:170](/Shared/Games/QuickMixGameView.swift:170).
- **Kuyruk tasarımında iki alternatif karışıyor:** adımlar başlangıçta mı açılıyor, üretim ısınmadan sonra mı ekleniyor? Birini seçin; aksi hâlde çift üretim riski var. İlerleme ve silme hesabı adım sayısından değil benzersiz kelimelerden yapılmalı; mevcut `sync` çıkarılan kuyruk öğesi kadar azaltıyor. [StudySession.swift:399](/Shared/Logic/StudySession.swift:399).
- **Referansların çoğu doğru, bazı garantiler yanlış:** yeniden sorma yalnız kuyrukta en az iki öğe varsa olur; `[Step]` sonrasında bu, iki farklı kelime demek değildir. `QuickMix.modes` da tek seçenek kaldığında “en fazla iki tekrar” kuralını ihlal edebilir. Sınır **toplam 20, bunun en fazla 5’i yeni**. [WordPicker.swift:75](/Shared/Logic/WordPicker.swift:75), [QuickMix.swift:15](/Shared/Logic/QuickMix.swift:15), [StudySession.swift:267](/Shared/Logic/StudySession.swift:267).
- **Harfleri Diz yalnız biçim değişikliği değil:** Türkçe → İngilizce soruyor; mevcut günlük yazma İngilizce → Türkçe. Motor ikisini üretim saysa da aynı beceriyi ölçmüyor. Ayrıca harf sorusunu yeniden sormak mevcut SPEC kararını değiştiriyor; bu değişiklik açıkça belgelenmeli. [LettersGameView.swift:174](/Shared/Games/LettersGameView.swift:174), [SPEC-MOTOR2.md:1046](/docs/SPEC-MOTOR2.md:1046).
- **Daha basit başlangıç:** Çoktan Seçmeli → Harfleri Diz/yazma; ilk sürümde Boşluğu Doldur ve geniş QuickMix refaktörü olmasın. Mevcut soru bileşenleri kullanılabilir; kayıt sorumluluğu `StudySession`da kalsın. Özetin başlangıç durumu ısınmadan önce alınmalı, tamamlanmamış kelime “başarılı” sayılmamalı.
- **Süre hesabının aritmetiği doğru, “en kötü durum” etiketi yanlış:** 520 saniye yalnız tekrar olmayan, harfe uygun senaryo. Uzun ifadeler ve yanlışlar süreyi artırır. `responseTime`, cevap sonrası beklemeyi kapsamaz; gerçek tur süresiyle de ölçün. Testlere yarıda bırakma, eski callback, tek/iki kelimelik kuyruk, önceki günlük cevap ve 04:00 geçişini ekleyin.

**İŞ 4 — Mevcut hâliyle sorunlu; cümle saklama kısmı ayrıştırılarak uygulanabilir**

- **Ayrı `@Model` tercihi makul; “eşzamanlı eklemeleri ancak bu sağlar” fazla kesin.** Tek JSON alanı otomatik olarak eleman bazında birleşmez; ayrı kayıtlar eklemeleri ayırır ama düzenleme/silme çatışmalarını çözmez. İsteğe bağlı ilişki doğru; CloudKit ilişkileri atomik işlemez, benzersizlik kısıtı da desteklemez. [Apple’ın SwiftData eşitleme kuralları](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).
- **`newMeanings: String` tasarımın kendi gerekçesiyle çelişiyor:** iki cihaz farklı anlam eklediğinde bu alan ve mevcut `turkish` alanı çatışabilir. Sonradan logları çıkarmak, başta kaybolan eklemeyi geri getirmez. İlk aşamadan `newMeanings` ve tanıtım kuyruğunu çıkarın; kalıcı tanıtım gerekiyorsa ayrı, kimlikli anlam/ekleme kaydı tasarlayın. Mevcut birleştirme de aynı metin alanını yeniden yazıyor. [WordMatcher.swift:63](/Shared/Logic/WordMatcher.swift:63).
- **Anlam metni kimlik olamaz:** yeniden adlandırma, silip yeniden ekleme ve aynı anlamın farklı yazımı eski loglarla yanlış eşleşir. Silinen anlamın geçmiş doğrusu yeni tanıtımı kapatabilir. Kalıcı öğrenme takibi için sabit anlam kimliği ve eklenme zamanı gerekir; yalnız cümle etiketi için metin kullanılacaksa bu sınır açık olmalı.
- **“Göç idempotent” yalnız dar bir senaryoda doğru.** İlk cümle düzenlenirken `example` ve cümle kaydı farklı zamanlarda gelirse eski metin yeniden içe alınabilir; son cümle silindikten sonra eski cihaz onu diriltebilir. `example` aynası ile eski veriyi içe alma ayrı kurallara bağlanmalı; göç kaynağı/işlenmiş sürüm ve silme politikası olmadan sürekli “eksikse ekle” yeterli değil.
- **Tekrarlı cümle temizliği veri kaybedebilir:** aynı metin farklı anlamlara bağlanmış olabilir. Yalnız metne göre silmeyin; anlam bağlantısını koruyun. `createdAt` eşitliğinde kalıcı UUID gibi ortak bağlayıcı sıralama gerekir; aynı tarihle göç eden kayıtların cihazlarda farklı seçilip karşılıklı silinmesi önlenmeli.
- **Sahipsiz kaydı bir saat sonra silmek güvence değil.** Mevcut cevap temizliği de yalnız bir zaman varsayımıdır; gecikmiş ilişkiyi gerçek silmeden ayıramaz. Kullanıcının cümlelerini ilişki yok diye otomatik silmek yerine korumayı tercih ederim. [StoreMaintenance.swift:18](/Shared/Logic/StoreMaintenance.swift:18).
- **`openSerialized` veri göçünü korumuyor:** kilit yalnız container açılışında; önerilen cümle göçü sonrasında çalışacak. Üstelik kilit alınamazsa beş saniye sonra kilitsiz devam ediliyor. Tüm hedeflerin aynı şemayı kullanması doğru; eski depo, eşzamanlı widget/paylaşım açılışı ve kayıt hatası ayrıca sınanmalı. [SharedStore.swift:36](/Shared/SharedStore.swift:36), [SharedStore.swift:75](/Shared/SharedStore.swift:75).
- **Birleştirme sırası değişmeli:** her iki Word’ün eski `example` verisini önce bağımsız cümleye dönüştürün, ilişkileri taşıyın, sonra kopya Word’ü silin. Yalnız “cümle kaydı varsa `mergedExamples` çalışmasın” demek, diğer kayıttaki henüz göçmemiş cümleyi kaybettirebilir. [StoreMaintenance.swift:129](/Shared/Logic/StoreMaintenance.swift:129).
- **Tanıtım bütün yazma yollarını kapsamalı:** yalnız `absorb` yeterli değil; düzenleme formu doğrudan `turkish` yazıyor. Eski istemci de `newMeanings` üretmez. Ayrıca mevcut günlük bütçe ilk kelime logunu sayar; yeni anlamlar, kart/rozet/bildirim hesaplarıyla birlikte ele alınmadan “5’ten yer kullanır” gerçekleşmez. [WordFormView.swift:737](/Shared/WordFormView.swift:737), [StudySession.swift:272](/Shared/Logic/StudySession.swift:272).
- **Hedef anlam uçtan uca taşınmalı:** cümle, doğru şık, harf kartı ve log aynı hedefi kullanmalı. `ClozeCard` hâlâ ilk anlamı, Harfleri Diz bütün anlamları gösteriyor. Başka anlamla verilen doğru cevabı hedef anlama yazmak tanıtımı yanlış kapatır. Çoklu yeni anlamda gelen cümleyi otomatik birine bağlamayın. [FillBlankGameView.swift:116](/Shared/Games/FillBlankGameView.swift:116).
- **Uyumluluk testleri eksik:** iki gerçek cihazda çevrimdışı ekleme, eşzamanlı göç/temizlik, düzenleme–silme çatışması, gecikmiş ilişki, eski sürümün `example` düzenlemesi ve uygulama açıkken gelen eşitleme gerekli. Mevcut uzak değişiklik gözlemcisi yalnız hafızayı yeniliyor. [MemoryCache.swift:69](/Shared/Logic/MemoryCache.swift:69).

**Kullanıcıya sorulacaklar için önerim**

- **İŞ 5:** ① Isınma yalnız yeni/`isLapsed`; ② diğer vadeli kelimeler yazma; ③ Boşluğu Doldur ilk sürümde yok; ④ Tanış aynı karışımı kullansın. Bunlar kapsamı ve motor etkisini daha anlaşılır tutar.
- **İŞ 4:** ① Genel kelime sorusunda başka geçerli anlam doğru sayılsın, fakat hedef anlam öğrenildi diye kaydedilmesin; ② tanıtım kuyruğu yapılınca yeni anlamlar ortak 5 tanıtım bütçesini kullansın; ③ farklı cümlelerde varsayılan **ikisini de tut**, aynı cümlede tekrar oluşturma olsun.

**İş sırası:** Devam eden düzeltmelerin tamamlandığını doğrula → daraltılmış İŞ 5 ve oturum testleri → İŞ 4’ün yalnız cümle modeli/göç/arayüz kısmı → gerçek eşitleme testleri → gerekirse ayrı anlam tanıtımı. İncelediğim kopyada `ChoiceQuiz` hâlâ `firstMeaning` kullanıyor; dönüşümlü anlam işinin bittiği varsayımı henüz geçerli değil. [ChoiceQuiz.swift:18](/Shared/Logic/ChoiceQuiz.swift:18).