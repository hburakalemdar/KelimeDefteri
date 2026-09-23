**Not:** Rapor dosyası yazılmadı. Bu oturum salt okunur modda, dosya oluşturmak yasak. Tam raporu aşağıya koydum; `<geçici dosya>` yoluna sen ya da ana ajan kopyalayabilir. Rakamlar motorun Python'da birebir kopyasıyla hesaplandı (hiçbir dosya yazılmadı).

## Özet (15 satır)
1. Ön incelemedeki bütün bulgular doğrulandı. Hepsinin kökü `ReviewRecorder.swift:34-56`: aynı gün koruması, vadeyi geçmişe koyarak işaretlenen "zayıf" durumu ve geri yükleme dalı birlikte.
2. **En ağır hata (H1):** aynı gün önce doğru sonra yanlış cevapta yanlış S ve D'ye hiç yansımıyor. S=30 olan kelime ilk doğruda 82'ye çıkıyor, yanlışta 82'de kalıyor. Ekran "%50 · Şimdi" diyor, motor "82 gün" diyor. Ertesi gün doğru cevapta S 83,7'ye büyüyor.
3. **H2:** doğru→yanlış→doğru sırasında vade ilk doğrunun vadesine dönüyor (`ReviewRecorder.swift:53-56`), yani yanlış tamamen siliniyor.
4. **H3:** Günlük Tekrar'da yanlıştan sonra araya 2 kart girip doğru bilinince zayıf durumu kalkıyor ve ekran hemen %100 gösteriyor. Özette kırmızı ✕ ile "→ 10 gün sonra" yazıyor.
5. **H6:** Aynı yanlışın sonucu giriş noktasına göre değişiyor. Günlük Tekrar'da yeniden sorulduğu için "10 gün sonra" oluyor; Hızlı Tur ve tanıma oyunlarında "Şimdi" kalıyor.
6. **H5:** Tur özeti üç ayrı anı karıştırıyor. İkon turdaki ilk cevabı, sol değer turdaki ilk cevaptan önceki hafızayı (bugün başka oyunda görüldüyse %99), sağ değer son cevaptan sonraki vadeyi gösteriyor. "%99 → Şimdi" ve "%50 → 8 gün sonra" buradan çıkıyor.
7. "%50" gerçek bir olasılık değil, bir durum etiketi. Vade S·11,52 gün geriye konuyor (S=10,5 için −121 gün, S=82 için −946 gün). Motor bu durumda R=0,989 kullanıyor. Motoru ekrandaki R'ye bağlamak çözüm olmaz: S 132'ye çıkardı.
8. **H7:** Tanıma oyunlarında şansla verilen doğru cevap zayıf durumunu kaldırıyor, S'yi de 21'in üstüne atabiliyor (S 10'dan 23'e çıkıp "Öğrenildi" oluyor; vadesi çok geçmiş S=3 kelime 42'ye çıkıyor). Widget'ta yeni kelimeler en yüksek ağırlıkla (1,0) seçildiği için bu durum en sık orada oluşuyor.
9. **H4:** `learnedAt` aynı gün yanlış→doğruda kayıyor; ayrıca `commitPendingAnswer` geri alınınca eski değerine dönmüyor (`StudySession.swift:252,259`). "Bu hafta +N" sayısı şişiyor.
10. **Yanlışta ×0,35 çarpanı (tartışmalı):** Olgun kelimelerde çok yumuşak kalıyor. S=300 olan unutulmuş kelime 105 gün sonra geri geliyor; FSRS-4.5 bunu 13,5 gün yapardı. S'nin üst sınırı yok.
11. Tanıma oyununda yanlış ×0,5 cezalanıyor, hatırlama oyunundaki ×0,35'ten hafif. Oysa seçeneklerden tanıyamamak unutmanın daha güçlü kanıtı. Harfleri Diz de `weight == 1` kontrolü yüzünden 0,5 alıyor.
12. **Zorluk (D) kayması:** "good" her seferinde D'yi 0,2 düşürüyor (FSRS'de değişmez). Sürekli doğru bilinen kelimede D 1,2'ye iniyor, büyüme %63 artıyor. Oyun ağırlığı D'ye uygulanmıyor.
13. **Günlük tekrar birikimi:** Günde tek cevap sayılsa bile, her gün doğru bilinen yeni kelime 7. günde (hatırlama), 12. günde (tanıma), hızlı ilk cevapla 5. günde "Öğrenildi" oluyor; uzun aralıkla hiç sınanmadan. Günde 10 tur ek bir etki yaratmıyor, asıl etken her gün yeniden görmek.
14. Diğer parametreler makul: %90 hedef, ilk S değerleri 0,4/1,2/3/8 (FSRS-5'e yakın), en düşük S 0,3, D aralığı 1–10. Ancak "Yeni Eklenenler"de dakikalar önce eklenen kelime 4 saniyenin altında yazılınca "easy" alıyor ve 8 gün sonraya gidiyor.
15. Önerilen düzeltme sırası: H1+H2 (aynı gün yanlışı günde bir kez S'ye işlensin), H3/H6 (aynı gün doğru zayıflığı ertesi güne kadar kaldırmasın), özet ve zayıf kelime gösterimi, yanlış formülüne FSRS benzeri tavan, tanımada şans düzeltmesi, `learnedAt`.

---

# Tam rapor: Hafıza ilerlemesi denetimi

## 0. Motorun özeti
- R = (1 + 19/81 · t/S)^−0,5 (`Memory.swift:26-29`). Motor t'yi `lastReviewedAt`'ten ölçer (`:48`). Ekran ise zayıf durumdaki kelimede t'yi `dueDate − S`'ten ölçer (`Word.swift:67`).
- İlk cevap: S = [0,4; 1,2; 3; 8][not] × ağırlık, en az 0,3. D = [7; 6; 5; 3,5] (`Memory.swift:22-23,43-45`).
- Doğru cevap: S' = S·(1 + e^1,5·(11−D)·S^−0,2·(e^{1,2(1−R)}−1)·çarpan·ağırlık). Çarpan hard 0,5, good 1, easy 1,5 (`:54-60`).
- Yanlış cevap: S' = max(0,3; S·(ağırlık==1 ? 0,35 : 0,5)) (`:52`). Ardından vade `lapseDue` ile geçmişe konur: hedef = min(önceki hafıza; 0,504), vade = şimdi − S'·(81/19·(hedef^−2 − 1) − 1) gün, yani yaklaşık **−11,52·S'** (`:82-87`).
- D: again +1, hard +0,4, good −0,2, easy −0,6; sonra 5'e doğru %5 yaklaşır, 1–10 arasında kalır (`:90-100`).
- Kayıt (`ReviewRecorder.swift`):
  - Kelimenin `lastReviewedAt`'i bugünse hafıza güncellenmez (`:34-35`).
  - Yanlışsa her durumda vade `lapseDue` ile geçmişe konur (`:50-52`).
  - Doğruysa ve güncelleme yapılmadıysa vade `last + S`'e geri döner (`:53-56`). Bu dal zayıf durumu da kaldırır.
  - `learnedAt` her cevapta yeniden hesaplanır (`:58-62`).
- `isLapsed` = dueDate < lastReviewedAt (`Word.swift:74-77`); `isLearned` = S ≥ 21 ve zayıf durumda değil (`:89`).

## 1. Giriş noktası tablosu

| Giriş | Kod | Not nasıl belirleniyor | Ağırlık (yanlış çarpanı) | Hafızaya yazar mı | Turda sayılan cevap | Yeni kelimede |
|---|---|---|---|---|---|---|
| Günlük Tekrar | `StudyView.swift:97`, `RecallGameView`, `StudySession` .daily, mode .dailyReview | `AnswerGrade.recall` (`GradeOption.swift:46-55`): doğru yazım ≤4 sn easy, 4–12 sn good, >12 sn hard; "Neredeyse" hard; Göster+Bildim hard; "Doğru Say" good; Bilemedim/Devam(yanlış) again. Süre kart gösteriminden cevabın açılmasına kadar, arka plan hariç. | 1,0 (×0,35) | Evet | Yanlış kelime 2 kart sonra yeniden sorulur, bilinene kadar sürer. Hepsi kayda ve sayaca yazılır; S/D'yi günün ilk cevabı değiştirir. Sonraki yanlış vadeyi geri çeker, sonraki doğru (hemen arkasından değilse) zayıflığı kaldırır. | En fazla 5 yeni, en eskiden başlayarak. İlk not S ve D'yi tablodan belirler. |
| Yeni Eklenenler | `StudyView.swift:99`, plan .recent, mode .dailyReview | Aynı | 1,0 | Evet | Aynı | En yeni 10 kelime, bekletmeden. Günlük yeni kelime sınırı yok ("Bir Tur Daha"). Kayıtta "Günlük Tekrar" adıyla görünür. |
| Yine de Çalış | .extraPractice, mode .dailyReview | Aynı | 1,0 | Evet | Aynı | Zorlanılanlar önce, sonra en zayıflar. Güçlü kelimeler de gelir, yani erken tekrar olur. |
| Hızlı Tur (kart, kilit ekranı, Denetim Merkezi) | Hep `QuickMixGameView` (`StudyView.swift:107`, `ContentView.swift:52`). Saf `.quick` planı yalnızca karışık turun tek soruluk oturumunda kullanılıyor. | Soru türüne göre: hatırlama→recall, çoktan/boşluk→recognition, harf→LetterPuzzle | Soru türünün ağırlığı | Evet | 5 soru, kelime başına 1 cevap. Yanlış hatırlama sorusu yeniden sorulmaz (`QuickMixGameView.swift:151-163`, oturum atılır). | Yeniler ağırlık 1,0 ile en olası seçim (`WordPicker.swift:27-30`). |
| Hızlı Tur (karışık) | Yukarıdakiyle aynı ekran; ayrı bir "düz" Hızlı Tur yok | — | — | — | — | — |
| Çoktan Seçmeli | `ChoiceGameView.swift:52` | `recognition`: doğru good, yanlış again (`GradeOption.swift:58-60`); süre notu etkilemez | 0,6 (×0,5) | Evet | 10 soru, kelime başına 1 | İlk doğru S=1,8, D=5; ilk yanlış S=0,3, D=7 |
| Eşleştir | `MatchGameView.swift:230`, `MatchBoard.swift:42-44` | Eşleşme anında: soldaki kelime daha önce yanlış bir anlamla denendiyse again, yoksa good. Sağdaki kelime ceza almaz. Süre kaydedilmez. Son çift eleme yoluyla kendiliğinden doğru olur. | 0,6 (×0,5) | Evet | 5 çift, kelime başına 1; hata sayısı değil var/yok bakılır | Tanıma ile aynı |
| Boşluğu Doldur | `FillBlankGameView.swift:54` | recognition | 0,6 (×0,5) | Evet | 10 soru | Aynı |
| Harfleri Diz | `LetterPuzzle.swift:104-107`, `LettersGameView.swift:262,274` | 0 hata good, 1–2 hata hard, 3+ hata ya da "Göster" again. Hiç easy yok, süre yok. | 0,8 (`weight==1` olmadığı için ×0,5) | Evet | 8 soru | İlk good S=2,4 |
| Ters Yön | `RecallGameView(plan: .reverse, mode: .reverse)` | recall; `ReverseChecker` yazım hatasını "Neredeyse" (hard) sayar | 1,0 (×0,35) | Evet | 10 kelime, yanlışlar yeniden sorulur (StudySession) | Recall ile aynı |
| Widget cevabı | `AnswerQuestionIntent.swift:28` → `GlanceQuizStore.answer` → `GlanceQuiz.answer` (`GlanceQuiz.swift:103`) | recognition, süre 0 | 0,6, "Çoktan Seçmeli" adıyla | Evet (widget sürecinde) | 1 | Soru seçiminde yeniler ağırlık 1,0 (`:69-75`): yeni kelime ilk kez 4 şıklı tahminle tanıtılabilir |
| Bildirim cevabı | `NotificationDelegate.swift:35-47` → `ReminderQuiz.handle` → `GlanceQuiz.answer` | Aynı; soru planlama anında sabitlenir, günler sonra cevaplanabilir | 0,6 | Evet | 1 | Aynı |
| Mac çalışması | `MacStudyView.swift:38,98,104,124`; oturumun modu varsayılan .dailyReview | recall | 1,0 | Evet | Günlük Tekrar ile aynı; gün dönünce tur yenilenir (`:36-39`) | Aynı |

Bütün yollar `ReviewRecorder.record`'dan geçiyor, dolayısıyla aynı gün koruması hepsine uygulanıyor. `GameRound`'daki (`GameRound.swift:72,78`) ve `StudySession`'daki (`StudySession.swift:330`) `isFirstAnswer` kontrolü artık gereksiz (bkz. G6).

## 2. Senaryo matrisi (başlangıç D=5, hatırlama ağırlığı 1, aksi yazmıyorsa)

| # | Senaryo | S | D | Vade | R (motor / ekran) | Zayıf durum | Ekranda / özette |
|---|---|---|---|---|---|---|---|
| 1a | Yeni, ilk doğru (hatırlama): hard / good / easy | 1,2 / 3 / 8 | 6 / 5 / 3,5 | +1,2 / +3 / +8 gün | — / %100 | yok | "Yeni → Yarın / 3 gün sonra / 8 gün sonra" |
| 1b | Yeni, ilk doğru (tanıma / harf) | 1,8 / 2,4 | 5 | +1,8 / +2,4 | %100 | yok | "Yeni → Yarın" ya da "2 gün sonra" |
| 2 | Yeni, ilk yanlış (hatırlama / tanıma) | 0,4 / 0,3 | 7 | −4,6 / −3,5 gün | ekran %50; 1 gün sonra %46, 3 gün sonra %40 | var | Kırmızı "Yeni → Şimdi". Günlük Tekrar'da 2 kart sonra doğru bilinince vade +0,4 gün (≈9,6 saat), ekran %100, özet ✕ "Yeni → Bugün/Yarın" |
| 3a | Olgun S=30, vadesinde (R=0,90): hard / good / easy | 56,0 / 82,1 / 108,1 | 5,38 / 4,81 / 4,43 | +56 / +82 / +108 | 0,90 / %90 | yok | "%90 → 82 gün sonra" |
| 3b | Aynısı, tanıma good / harf good | 61,3 / 71,7 | 4,81 | +61 / +72 | | | |
| 3c | Olgun S=30, vadesinde yanlış (hatırlama / tanıma) | 10,5 / 15,0 | 5,95 | −121 / −173 gün | ekran %50 (önceki %90 değeri 0,504'e kısılır) | var, `isLearned` false | "%90 → Şimdi" (kırmızı) |
| 4a | Erken (t=10, vade 20 gün sonra, R=0,963): good / easy / tanıma good | 48,5 / 57,8 / 41,1 | 4,81 | +48 / +58 / +41 | 0,963 | yok | "%96 → 48 gün sonra" |
| 4b | Erken yanlış | 10,5 (vadesindekiyle aynı) | 5,95 | −121 | %50 | var | Erken yanlış geç yanlışla aynı cezayı alıyor |
| 5 | Aynı gün doğru → yanlış (S=30, vadesinde) | 82,1'de kalır | 4,81 | 1. cevapta +82 gün; 2. cevapta **−946 gün** | motor ~1,0 / ekran %50 | var | 2. oturumun özetinde "%99 → Şimdi" (bu tur içinde ilk cevap). `learnedAt` silinir. Ertesi gün doğru: R_motor 0,997, S **83,7**. Yanlış S'ye hiç yansımadı |
| 6 | Aynı gün yanlış → doğru (arada ≥1 kart) | 10,5 | 5,95 | yanlışta −121; doğruda **t1 + 10,5 gün** | ekran %50'den %100'e zıplar | kalkar | Özet: ✕ "%90 → 10 gün sonra". Doğru hemen arkasından gelirse (son kart) zayıf kalır ve "Şimdi". Tanıma oyunlarında ve Hızlı Tur'da yeniden sorma olmadığından "Şimdi" kalır |
| 7 | Aynı gün yanlış → yanlış → doğru | 10,5 | 5,95 | t1 + 10,5 | | kalkar | #6 ile aynı; ikinci yanlış yok sayılır (hedef zaten ≈0,504) |
| 7b | Aynı gün doğru → yanlış → doğru | 82,1 | 4,81 | **t1 + 82** | | kalkar | Yanlış tamamen silinir. S≥21 ise `learnedAt` = şimdi (kayar) |
| 8 | Dün yanlış, bugün doğru (S 30'dan 10,5'e düşmüştü) | good 12,47 / easy 13,46 / tanıma good 11,68 | 5,71 | +12,5 | motor 0,989 / ekran 0,503 | kalkar | **"%50 → 12 gün sonra"**. Motor ekrandaki R'yi kullansaydı S=132 olurdu |
| 8b | Yeni kelime dün yanlış (0,4), bugün good | 2,82 | 6,7 | +2,8 | motor 0,794 / ekran ~0,46 | kalkar | "%46 → 2 gün sonra" |
| 8c | "%50 → 8 gün sonra" (kullanıcının gördüğü) | Bugün önce başka bir oyunda yanlış (S≈23×0,35 ya da ≈16×0,5 = 8), sonra Günlük Tekrar'da doğru | | t1 + 8 | | kalkar | Tur içindeki ilk cevaptan önceki değer %50, vade geri yüklendi |
| 9 | Tanımada şansla doğru (bilmeden, p=0,25) | Vadesinde S=10 → **23,0** ("Öğrenildi"); yanlışta 5,0. Vadesi 60 gün geçmiş S=3 → **42**. Zayıf durumdaki kelime ertesi gün → 11,7 | good −0,2 | | | kalkar | Beklenen ln(S'/S) = −0,31, yani tahminle oynayan kişinin S'si uzun vadede düşer (10 turda medyan 0,3). Ama tek şanslı cevap "Öğrenildi" rozeti verebiliyor. Eşleştir'de son çift her zaman doğru |

## 3. Tutarsızlık ve hata listesi (önem sırasıyla)

### Gerçek hatalar
- **H1 (yüksek) Aynı gün yanlışı kayboluyor.** Kod: `ReviewRecorder.swift:34-35,50-52`. Günün ilk cevabı doğruysa sonraki yanlış S ve D'yi değiştirmiyor, yalnızca vadeyi −11,5·S gün geriye itiyor. Böylece ekran (%50, "Şimdi") ile motor (S=82) birbirinden ayrılıyor. Ertesi gün doğru cevap şişmiş S'den büyüyor. `SameDayMemoryTests.swift:83-98` bu davranışı bilerek test ediyor, yani kasıtlı ama sonucu yanlış.
  - Aynı durum widget için de geçerli: sabah şansla doğru tahmin (ağırlık 0,6) günün "ilk cevabı" oluyor, akşamki gerçek hatırlama yanlışı S'ye işlenmiyor.
- **H2 (yüksek) Doğru→yanlış→doğru yanlışı siliyor.** `ReviewRecorder.swift:53-56`: `last + S` ile vade, ilk doğrunun vadesine dönüyor.
- **H3 (orta-yüksek) Aynı gün yanlıştan sonra doğru zayıflığı kaldırıyor.** Kod: `StudySession.swift:312-316,337`, `WordPicker.swift:77-79`. Araya iki kart girince zayıf durumu kalkıyor, ekran hemen %100 oluyor, vade S' gün sonraya gidiyor. Kodun gerekçesi "az önce gördüğü cevabı yazmak kelimeyi bildiğini göstermez" ama bu yalnızca hemen arkasından gelen cevabı koruyor; iki kart sonrası da hâlâ kısa süreli bellek.
- **H4 (orta) `learnedAt` kayıyor.**
  - `ReviewRecorder.swift:58-62`: zayıf duruma düşünce siliniyor, aynı gün geri yüklenince bugünün tarihi yazılıyor.
  - `StudySession.swift:252,259`: `commitPendingAnswer`'ın geri alma listesinde `learnedAt` yok. Önce yanlış kaydedilip sonra "Doğru Say" denince tarih kayıyor.
  - Sonuç: `WeeklySummaryView.swift:19` üzerinden "bu hafta +N" sayısı şişiyor.
- **H5 (orta) Tur özeti üç anı karıştırıyor.**
  - İkon ilk cevabın doğruluğu (`RoundSummaryView.swift:115`).
  - Soldaki değer turdaki ilk cevaptan önceki hafıza (`GameRound.swift:74`, `StudySession.swift:332`). Aynı gün başka oyunda görülen kelimede %99 ya da %50 çıkıyor.
  - Sağdaki değer son cevaptan sonraki vade (`RoundSummaryView.swift:151-153`); rengi ekranın çizildiği ana göre belirleniyor.
- **H6 (orta) Giriş noktasına göre aynı yanlışın sonucu farklı.** Günlük Tekrar ve Ters Yön yanlışı yeniden sorduğu için vade S' gün sonraya gidiyor. Hızlı Tur'un hatırlama sorusu (`QuickMixGameView.swift:151-163`), Çoktan Seçmeli, Boşluk, Harf ve Eşleştir'de yeniden sorma yok, kelime "Şimdi" olarak kalıyor.
- **H7 (orta) Tanımadaki şans başarısı.** Kod: `GradeOption.swift:58-60`, `GlanceQuiz.swift:69-75,103`. Tek şanslı doğru zayıf durumu kaldırıyor ve S'yi 21'in üstüne taşıyabiliyor. Widget ve bildirim sorusunda yeni kelimeler en yüksek ağırlıkta (1,0).
- **H8 (düşük) Günün ilk cevabı en zayıf kanıt olabiliyor.** Düşük ağırlıklı bir tanıma cevabı o günün sonraki hatırlama cevabını (ağırlık 1) etkisiz bırakıyor.
- **H9 (düşük) Eski biçimli kelime geçişi.** `MemoryMigration.values` `lastReviewedAt = due − S` yazıyor; bu tarih bugüne düşerse ilk gerçek cevap korumaya takılıyor (`ReviewRecorder.swift:31-35`). Uç bir durum.

### Kötü gösterim
- **G1 %50 sabiti bir olasılık değil, durum etiketi.** Kod: `Memory.swift:72-87`, `Word.swift:65-70`.
  - S=300 olan kelime de yeni kelime de aynı %50'yi gösteriyor.
  - Düşüş hızı S'ye bağlı: S=10,5 iken 30 günde %47'ye iniyor, S=0,3 iken 3 günde %40'a.
  - Ortalama hafızaya (`MemoryStats.swift:66-70`) ve seçim ağırlığına sahte bir değer olarak giriyor.
- **G2 Motor R ile ekran R farklı.** Zayıf durumdaki kelimede ekran 0,50, motor 0,989. Motorun kullandığı değer doğru; yanıltıcı olan ekran.
- **G3 Vade gerçek dışı bir geçmişe konuyor** (−121, −946 gün). Ayrıntı sayfasında sürekli "Sıradaki tekrar: Şimdi" yazıyor (`Leitner.swift:10-20`).
- **G4 Yanlıştan sonraki doğru ekranı yeşil %100 yapıyor** (H3'ün gösterim tarafı).
- **G5 Kayıttaki oyun adı gerçeği yansıtmıyor.** Yeni Eklenenler, Yine de Çalış ve Mac "Günlük Tekrar" adıyla, widget ve bildirim "Çoktan Seçmeli" adıyla kaydediliyor. `WordStats` bunları ayıramıyor.
- **G6 Gereksiz tekrar kontrolü.** `GameRound` ve `StudySession`'daki `isFirstAnswer` ile `memoryAnsweredAt`, `ReviewRecorder`'daki gün kontrolüyle aynı işi yapıyor.

### Tartışmalı tasarım kararları
- **T1 Yanlışta ×0,35 çarpanı.** R'ye bağlı değil ve üst sınırı yok. S=100 için 35 gün (FSRS 8,6), S=300 için 105 gün (FSRS 13,5). Unutulmuş olgun kelime S≥21 kaldığı için geri yüklenince yine "Öğrenildi" sayılıyor. S'nin kendisinin de üst sınırı yok: 12 yıl sonra 4358 gün.
- **T2 Tanımada yanlış ×0,5, hatırlamadakinden hafif.** Tanıyamamak unutmanın daha güçlü kanıtı. Harfleri Diz de `weight == 1` karşılaştırması yüzünden 0,5 alıyor (`Memory.swift:52`).
- **T3 Zorluk kayması.** good −0,2 olduğu için sürekli doğru bilinen kelimede D 1,2'ye yaklaşıyor ve (11−D) çarpanı %63 büyüyor. Oyun ağırlığı D'ye uygulanmıyor.
- **T4 "Öğrenildi" (21) kolay erişiliyor.** Her gün doğru bilinen kelime 5–12 günde bu eşiğe ulaşıyor, hızlı ilk cevapla iki cevapta (8'den 30,6'ya). Uzun aralıkla sınanmış olması şart değil.
- **T5 Mutlak 4 saniyelik easy eşiği.** Dakikalar önce eklenen kelime 8 gün sonraya gidiyor. Kelime uzunluğu hesaba katılmıyor.
- **T6 Not tutarsızlıkları.** Göster+Bildim (hard) vadesindeki kelimenin S'sini 10'dan 20,8'e çıkarıyor. "Doğru Say" (good, S 31,6) yavaş ama doğru yazılmış cevaptan (hard, S 20,8) daha fazla ödüllendiriliyor.
- **T7 Yeni kelimeler bütün seçicilerde en yüksek ağırlıkta** (1,0). Günlük 5 yeni kelime sınırı oyunlar ve widget üzerinden fiilen deliniyor.
- **T8 Aynı gün kuralı.** "Günün ilk cevabı kazanır" yerine "günde bir yanlış işlenir" daha doğru olurdu. Erken yanlış ile geç yanlış aynı cezayı alıyor.
- **T9 Eşleştir.** Son çift eleme yoluyla her zaman doğru; yanlış çiftte yalnızca soldaki kelime sayılıyor.

## 4. Sayısal sağlık
- **Makul olanlar:** %90 hedef, 0,3 alt sınırı, D aralığı 1–10, ilk S değerleri (FSRS-5: 0,40/1,18/3,17/15,7; burada easy 8 daha temkinli), büyüme sabitleri (FSRS-4.5'teki e^1,49, S^−0,14, 0,94'e yakın). Vadesinde her doğruda S yaklaşık ×3,5 büyüyor: 3 → 11 → 36 → 100 → 248.
- **Sorunlu olanlar:** yanlış çarpanı (T1), tanımadaki 0,5 (T2), good için −0,2 (T3), 21 eşiği (T4), easy'deki 4 saniye (T5), S'nin üst sınırı olmaması.
- **Günde 10 tur:** Günde yalnızca ilk cevap sayılıyor. Aynı saat içindeki ek doğruların etkisi zaten ~%0,06, yani koruma doğru cevaplarda neredeyse bir şey değiştirmiyor, yalnızca yanlışları kaybettiriyor. Asıl birikim her gün yeniden görmekten geliyor:
  - Hatırlama: S=30'dan 30 günde 76,5'e; D 2,0'a iniyor.
  - Tanıma: 30 günde 49,8.
- **Uç durumlar:** `lapseDue` hedef 0'a yaklaşırsa sonsuza gidiyor, ama R>0 olduğu için bu pratikte olmuyor. Saat ileri kaymış bir cihazda geçen süre 0'a sabitleniyor. Eşitlenmemiş iki cihazın ikisi de aynı gün hafızayı güncelleyebiliyor.

## 5. Düzeltme yönü (öneri)
1. **Aynı gün kuralı:** Günün ilk yanlışı, bugün daha önce doğru bilinmiş olsa bile S'ye bir kez işlensin (S×0,35). Aynı gün sonraki doğru vadeyi `last + S` ile geri yüklemesin; zayıflık ertesi güne kadar sürsün ya da vade şimdi + min(S, 1 gün) olsun.
2. **Zayıf durumu açık bir alanla tutulsun:** yeni bir `lapsedAt: Date?` alanı (CloudKit yalnızca ekleme kabul ettiği için eklenebilir). Vadeyi geçmişe koyma hilesi kalksın. Ekran "%50" yerine "Tekrar gerekli" desin ya da motorun R'sini göstersin.
3. **Özet tek bir anı göstersin:** ilk cevap ikonu, günün başındaki hafıza ve ilk cevaptan sonraki vade. Zayıf kelimede "Şimdi" yerine "Yarın tekrar" yazsın.
4. **Yanlış formülü:** S' = min(S×0,35; FSRS-4.5 yanlış formülü) ya da bir üst sınır. Tanımada yanlış çarpanı hatırlamadakinden hafif olmasın.
5. **Tanımada şans düzeltmesi:** Tanımadaki doğru zayıflığı kaldırmasın; büyüme sınırlansın ya da (p−0,25)/0,75 ile ölçeklensin. Widget'ta yeni kelimeler sorulmasın ya da ağırlıkları düşürülsün.
6. **`learnedAt`:** yalnızca belirli bir süre (örneğin ≥7 gün) sonra gelen doğru cevapta yazılsın; geri alma listesine eklensin.
7. **Zorluk:** good için değişim 0 olsun.

### Critical Files for Implementation
- Shared/Logic/ReviewRecorder.swift
- Shared/Logic/Memory.swift
- Shared/Word.swift
- Shared/Logic/StudySession.swift
- Shared/Games/RoundSummaryView.swift