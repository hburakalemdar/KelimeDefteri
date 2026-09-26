# Spec: Yeni anlam tanıtımı

Durum (2026-09-26): uygulandı (bkz. §9 uygulama notları). Kaynak: `docs/GOREV-YENI-ANLAM.md`, `docs/PLAN-CUMLE-OYUN.md` (İŞ 4 "Açık sorun" + Codex
itirazları). İlgili: `docs/SPEC-CUMLE.md`, `docs/SPEC-OYUN.md` §5.11.

## 0. Sorun ve ana fikir

Çalışılmış kelimeye sonradan eklenen anlam, kelimenin hafızasını devralıyor; güçlü kelimede haftalarca sorulmuyor.

Ana fikir: **"Bekleyen anlam" hiçbir yere yazılmaz, veriden çıkarılır.** Kelime ilk çalışıldığında o anki anlamları bir
kez "taban" olarak kaydedilir. Sonra kelimede olup tabanda olmayan ve hiç doğru cevaplanmamış anlam bekleyen anlamdır.
Böylece hangi yoldan eklenirse eklensin (form, Anlamları Ekle, başka cihaz, eski sürüm) yakalanır; iki cihazın aynı
alana farklı değer yazıp çakışması olmaz (taban yalnız boşken bir kez yazılır, cevap kayıtları yalnız eklenir).

## 1. Model (CloudKit: hepsi varsayılanlı, silme/ad değişikliği yok)

- `Word.meaningBaseline: String? = nil` — kelime ilk çalışıldığında `turkish`'in kopyası. `nil` = henüz alınmadı.
  **Yalnız `nil` iken yazılır**, bir daha değişmez.
- `ReviewLog.meaning: String = ""` — cevabın gösterdiği anlam (yazıldığı gibi). Boş = belirli bir anlam yok.
- `ReviewLog.isIntro: Bool = false` — tanıtım cevabı: hafıza motoru bunu **hiç oynatmaz** (bkz. §4).

## 2. Bekleyen anlam (`Word.pendingMeanings`)

- Kelime yeni (`isNew`) ya da `meaningBaseline == nil` → boş.
- Değilse: `ChoiceQuiz.displayMeanings(turkish)` sırasıyla; sadeleştirilmiş (`AnswerChecker.fold`) hâli tabanın
  anlamları arasında olmayan **ve** `correct == true` olup `fold(log.meaning)` kendisine eşit bir kaydı olmayan anlamlar.
- Anlam silinirse listeden kendiliğinden düşer.
- **Metin kimliğinin bilinen sonuçları (kasıtlı, hepsi "fazla sormak" yönünde):** anlamın yazımı düzeltilir ya da
  yeniden adlandırılırsa yeni yazılış bekleyen olur → bir tanıtım sorusu fazladan sorulur. Silinip yeniden eklenen
  anlam tabandaysa ya da önceden doğru bilinmişse bekleyen olmaz (zaten biliniyordu). Aynı kelimede aynı yazılışlı iki
  farklı anlam olamaz. Böylece metin kimliği hiçbir zaman öğrenilmemiş anlamı "öğrenildi" saymaz.

## 3. Tabanın yazıldığı yerler (bütün yazma yolları)

Ortak yardımcı `Word.fillMeaningBaselineIfNeeded()` (çalışılmışsa ve `nil` ise `turkish`'i yazar; yenide dokunmaz):
1. `ReviewRecorder.record`, kayıt eklenmeden **önce** (ilk cevapta taban = o anki anlamlar; eklentiler, widget, bildirim
   cevabı da buradan geçer). Yeni kelimede de ilk kayıttan önce yazılır: burada "çalışılmış" şartı aranmaz.
2. `turkish`'i değiştiren her yol, değiştirmeden **önce**: düzenleme formunun kaydı (`WordFormView`, iOS + Mac),
   `WordMatcher.absorb` (Paylaş/eylem eklentisi, ⇧⌘E dahil). Böylece eski (tabansız) kelimeye eklenen anlam tabana
   yutulmaz.
3. Göç: `StoreMaintenance.run` çalışılmış (`!isNew`) ve tabanı `nil` olan kelimeye yazar (eski kelimeler).
4. Kopya kelime birleştirme: kalan kaydın tabanı = iki kelimenin tabanlarının birleşimi (tabanı `nil` ama çalışılmış
   olanın tabanı kendi `turkish`'i, hiç çalışılmamışınki boş). Böylece yeni kopyadan gelen anlam tanıtılır.

Sınır: eski sürüm tabansız, çalışılmış bir kelimeye anlam eklerse ve yeni sürüm bunu ilk kez o hâliyle görürse, anlam
tabana girer (tanıtılmaz). Yalnız geçiş anında olabilir.

## 4. Tanıtım cevabı ve hafıza

- `ReviewRecorder.record(..., meaning:)` yeni parametre (varsayılan `""`). `isIntro` burada merkezî hesaplanır:
  tür **tanıma** (`!mode.isProduction`) **ve** `meaning` kaydın eklenmesinden önce `pendingMeanings` içindeyse `true`.
- Motor `isIntro` kayıtlarını atlar (`MemoryCache` cevap listesini kurarken). Gerekçe: yeni anlamı bilmemek kelimeyi
  unutmak değil; güçlü kelime tanıtımda yanlış yaptı diye zayıflamamalı. Doğru tanıtım da hafızayı büyütmez.
- Kayıt sayısı, geçmiş noktaları, "Görülme" ve `meaningTurn` tanıtım kaydını sayar (gerçek bir cevap).
- `isPendingProduction` değişmez (tanıtım kaydı da `choice` türünde; zayıf kelimede ısınma gibi davranır).

**Hangi kayda hangi anlam yazılır:**
- Seçmeli sorular (Günlük Tekrar ısınması, Çoktan Seçmeli, Boşluğu Doldur, Hızlı Tur'un seçmelileri, widget, bildirim
  cevabı): doğru şıkkın anlamı (soru kurulurken alınan).
- Yazarak cevap (İngilizce → Türkçe): yazılan cevap bir anlamla eşleşiyorsa **o anlam** (başka anlamla verilen doğru
  cevap sorulan anlamı kapatmaz); yanlışta, bakmada ve "Doğru Say" gibi elle notlamada sorulan anlam (`questionMeaning`).
  Üretim türü olduğu için hiçbir zaman `isIntro` değildir; yazılan cevap bekleyen anlamsa doğru kayıt onu kapatır.
- Harfleri Diz, Ters Yön, Eşleştir: `""` (belirli bir anlam göstermiyor ya da hepsini gösteriyor). Eşleştir'de kolaysa
  gösterilen anlam yazılabilir; zorunlu değil.

## 5. Hangi anlam sorulur

- `Word.askedMeaning` / `askedCandidate`: bekleyen anlam varsa **ilk bekleyen**, yoksa bugünkü dönüş (`meaningTurn`).
  Tanıma oyunları ve widget bunu kullanır → tanıtım her yerde olabilir, her yerde doğru işaretlenir.
- Yeni `Word.productionMeaning`: dönüş, bekleyen anlamlar hariç (hepsi bekleyense bütün anlamlar). Günlük Tekrar'ın
  yazarak cevap sorusu `questionMeaning`'i bundan alır: üretim sorusu bilinen bir anlamla sorulur, ipucu cümlesi onunki.
- Hedef anlam soru → şık → ipucu cümlesi → kayıt boyunca aynı değerdir (adım kurulurken sabitlenir).

## 6. Günlük Tekrar'da tanıtım

**Tanıtıma uygun kelime (`Word.needsMeaningIntro(now:)`):** `pendingMeanings` dolu **ve** bugün (04:00) `isIntro`
kaydı yok (yanlış tanıtım aynı gün tekrarlanmaz; widget'ta yapılmışsa da bugün tekrar sorulmaz) **ve** defterde en az 4
farklı anlam var (`DailyMix.minimumMeanings`).

**Adımlar (`StudySession.steps`, karışık turlar: Günlük Tekrar, Tanış, Yine de Çalış):**
- Tanıtıma uygun kelimenin ilk adımı Çoktan Seçmeli, doğru şık ilk bekleyen anlam (`askedCandidate`). Bu adım ısınma
  gibi sıralanır (`DailyMix.order`).
- Cevaptan sonra: kelime zayıfsa ya da üretim bekliyorsa üretim adımı (`productionKind`), vadesi gelmişse yazarak
  cevap, ikisi de değilse (yalnız tanıtım için girdi) başka adım yok, kelime turdan çıkar. Ekleme yeri bugünkü gibi
  araya en az iki kelime.
- Tanıtım yeniden sorulmaz (ısınma gibi).
- Şık kurulamazsa (3 çeldirici yok): vadesi gelmiş kelime normal adımıyla sorulur; yalnız tanıtım için gelen kelime
  turdan düşer (`wordCount` düzeltilir).
- Yeni kelimede bekleyen anlam olmaz (taban ilk cevapta alınır), yani yeni kelime akışı değişmez.

**"5 yeni" bütçesi = günde 5 tanışma** (yeni kelime ya da yeni anlam):
- `introducedToday` = ilk kaydı bugün olan kelimeler + ilk kaydı daha eski olup bugün `isIntro` kaydı olan kelimeler.
- Bütçe havuzu (`dailyCount`'un `new` sayısı): hiç çalışılmamış kelimeler + **yalnız tanıtım için gelecek** kelimeler
  (tanıtıma uygun, vadesi gelmemiş, üretim beklemeyen). Vadesi gelmiş/üretim bekleyen kelimenin tanıtımı zaten
  `weak` içinde sorulur, havuzdan yer almaz (ama cevaplanınca `introducedToday`'e girer).
- Seçim sırası: önce yeni anlamlar (tanıtıma uygun kelimeler, `createdAt` eskiden yeniye), sonra yeni kelimeler
  (bugünkü gibi en eski eklenen). `dailyNewWords` bu birleşik listeyi döner.
- `recentWords` / `recentWaitingCount` yalnız **yeni kelimeleri** sayar: alınan yeni kelime sayısı = `new` − alınan
  anlam sayısı. Tanış turu yeni anlam almaz; bütçeye sığmayan anlamlar ertesi günü bekler.
- `dailyCount(weak:new:introducedToday:)` imzası ve tuple aynı kalır → rozet, bildirim (`ReminderScheduler`,
  `ReminderPlanner`'ın `newCount`'u: yeni kelimeler + yalnız tanıtım için gelecek kelimeler), widget özeti ve kart
  aynı sayıyı gösterir.
- Kart metni (iOS `StudyView.dailyText`, Mac `MacGamesView`): yeni anlam varsa "yeni kelime"den ayrı yazılır
  ("1 yeni anlam"); metin `RoundText`'te. Tahmini süre: tanıtım adımı seçmeli süresi (+ varsa normal adımı).

## 7. Arayüz

- Tanıtım sorusu normal Çoktan Seçmeli kartıdır; kartın üstünde küçük bir "Yeni anlam" etiketi (vurgu rengi, sistem
  parçası) görünür ki kullanıcı neden güçlü kelimenin sorulduğunu anlasın. iOS ve Mac.
- Kelime ayrıntısı: bekleyen anlam varsa anlam listesinde / başlıkta küçük "Yeni" notu (varsa kolay bir yer; yoksa
  atlanabilir).

## 8. Testler (Swift Testing)

- Taban: ilk kayıtta yazılır, bir daha değişmez; göç eski çalışılmış kelimeye yazar, yeniye yazmaz.
- Form ve `absorb` tabansız çalışılmış kelimeye anlam eklerken önce tabanı eski anlamlarla doldurur → yeni anlam bekleyen.
- Bekleyen: yalnız aynı anlamla doğru kayıt kapatır; başka anlamla doğru, aynı anlamla yanlış kapatmaz; silinen anlam
  düşer; yazım düzeltmesi bekleyen olur.
- `isIntro`: tanıma + bekleyen anlam → true; üretim → false. Güçlü kelimede yanlış tanıtım hafızayı değiştirmez.
- Yazarak cevapta yazılan anlam kaydedilir (başka anlam yazılınca o).
- Günlük Tekrar: vadesi gelmemiş güçlü kelime yalnız tanıtımla girer ve tek adımda çıkar; vadesi gelmişte tanıtım +
  yazarak; aynı gün ikinci kez girmez; bütçe: 5 yeni kelime + 2 yeni anlam → 2 anlam + 3 kelime; `recentWaitingCount`
  doğru; `introducedToday` tanıtımı sayar.
- Birleştirme: tabanlar birleşir.

## 9. Uygulama notları (2026-09-26)

Belgede açık olmayan, uygulamada verilen kararlar:
- `Word.needsMeaningIntro(now:)` yalnız bekleyen anlama ve bugünkü tanıtım kaydına bakar; "defterde en az 4 farklı
  anlam" şartına çağıran bakar (`StudySession.introOnlyWords`, `steps`, `dailyEstimate`), çünkü kelime defteri bilmez.
- `productionMeaning` yalnız Günlük Tekrar'da değil, `StudySession`'ın bütün yazarak cevap ve harf adımlarında
  `questionMeaning` olur (Hızlı Tur'un, Ters Yön'ün, Zayıflar'ın yazarak sorusu da üretimdir).
- Yazarak cevapta tutan anlam: sorulan anlam tutuyorsa o, değilse kayıttaki sırayla ilk tutan (`Word.matchedMeaning`).
  Ters Yön kaydı `""`.
- Yine de Çalış'ta (ve kendisi için seçilmiş her kelimede) tanıtımın ardından yazarak cevap gelir; "başka adım yok"
  yalnız Günlük Tekrar'ın bütçeden aldığı yalnız-tanıtım kelimeleri içindir. Bu kelime tur özetine tanıtım cevabıyla girer.
- Boşluğu Doldur kaydına ipucu (gösterilen Türkçe anlam), Eşleştir kaydına kutuda gösterilen anlam yazılır.
- `StoreMaintenance.Summary.meaningBaselines`: göçte taban alınan kelime sayısı (kaydı tetikler).
- Birleştirmede hiçbir kopya çalışılmamışsa taban `nil` kalır.
- Kelime ayrıntısı (iOS): anlamların altında "Yeni: …" notu. Mac'in Kelimelerim tablosuna eklenmedi.
- Bildirim planı (`ReminderScheduler`): `newCount` = yeni kelimeler + yalnız tanıtım için gelecek kelimeler; ileri
  günler için bu sayı sabit varsayılır (yaklaşık).
- Kasıtlı: yanlış tanıtımdan sonra aynı gün Günlük Tekrar tanıtımı yeniden sormaz, ama başka tanıma oyunları ve
  widget bekleyen anlamı göstermeye devam eder ve kayıtları yine `isIntro` olur (hafızaya işlenmez).
- Seçmeli adım (ısınma ya da tanıtım) yanlış da olsa yeniden sorulmaz; yalnız takip adımı eklenir, yalnız-tanıtım
  kelimesi doğru/yanlış fark etmeden turdan çıkar.
- Kilit ekranı özeti yeni anlamları ayrı yazar ("2 yeni kelime · 1 yeni anlam").
