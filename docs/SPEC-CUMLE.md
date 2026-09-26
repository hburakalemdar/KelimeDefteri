# Spec: Çok cümleli kelimeler (İŞ 4, yalnız cümle modeli)

Durum (2026-09-26): uygulandı. Kaynak: `docs/PLAN-CUMLE-OYUN.md` İŞ 4 + Codex değerlendirmesi.
Kapsam dışı (sonraya): yeni anlam tanıtımı, `newMeanings`, `ReviewLog.meaning`, sabit anlam kimliği.

## 1. Model

- Yeni `@Model WordSentence` (`Shared/WordSentence.swift`): `sentenceID: String = UUID().uuidString` (kalıcı,
  her cihazda aynı; eşitlikte sıralama bağlayıcısı), `text = ""`, `meaning = ""` (boş = anlamı belirsiz),
  `createdAt = .now`, `word: Word?`. Bütün alanların varsayılanı var (CloudKit).
- `Word`'e: `sentences: [WordSentence]?` (cascade, isteğe bağlı ilişki) ve `exampleMirror: String? = nil`.
  Hiçbir alan silinmedi, adı değişmedi. `SharedStore.schema` = `[Word, ReviewLog, WordSentence]`; iOS uygulaması,
  KelimeEkle, KelimeEylem, KelimeWidget, Mac ve testler aynı `SharedStore.schema`yı kullanır.
- Sıra: `createdAt`, eşitse `sentenceID`. "İlk cümle" bu sıradaki ilktir.
- **`example` = ilk cümlenin aynası** (eski istemciler yalnız onu görür). Yeni istemci `example`'a yazdığı değeri
  `exampleMirror`'a da yazar; ikisi aynı Word kaydında birlikte eşitlenir. Yazım yalnız değer farklıysa yapılır.
- Anlam etiketi **metinle** tutulur (kimlik değil). Etiket kelimenin güncel anlamlarından biriyle (sadeleştirilmiş
  karşılaştırma) eşleşmezse cümle "belirsiz" sayılır; etiket silinmez, anlam geri gelirse bağ da geri gelir.
  Bilinen sınır: anlam yeniden adlandırılınca bağ kopar (cümle belirsize düşer, veri kaybolmaz).

## 2. Eski `example`'ı içe alma (göç)

`Word.pendingLegacyExample`: `example` dolu **ve** (`exampleMirror == nil` ya da `example != exampleMirror`)
**ve** aynı metinli (boşlukları sadeleştirilmiş) cümle kaydı yok. Varsa:
- Göç (`importLegacyExample`) onu tek bir "belirsiz" cümle kaydı yapar, sonra aynayı günceller. `createdAt`: ilk göçte
  (`exampleMirror == nil`) kelimenin `createdAt`'i (asıl cümle ilk sırada durur; iki cihaz aynı değeri üretir), eski
  sürümün sonradan yazdığı metinde şimdi (sona eklenir). `exampleMirror` dolunca kelime bir daha içe alınmaz:
  tekrar çalışınca sonuç aynı. Boş `example`'lı kelimede yalnız ayna `""` yazılır (bir kez).
- **Bölünmez:** önceki birleştirmenin `\n` ile yazdığı iki cümle de, gerçek çok satırlı alıntı da tek cümle olur
  (hangisi olduğu ayırt edilemez; yanlış bölmek alıntıyı bozar). Kullanıcı formda ayırabilir.
- Göç yalnız ana uygulamalarda çalışır: `StoreMaintenance.run` (iOS ContentView öne gelince, Mac oyun merkezi
  açılınca) ve düzenleme formu açılınca. Paylaş/eylem eklentisi ve widget yalnız ekler/okur; içe alınmamış
  kelimede aynaya dokunmazlar. Göçten önce her ekran `exampleSentences` ile çalışır: içe alınmamış `example`
  sanal bir belirsiz cümle olarak başta görünür.
- İki süreç: `openSerialized` yalnız container açılışını kilitler. Veri göçü tek süreçte (uygulama) koşar;
  eklenti aynı anda aynı kelimeye cümle eklerse en kötü sonuç bir kopya cümledir, temizlik onu toplar.

## 3. Çakışmalar ve temizlik (`StoreMaintenance.run`)

Sıra: (1) her kelimede içe alma → (2) kopya kelime birleştirme → (3) her kelimede kopya cümle temizliği ve ayna.
- **Kopya cümle:** aynı kelimede aynı metin (boşluk sadeleştirilmiş, büyük/küçük harf korunur) + aynı anlam
  etiketi (sadeleştirilmiş) → tek kayıt. Kalan: en eski `createdAt`, eşitse küçük `sentenceID` (her cihaz aynı
  kaydı seçer, karşılıklı silme olmaz). Etiketli bir kopya varken aynı metnin **belirsiz** kopyası da silinir
  (bilgi kaybı yok). Farklı dolu etiketlerle bağlı aynı metin korunur.
- İki cihaz aynı anda göç ederse ikisi de aynı metin, boş etiket ve aynı `createdAt` ile kayıt üretir → temizlik tek
  kayda indirir.
- **Kopya kelime birleştirme** (`merge`): önce gruptaki her kelimenin bekleyen `example`'ı cümleye dönüştürülür,
  sonra cümleler (ve cevap kayıtları) kalan kayda taşınır, sonra kopya silinir; en sonda cümle temizliği ve ayna.
  `WordMatcher.mergedExamples` kaldırıldı.
- **Sahipsiz cümle** (kelimesi yok) otomatik silinmez: iCloud cümleyi kelimesinden önce getirebilir. Her cümle
  kelimesinin sadeleştirilmiş İngilizcesini de taşır (`wordKey`); bakım anahtarı bir kelimeyle eşleşen sahipsiz
  cümleyi o kelimeye (birden çok aday varsa birleştirmede kalacak olana) bağlar. Böylece birleştirmede silinen
  kopyaya başka cihazdan eklenmiş cümle kaybolmaz. Anahtarı eşleşmeyen sahipsiz cümle görünmez bekler.

## 4. Eski istemci senaryoları (seçilen politika)

- Eski istemci `example`'ı **değiştirirse** (`example != exampleMirror`, dolu ve yeni metin): yeni istemci onu yeni
  bir belirsiz cümle olarak sona ekler, sonra aynayı
  ilk cümleye çeker. Düzenleme "değiştirme" değil "ekleme" sayılır: eski metin de kalır (veri kaybı yerine kopya).
- Eski istemci `example`'ı **boşaltırsa**: silme yayılmaz; ayna ilk cümleyle yeniden dolar.
- Yeni istemci son cümleyi sildikten sonra eski istemci eski `example`'ı yeniden yazarsa (düzenleme ya da bütün
  kaydı yeniden gönderme), metin aynadan farklı olduğu için cümle geri gelir (diriliş). Kasıtlı: kaybetmek yerine
  fazladan cümle; kullanıcı yeniden silebilir.
- Göç öncesi bir cihazın eski metni, öbür cihazda düzenlenmiş cümleyle yarışırsa eski metin de cümle olarak
  kalabilir (aynı nedenle). Gecikmiş eşitleme (Word önce, cümle sonra) içe almayı tetiklemez: ayna Word ile gelir.
  Bu arada kelimenin hiç cümle kaydı yoksa bakım dolu aynayı boşaltmaz (`refreshExampleMirror(clearsWhenEmpty:)`);
  yalnız formda son cümlenin silinmesi boşaltır.

## 5. Yazma yolları

- **Form** (iOS ve Mac `macFields`, Paylaş eklentisi ve ⇧⌘E de aynı form): "Cümleler" bölümü; satırda metin, kelimenin
  2+ anlamı varsa anlam seçici (anlamlar + "Belirsiz"), silme (iPhone kaydırma, Mac – düğmesi), "Cümle Ekle".
  Kaydedince (`Word.applySentenceDrafts`): yalnız form açılırken yüklenip kullanıcının kaldırdığı kayıt silinir — form
  açıkken eşitlemeyle ya da bakımla gelen kayıtlara dokunulmaz; değişen güncellenir, yeniler eklenir (aynı metin + anlam iki kez
  eklenmez), ayna güncellenir; ayna yalnız kullanıcı yüklenmiş cümlelerin hepsini sildiyse boşaltılır. Anlamı artık
  kelimede olmayan etiket seçicide "(anlamlarda yok)" notuyla kendi seçeneği olarak görünür; "Belirsiz" seçilirse silinir. Düzenleme formu açılırken kelimenin bekleyen eski cümlesi kayda alınır (yalnız
  uygulamada). Yeni kelimede tek anlam varken cümle belirsiz kalır (anlam seçici 2+ anlamda görünür).
- **Yeniden ekleme** (`absorb`): "hangi cümle kalsın" seçimi kalktı; yeni cümle de tutulur, zaten varsa eklenmez.
  Yeni cümle, bu eklemede **tam olarak bir** yeni anlam eklendiyse ona bağlanır; aksi hâlde belirsiz. Eylem adı:
  "Kaydı Güncelle" / "Cümleyi Ekle" / "Anlamları Ekle". İçe alınmamış kelimede `example`'a dokunulmaz.

## 6. Sorularda ipucu

- Sorulan anlam: `Word.askedMeaning` (soru kurulurken bir kez alınır: `StudySession.questionMeaning`, seçmelide
  doğru şıkkın metni).
- İpucu cümlesi (`hintSentence(for:)`): o anlama bağlı ilk cümle; yoksa ilk belirsiz cümle; o da yoksa ipucu yok
  (başka anlama bağlı cümle gösterilmez). `RecallQuestionView`, `GameWordCard` aynı kuralı kullanır.
- Boşluğu Doldur (`cloze(for:)`): boşluk açılabilen cümleler arasından sorulan anlamınki, sonra belirsiz, sonra
  başka anlamınki; ipucu seçilen cümlenin anlamı (belirsizse sorulan anlam). Seçim soru kurulurken bir kez.
- `GameDeck.withSentence` ve `QuickMix.allowedModes`: kelimenin herhangi bir cümlesinde boşluk açılabiliyor mu.

## 7. Bilinen sınırlar

- Anlam etiketi metin: yeniden adlandırma bağı koparır; aynı anlamın farklı yazımı ayrı sayılır.
- Aynı cümlenin iki cihazda farklı düzenlenmesi: son yazan kazanır (kayıt düzeyinde).
- Kelime anahtarı eklenme anındaki İngilizcedir; kelimenin İngilizcesi başka cihazda değiştirilirken silinmiş kopyaya
  gelen cümle eşleşmeyebilir ve sahipsiz kalır (silinmez). Bu alandan önce yazılmış cümlelerin anahtarı boştur.
- Eski istemcinin düzenlemesi ekleme olarak gelir; eski istemci kendi ekranında ilk cümleyi görmeye devam eder.
- CloudKit şemasına yeni kayıt türü (`CD_WordSentence`) ve `exampleMirror` alanı eklendi: TestFlight/App Store
  öncesi üretim ortamına aktarılmalı. Gerçek iki cihaz eşitleme testi ayrıca yapılmalı.
