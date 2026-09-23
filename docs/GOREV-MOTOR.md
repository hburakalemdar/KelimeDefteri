# Görev: Motor 2'yi kodla (hafıza motoru + tur içi mantık + özet/Mac)

Devir notu (24 Eylül 2026, önceki oturum). Tasarım bitti: **`docs/SPEC-MOTOR2.md`** (son sürüm; kendi başına yeterli).
Bu oturumun işi onu kodlamak, test etmek, iki cihaza kurmak, commit/push. İş bitince bu dosyayı sil ve
`docs/CALISMA-RAPORU.md` sonuna kısa "Motor 2" bölümü ekle; `docs/SPEC-OYUN.md`'nin motor kısmına "yerine SPEC-MOTOR2 geçer"
diye bir satır not düş.

## Neden
Kullanıcı tur özetinde "%99 → Şimdi", "%50 → 8 gün sonra" gibi çelişkiler gördü; aynı gün doğru→yanlış ya hiç işlenmiyor ya
her şeyi siliyordu. 4 araştırma + 12 tasarım sürümü + her sürümde bağımsız denetim + Python simülasyonu sonucunda yeni motor:
kelimenin hafıza durumu **ReviewLog'lardan gün gün (04:00 sınırı) yeniden oynatılarak** hesaplanır (`replay(taban, loglar, now)`),
Word alanları önbellektir. Ayrıntı ve gerekçeler SPEC'te.

## Onaylar (tekrar sorma)
- Testler geçince **sormadan** commit et, push et. Cihazlara kurulum yalnızca **A, B, C üçü de bitince**, iPhone ve Mac
  birlikte (ara parçalarda kurma; ara sürüm eski/yeni karışımı yaratır).
- Mac ve iPhone **aynı anda** güncellenmeli (eski+yeni sürüm birlikte çalışırsa önbellek farklı yazılır — SPEC §6).
- CloudKit şemasını üretime aktarma (ayrı onay). Apple hesabında yeni kayıt gerekmez.

## Kullanıcı kararları (özet; numaralar ve tam metin için SPEC §9 esastır)
1. Aynı gün 1 doğru + 1 yanlış = "bilemedin" (1/3 eşiği).
2. Widget/bildirim sorusu: önce vadesi gelmiş ve yeni olmayan kelimeler, yoksa ağırlıklı rastgele (yeniler hariç); widget boş kalmaz.
3. Tur özetinde ✓/✗ = bu turdaki ilk cevap; "sonraki tekrar" metni günün sonucunu yansıtır; yüzde yok, "önce → sonra" vade.
4. Yanlış bilinen kelime: listede/ayrıntıda turuncu halka + "Tekrar edilecek" + ne zaman ("Yarın"); Günlük Tekrar ve
   "N zayıf" sayısına vadesi gelince girer.
5. Tanıma oyunlarında tur içi yeniden sorma yok; Harfleri Diz / Ters Yön ipucu düğmesi yok; aynı desteyi tekrar oynarken tek satır not.

## Nasıl çalışılacak
- CLAUDE.md'yi oku (derleme, kurulum, tuzaklar). Kullanıcı bağlam şişmesinden çekiniyor: yönetici ol, işi ajanlara ver.
- Parçalar **SIRALI**: A → B → C (SPEC §8). Her parça **ayrı, temiz bir ajan** (general-purpose, worktree); eline SPEC'i ve
  parça adını ver. Paralel koşturma (Mac ısınıyor, tipler çakışıyor). Her parça kendi sonunda iOS testleri + Mac derlemesi
  geçmeli; tip/imza değiştiren parça bütün çağıranları (grep) kendisi günceller — dosya listeleri yol göstericidir.
- Son denetimde (SPEC v11) "A kodlamaya hazır" denmişti; B/C listeleri v12'de tamamlandı. v12 sonrası denetim sonucu aşağıda.
- Her parçadan sonra yönetici: diff'e ve test sonucuna bak, main'e birleştir, bir sonraki parçayı ver.
- A'dan sonra **simülasyonla karşılaştır**: `docs/motor/sim_v8.py` (Python, SPEC v8 kurallarının birebir uygulaması; sonraki
  sürümlerde küçük eklemeler oldu: ilk cevap tablosu, widget seçimi, özet alanları, yeni kelime sınırı). SPEC §7.1
  senaryolarını Swift birim testleriyle doğrula; sayılar tablo ile tutmalı. Tutmazsa önce SPEC'e bak, sonra koda.
- Hepsi bitince: tüm testler, cihaz derlemesi, iPhone kurulumu, Mac Release kurulumu (CLAUDE.md'deki lsregister adımlarıyla),
  commit/push. Kullanıcıya sade Türkçe özet ve neyi denemesi gerektiği (bilerek doğru/yanlış basarak tur özeti, widget,
  yanlış kelimenin ertesi gün gelmesi, liste halkası).

## Dosyalar
- `docs/SPEC-MOTOR2.md` — tasarım (tek kaynak).
- `docs/motor/` — dayanak raporlar: eski motor denetimi, tur içi denetim, iki web araştırması, v8 simülasyon raporu,
  model karşılaştırması (oran modeli vs sade "günün ilk cevabı"), `sim_v8.py`.
- Önceki SPEC sürümleri git geçmişinde (v7–v12 commit'leri).

## Son durum
- SPEC v12 son denetimi: **Kodlamaya hazır**, Yüksek yok (`docs/motor/7-son-denetim-v12.md`). Kalan Orta/Düşük
  maddeler SPEC'e işlenmedi; ilgili parçanın ajanına bunları da ver:
  - (C) Tekrar turu notu için tur başlangıcı: `startedAt` duraklatmada kayıyor (StudySession:284, GameRound:99) →
    StudySession'ın `roundBeganAt`'ını (:79, private) aç, GameRound'a kaymayan başlangıç alanı ekle.
  - (C) Mac'te otomatik yeniden başlatma iki yerde: `continueDailyIfWeakRemain` VE `MacStudyView.refresh()` →
    `startDailyIfNeeded()` (:86-105); ikisi de kalkmalı ki özet ekranı kaybolmasın ("tur başlamadı" durumu gerekebilir).
  - (A) "Neredeyse"de yazılan cevap gösterilsin: RecallGameView:230 şu an yalnız `.incorrect`'te gösteriyor.
  - (A) Soru kartında yüzde gösterilmez (§4.3): RecallGameView:145 `MemoryRing(..., text: .trailing)`.
  - Mac tur özetini C kurar (§4.1'deki "A" ifadesi yanlış; A'nın MacStudyView'da işi yok).
  - §2.5 ilk gün: yanlışta lapsedAt = bugün, vade = Yarın 04:00; doğruda vade = çıpa + S (§7.1 ile aynı).
  - (B) Hızlı Tur süre metni GameMode.swift:55'te; `GameDeck(count:withSentence:shortWords:)` elle yazılmış init.
