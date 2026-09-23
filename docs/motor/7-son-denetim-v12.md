v11 denetiminin 9 maddesinin hepsi metinde kapanmış; bunu kodla karşılaştırarak doğruladım. Yalnızca iki kapanış yeni bir sorun getiriyor (aşağıda 1. ve 2. Orta). Yüksek önemde sorun yok.

**Orta**
1. **§3.2 son paragraf ve §4.1 (C) · Tur başlangıcı yanlış alandan alınıyor.** `roundStartedAt` için `startedAt` verilmesi yazılmış, ama bu alan duraklatmada ileri kayıyor (`StudySession.swift:284`, `GameRound.swift:99`). Uygulama arka plana geçince ya da Mac penceresi kapanıp açılınca, turun kendi eski cevapları bu anın öncesine düşer. "Aynı deste" notu bu yüzden yeni turda da yanlışlıkla çıkar. Öneri: StudySession'daki `roundBeganAt`ı (`:79`, şu an private) kullanın; GameRound'a da kaymayan bir başlangıç alanı ekleyin.
2. **§5 ve §8 C · Mac'te otomatik yeniden başlatma iki yerde var, belge yalnızca birini kaldırıyor.** `MacStudyView.refresh()` → `startDailyIfNeeded()` (`:86-105`) de `current == nil` iken yeni tur başlatıyor. Bu, pencere açılışında ve kelime listesi değişince çalışıyor. Yalnızca `continueDailyIfWeakRemain` kalkarsa özet ekranı yine kendiliğinden kaybolur. Ayrıca StudySession'da "tur hiç başlamadı" durumunu gösteren bir alan yok. Öneri: `refresh`/`startDailyIfNeeded`'ı da C'nin işine adıyla yazın.
3. **§3.2 · "Neredeyse'de yazılan cevap gösterilir, mevcut davranış" doğru değil.** `RecallGameView.swift:230` yazılan cevabı yalnızca `.incorrect` durumunda gösteriyor. Hiçbir parça bu işi üstlenmiyor. Öneri: A'nın `RecallGameView` işine ekleyin ya da maddeyi çıkarın.
4. **§4.3 · "Soru kartında yüzde gösterilmez" kuralının sahibi yok.** `RecallGameView.swift:145` (`MemoryRing(..., text: .trailing)`) bugün kartta yüzde gösteriyor. Öneri: A'ya ya da C'ye verin, veya kapsam dışı olduğunu yazın.

**Düşük**
5. **§4.1 ve §5/§8 C · Mac tur özetinin sahibi çelişiyor.** §4.1'e göre Mac tur özetini A kuruyor, §5/§8'e göre C. `MacStudyView` yalnızca `.word`'ü okuduğu için (`:95`) A'nın burada değiştireceği bir şey yok. Cümleyi düzeltin.
6. **§2.5 · İlk gün eksik tanımlı.** Paragraf S₀/D₀/çıpayı veriyor, ama o günkü `lapsedAt` ve `dueDate`'i yazmıyor. Doğru değerler yalnızca §7.1 tablosundan çıkarılabiliyor: yanlışta "bugün, Yarın", doğruda "çıpa + S". Açıkça yazın.
7. **§3.2 ve §8 B · Küçük kod uyuşmazlıkları.** Hızlı Tur süre metni `QuickMixGameView`'de değil, `GameMode.swift:55`'te ("5 kelime, 1 dakika"). `GameDeck(count:withSentence:shortWords:)` otomatik (memberwise) init değil, elle yazılmış bir init. "Varsayılanı count" için `Int? = nil` gibi bir parametre gerekir.
8. **GOREV ile SPEC · Numara ve kurulum sırası.** Karar numaraları SPEC §9'dan farklı: GOREV 1–5 = SPEC 2, 3, 4, 5, 1; SPEC ise "Kararlar/N" diye bu numaralara atıf yapıyor. "Parça bitince sormadan cihazlara kur" ile "hepsi bitince kurulum" birbirine karışıyor. "Son durum" bölümü boş.

Kodlamaya hazır

Dosyalar: docs/SPEC-MOTOR2.md, docs/GOREV-MOTOR.md, Mac/MacStudyView.swift, Shared/Logic/GameRound.swift, Shared/Logic/StudySession.swift, Shared/Games/RecallGameView.swift, Shared/Logic/GameMode.swift