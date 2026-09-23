**Özet (en fazla 15 satır):**

Bu görev salt okunur modda çalıştı. Dosya oluşturmam engelli olduğu için rapor `.../scratchpad/motor/2-tur-ici.md` dosyasına yazılmadı. Raporun tamamı aşağıda; ana ajanın o dosyaya kaydetmesi gerekiyor.

1. **Gerçek hata (Mac):** Aynı gün "Yine de Çalış" turu bittikten sonra yeni kelime eklenince ya da bir kelime zayıflayınca, kart "Başla" diyor ama açılan ekran "Tur Bitti" oluyor (`Mac/MacStudyView.swift:86-92`).
2. **Gerçek hata:** Turun son kelimesi yanlış bilinirse aynı kart hemen yeniden soruluyor. Bu, spec'teki "art arda gelmez" kuralına aykırı (`WordPicker.swift:77-79`). 4 kelimelik defterde sık oluyor.
3. **Gerçek hata:** Boşluğu Doldur'da aynı Türkçe anlamlı kelime (deneme/denemw) çeldirici olarak çıkıyor, yani iki doğru şık oluşuyor (`FillBlankGameView.swift:68-69`).
4. **Gerçek hata:** Ters Yön'de aynı Türkçe anlama sahip iki kelimede soru belirsiz. Öbür kelimeyi yazmak "Neredeyse" ya da "Tam tutmadı" sayılıyor (`StudySession.swift:228-234`).
5. Yanlış cevaptan sonra sayaç ilerlemiyor: sıradaki farklı kelimede de "1/4" yazıyor (`GameScaffold.swift:177`). Mac'te aynı tur "N kaldı" ile, başka bir mantıkla gösteriliyor.
6. Çoktan Seçmeli ve Eşleştir'in açılma koşulu kelime sayısına bakıyor, farklı anlam sayısına bakmıyor. Kullanıcının defterinde 3 şık ve 3 çift çıkıyor, "4 seçenekten doğrusu" tutmuyor.
7. Cevap kontrolünde iki gevşeklik var: baştan eşleşme yüzünden "kara" cevabı "karar" için doğru sayılıyor; virgülle birkaç tahmin yazmak da doğru sayılıyor (`AnswerChecker.swift:23,63-71`).
8. Seçmeli oyunlarda "Bir Tur Daha" hemen sonra oynanınca yanlış bilinen kelimenin zayıflığı siliniyor (`GameRound.swift:76-79`). Az kelimede her turda aynı kelimeler geliyor; hafıza değişmiyor ama günlük hedefe sayılıyor.
9. Mac'in Günlük Tekrar'ında tur özeti yok. Yeni kelime beklerken "Hepsi Güçlü" yazıyor ve tur kendiliğinden yeniden başlıyor; iPhone'la akış farklı.
10. Küçük maddeler: Eşleştir'de hata hep soldaki kelimeye yazılıyor; Harfleri Diz'de çözülen kelime özette ✗ olabiliyor ve ipucu yok. Hiç bilinmemiş kelime "%50" görünüyor. "Neredeyse"de yazılan cevap gösterilmiyor. Hızlı Tur kartında "1 dakika" yazıyor, tahmin 25 sn/kelime.

---

# Tur İçi Oyun Mantığı Denetimi (2-tur-ici.md)

Örnek defter: `me/ben`, `you/sen`, `deneme/deneme`, `denemw/deneme` (4 kelime, büyük ihtimalle cümlesiz).

## A. Ortak altyapı

**GameRound** (`Shared/Logic/GameRound.swift`) şu oyunları taşıyor: Çoktan Seçmeli, Boşluğu Doldur, Harfleri Diz, Eşleştir ve karışık Hızlı Tur.
- Kelimeler `WordPicker.order` ile ağırlıklı ve tekrarsız seçiliyor. Önceki turun ilk kelimesi mümkünse ilk sıraya gelmiyor (satır 34-62).
- Yanlış bilinen kelime tur içinde tekrar sorulmuyor. Tur, `index == words.count` olunca bitiyor.
- Özetteki ✓/✗, kelimenin turdaki ilk cevabından geliyor (satır 72-75).

**StudySession** (`Shared/Logic/StudySession.swift`) şunları taşıyor: Günlük Tekrar, Yeni Eklenenler (Tanış), Yine de Çalış, Ters Yön ve Hızlı Tur içindeki tek kelimelik hatırlama soruları.
- Yanlış bilinen kelime `reinsertionIndex = min(2, queue.count)` konumuna geri konuyor ve bilinene kadar soruluyor (satır 312-316).
- Tur, sıra boşalınca bitiyor. Özetteki ✓/✗ yine ilk cevaptan geliyor (satır 331-333).

**Aynı gün tekrar oynama:** `ReviewRecorder.swift:34-35` aynı gün hafızayı ikinci kez değiştirmiyor. Ama yanlış cevap yine zayıf işaretliyor, doğru cevap da o zayıflığı temizliyor (satır 50-56). Günlük hedef ise her cevabı sayıyor.

## B. Oyun oyun akış

1. **Çoktan Seçmeli** (`ChoiceGameView.swift`)
   - Tur en fazla 10 soru; 4 kelimede 4 soru.
   - Şıklar defterin tamamından geliyor. Doğru cevapla ortak anlamı olan kelime ve aynı metin çeldirici olmuyor (`ChoiceQuiz.swift:51-56`).
   - deneme/denemw sorusunda öbür kelime çeldirici olmuyor. Sonuç: iki doğru şık çıkmıyor ama şık sayısı 3'e düşüyor.
   - Doğru seçimde 0,8 sn sonra kendiliğinden geçiyor; yanlışta "Devam" beliriyor. Tur içinde tekrar yok.
2. **Boşluğu Doldur** (`FillBlankGameView.swift`)
   - Yalnızca cümlesinde kelimenin kendisi geçen kelimeler, en fazla 10 soru.
   - Çeldiriciler, bütün defterdeki İngilizce kelimeler. Karşılaştırma yalnızca İngilizce yazılışa bakıyor (satır 68-69).
3. **Harfleri Diz** (`LettersGameView.swift`)
   - En fazla 14 harfli kelimeler, 8 soru.
   - Yuvalar dolunca kontrol ediliyor. Notlama: 0 hata iyi, 1-2 hata zor, 3 ve üstü hata ya da "Göster" yanlış sayılıyor (`LetterPuzzle.swift:104-107`).
4. **Eşleştir** (`MatchGameView.swift`)
   - 5 çift. Ortak anlamı olan kelimeler aynı tahtaya konmuyor (satır 200). Örnek defterde bu yüzden 3 çift kalıyor.
   - Kelime, yanlış bir çiftte **sol** taraftaysa özette ✗ oluyor (`MatchBoard.swift:37`).
5. **Hızlı Tur (karışık)** (`QuickMixGameView.swift`)
   - 5 soru; her soru için oyun türü rastgele. Hatırlama soruları tek kelimelik ayrı bir `StudySession`'la soruluyor.
   - Yanlış bilinen kelime tekrar sorulmuyor, çünkü oturum atılıyor (satır 151-163).
6. **Günlük Tekrar / Tanış / Yine de Çalış** (`RecallGameView.swift`)
   - Yanlış kelime bilinene kadar tekrar geliyor.
   - "Bir Tur Daha" planı sessizce değiştiriyor: Tanış → Günlük Tekrar → Yine de Çalış (satır 58-70).
7. **Ters Yön** (`RecallGameView`, `.reverse` planı)
   - Defterin tamamından 10 kelime, örnek defterde 4.
   - Cevap önce birebir karşılaştırılıyor. 5 ve daha uzun kelimelerde 1 harf fark "Neredeyse" sayılıyor (`ReverseChecker.swift:22`).

## C. Bulgular (önem sırasıyla)

**1. Gerçek hata (yüksek): Mac'te "Başla" düğmesi "Tur Bitti" ekranını açıyor.**
- Yer: `Mac/MacStudyView.swift:86-92`.
- Nasıl oluyor: `refresh()` yalnızca `!session.isPracticeAll` iken yeni Günlük Tekrar başlatıyor. Aynı gün "Yine de Çalış" turu bittiyse, sonra bir kelime eklenince ya da zayıflayınca hub kartı "Başla" gösteriyor. Tıklanınca `sync` çalışıyor; plan `.weak` olmadığı için hiçbir şey eklemiyor ve ekran "Tur Bitti / Yine de Çalış" kalıyor.
- Düzeltme: `current == nil` ise plana bakmadan `startDailyIfNeeded()` çağrılmalı. Ya da hub düğmesi `hasWork` doğruysa turu doğrudan `.daily` ile başlatmalı (`MacGamesView.swift:132`).

**2. Gerçek hata (yüksek): Yanlış bilinen son kelime hemen yeniden soruluyor.**
- Yer: `WordPicker.swift:77-79` ve `StudySession.swift:315`.
- Nasıl oluyor: sıra boşken `reinsertionIndex` 0 dönüyor ve aynı kart hemen geliyor. Spec §3'teki "Aynı kelime art arda gelmez" kuralına ve "sonucu belli şeyi tekrar sorma" isteğine aykırı. Ayrıca bu ikinci doğru cevap `clearsLapse=false` olduğu için kelimeyi zayıflıktan çıkarmıyor; yani yeniden sormak hiçbir işe yaramıyor. Sondan bir önceki kelimede arada yalnızca 1 kart kalıyor.
- Düzeltme: araya konacak başka kelime yoksa kelime yeniden kuyruğa girmemeli. Tur bitsin, kelime zayıf kalsın ve Günlük Tekrar'a düşsün. Ya da en az 2 kart aralığı sağlanamıyorsa yeniden sorulmasın.

**3. Gerçek hata (yüksek): Boşluğu Doldur'da iki doğru şık.**
- Yer: `FillBlankGameView.swift:68-69` ve `QuickMixGameView.swift:131`.
- Nasıl oluyor: İngilizce şıkların anlam kümesi yalnızca yazılıştan oluşuyor. Ekrandaki ipucu Türkçe "deneme" iken "denemw" de şık olarak çıkıyor; ipucuna göre iki şık da doğru.
- Düzeltme: şıklar `Candidate(text: english, meanings: AnswerChecker.meanings(in: turkish))` ile kurulmalı. Doğru cevap da aynı şekilde kurulmalı ki ortak Türkçe anlamı olan kelime elensin.

**4. Gerçek hata (orta-yüksek): Ters Yön'de ortak Türkçe anlamlı kelimeler.**
- Yer: `StudySession.swift:228-234` ve `ReverseChecker`.
- Nasıl oluyor: "deneme" sorusunun defterde iki geçerli İngilizcesi var. Öbür kelimeyi yazmak 5+ harfte "Neredeyse" (zor ama bilindi), kısa kelimede "Tam tutmadı" sayılıyor. Eşanlamlılar (bayat: stale/outdated) de "Doğru Say" gerektiriyor.
- Düzeltme: cevap, defterde istenen Türkçe anlamı taşıyan başka bir kelimeyse şu gösterilsin: "Doğru, ama bu kartta aranan: X". Tercihen soru kartına bir ayırt edici ipucu da eklensin (ilk harf ya da harf sayısı).

**5. Kafa karıştıran (orta): Yanlıştan sonra sayaç ilerlemiyor.**
- Yer: `GameScaffold.swift:177`, ekranda `min(done+1, total)` gösteriliyor; `RecallGameView.swift:20`.
- Nasıl oluyor: `done`, bilinen kelime sayısı (`finishedWordCount`). İlk kelime yanlışsa ikinci kelime de "1/4" görünüyor, sayaç takılmış gibi duruyor. Erişilebilirlik etiketi de ("4 kelimeden 1. kelime") yanlış bilgi veriyor.
- Ayrıca Mac'te aynı tur `"\(remaining+1) kaldı"` ile gösteriliyor ve yanlışta sayı büyüyor (`MacStudyView.swift:68,109-112`). İki platform farklı.
- Düzeltme: hatırlama oyunlarında "2/4 bilindi" gibi bir metin ya da yalnızca çubuk kullanılsın. Mac, iPhone'daki `GameProgressHeader` ile aynı olsun.

**6. Gerçek hata (orta): Açılma koşulu ham kelime sayısına bakıyor.**
- Yer: `GameMode.swift:81-82` ve `QuickMix.swift:26-27`.
- Nasıl oluyor: `deck.count >= 4` koşulu, ortak anlamlı ya da aynı yazılışlı kelimeleri ayrı sayıyor. Örnek defterde Çoktan Seçmeli 3 şık, Eşleştir 3 çift çıkıyor; tüm kelimeler aynı anlamdaysa 1 şık ya da 1 çift çıkabilir. Kartta ise "4 seçenekten doğrusu" yazıyor.
- Düzeltme: `GameDeck`'e "farklı anlam sayısı" alanı eklenmeli (ilk anlama göre kümeleyip ortak anlamlıları birleştirerek). Koşul bu sayıyla ≥ 4 olmalı.

**7. Gerçek hata (orta): Türkçe cevap kontrolü çok gevşek.**
- Yer: `AnswerChecker.swift:63-71`.
  - `wordsMatch` yalnızca "baştan eşleşme ve olumsuzluk eki yok" koşuluna bakıyor. Bu yüzden "kara" ↔ "karar" ve "kale" ↔ "kalem" doğru sayılıyor.
  - Satır 23'te kullanıcının cevabı da virgülle bölünüyor. "ben, sen, deneme" gibi bir tahmin listesi yazmak doğru sayılıyor.
- Düzeltme:
  - Kalan kısım bilinen bir Türkçe ek listesinden biri olmalı (-mek/-mak, -ler/-lar, -i, -de…).
  - Kullanıcının cevabı bölünmemeli; ya da birden fazla parça yazıldıysa hepsinin tutması istenmeli.

**8. Gerçek hata ve tasarım sorusu (orta): Seçmeli oyunlarda aynı gün tekrar oynama.**
- Yer: `GameRound.swift:76-79`; `clearsLapse` hep true gidiyor.
- Nasıl oluyor: Çoktan Seçmeli'de yanlış bilinen kelime, "Bir Tur Daha"da az önce görülen doğru şıkla bilinince zayıflıktan çıkıyor. Az kelimeli defterde bu hemen oluyor, çünkü "Bir Tur Daha" aynı 4 kelimeyi yalnızca sırasını değiştirerek getiriyor (satır 34-51). Hafıza değişmiyor ama ReviewLog yazılıyor ve günlük hedef doluyor.
- Düzeltme:
  - Aynı gün bir önceki yanlıştan sonra gelen tanıma cevabında `clearsLapse=false` gitsin. Zayıflığı yalnızca hatırlama oyunları temizlesin.
  - Tasarım sorusu: tur özeti az kelimede ve aynı gün "Bu kelimeler bugün zaten çalışıldı; hafıza yarın değişir" diye açıkça söylesin mi?

**9. Tasarım farkı (orta): Mac Günlük Tekrar ile iPhone ayrışıyor.**
- Yer: `MacStudyView.swift:50-56,94-150`.
  - Mac'te tur özeti (✓/✗ listesi) yok. Bitince yalnızca "Bu turda N cevap verdin" yazıyor; bu sayı tekrar sorulan kartları da içeriyor.
  - Yeni kelime beklerken bile "Hepsi Güçlü" başlığı çıkıyor. Pencere yeniden açılınca sıradaki 5 yeni kelimeyle kendiliğinden yeni tur başlıyor (satır 87-88, 101-105).
  - Zayıf kelime kaldıysa tur özet göstermeden kendiliğinden devam ediyor.
- Düzeltme: Mac'te de tur sonunda `RoundSummaryView` gösterilsin. Tur kendiliğinden yeniden başlamasın; kullanıcı "Bir Tur Daha"ya bassın. "Hepsi Güçlü" yalnızca gerçekten iş kalmadığında görünsün.

**10. Kafa karıştıran (orta-düşük): "Bir Tur Daha" planı sessizce değiştiriyor.**
- Yer: `RecallGameView.swift:61-68`.
- Nasıl oluyor: Tanış → Günlük Tekrar → Yine de Çalış geçişi hiçbir yerde belirtilmiyor.
- Mac'e özgü ek: "Tanış"tan gelen Günlük Tekrar, `MenuBarView`'deki kalıcı turdan ayrı ikinci bir tur açıyor. Hub'da "Devam Et" yazıyor ama o turun kelimeleri az önce öbür turda cevaplanmış oluyor.
- Düzeltme: özet ekranındaki düğme ne açacaksa onu yazsın ("Günlük Tekrar'a Geç", "En Zayıflarla Çalış"). Mac'te bu geçiş kalıcı `session`'a yönlendirilsin.

**11. Kafa karıştıran (düşük-orta): Eşleştir'de hata kime yazılıyor.**
- Yer: `MatchBoard.swift:36-38`.
- Nasıl oluyor: kullanıcı önce sağdan Türkçe anlamı seçip yanlış İngilizce kelimeye götürürse ✗, yanlış bilinen anlamın kelimesine değil soldaki kelimeye yazılıyor.
- Düzeltme: ilk seçilen kutu "soru" sayılsın; hata onun kelimesine yazılsın.

**12. Kafa karıştıran (düşük): Harfleri Diz.**
- Yer: `LetterPuzzle.swift:104-107`.
  - 3 yanlış denemeden sonra doğru dizilen kelime ekranda yeşil kutluyor ama özette ✗ çıkıyor.
  - Harf harf ipucu yok; "Göster" cevabın tamamını açıyor.
  - Büyük harfli kelimelerde taşlar yazıldığı gibi gösteriliyor ("P"), bu da ilk harfi ele veriyor.
- Düzeltme:
  - Özette ✗ yerine "zorlandın" gibi bir durum gösterilsin, ya da ✓/✗ eşiği ekranla uyumlu hale getirilsin.
  - "İpucu" düğmesi sıradaki doğru harfi yerleştirsin ve bir hata sayılsın.
  - Taşlar küçük harfle gösterilsin.

**13. Gösterge sorunu (düşük): "%50" rozeti.**
- Yer: `RecallGameView.swift:145` ve `Memory.lapseTarget`.
- Nasıl oluyor: hiç bilinmemiş yeni kelime ilk cevapta yanlış olunca soru kartında ve listede "%50" görünüyor. Bu, kelimenin yarı bilindiğini ima ediyor.
- Ayrıca soru kartındaki halka cevaptan önce hafızayı gösteriyor. Tekrar gelen kelimede "%50" görmek, kullanıcıya kelimeyi az önce bilemediğini hatırlatıyor.
- Düzeltme: en az bir kez doğru bilinmemiş kelimede "Öğreniliyor" ya da "Yeni" yazılsın (bu konuyu hafıza motoru ajanıyla birlikte ele alın). Soru kartındaki halkanın gerekli olup olmadığı da sorgulanmalı.

**14. Küçük maddeler (düşük).**
- "Neredeyse"de kullanıcının yazdığı cevap gösterilmiyor; yalnızca "Tam tutmadı"da gösteriliyor (`RecallGameView.swift:230`). Spec §5.8 "Neredeyse: doğrusu X" istiyor; yazılan cevapla fark da gösterilmeli.
- Mac'te "Göster"in kısayolu ⌘↩, ipucu metni ise "(↩)" diyor (`RecallGameView.swift:337-338`).
- Hızlı Tur kartında "5 kelime, 1 dakika" yazıyor (`GameMode.swift:55`), ama zamanlayıcı yok ve tahmin 25 sn/kelime (`RoundText.swift:6`).
- Cümlede kelime iki kez geçiyorsa yalnızca ilki boşaltılıyor; ikincisi cevabı gösteriyor (`ClozeSentence.swift:23-35`).
- Spec'teki "önce aynı kaynaktan çeldirici" kuralı uygulanmamış (`ChoiceQuiz.swift:48`).

**15. Hafıza motoru ajanına devir.**
- "5 yeni/gün" sınırı aslında tur başına işliyor: `dailyCount` bugün tanıtılmış yeni kelimeleri saymıyor (`StudySession.swift:212-219`). Günlük Tekrar'da "Bir Tur Daha"ya basınca ya da Mac penceresi yeniden açılınca 5 yeni kelime daha geliyor.

## D. Doğru çalışanlar

- Özetteki "x/y doğru" ile satırlar aynı listeden (`entries`) hesaplanıyor; silinen kelime ikisinden de düşüyor.
- Süre, duraklatma dahil doğru hesaplanıyor.
- Çoktan Seçmeli ve Eşleştir'de ortak anlam, iki doğru şık ya da iki aynı kutu üretmiyor.
- Büyük/küçük harf ve Türkçe karakterler (ı/i, ş/s) iki kontrolde de tolere ediliyor. Olumsuzluk ("mümkün değil") doğru reddediliyor.
- "Göster" sonrası yalnızca Bildim/Bilemedim soruluyor: Bildim "zor", Bilemedim "yanlış" sayılıyor ve kelime yeniden kuyruğa giriyor.

### Critical Files for Implementation
- Mac/MacStudyView.swift
- Shared/Logic/StudySession.swift
- Shared/Logic/WordPicker.swift
- Shared/Games/FillBlankGameView.swift
- Shared/AnswerChecker.swift