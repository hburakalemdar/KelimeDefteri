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
