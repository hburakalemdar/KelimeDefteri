# 11 — V4F ile SADE karşılaştırması

Betik: `scratchpad/motor/compare.py` (ortak parçalar `sim.py` v4'ten: 04:00 gün sınırı, tam gün t, ilk cevap tablosu,
büyüme, tavanlı yanlış, tanıma çarpanları ve tavanı, zayıfken 0,5 ceza, learnedAt kuralları, seçim vadeye bakar).
`python3 compare.py` → ekteki ham çıktı (~7 dk). Belge değiştirilmedi.

- **V4F** = v4 + dört düzeltme: oran kuralı (>1/3 again, ≤1/3 hard); o gün üretim cevabı (hatırlama/Ters Yön/Harfleri Diz)
  varsa oran yalnız onlardan hesaplanıyor; tur içi yeniden sorma ve "Aynı Kelimelerle Tekrar" cevapları birincil sayılmıyor;
  `lapsedAt`/vade her cevapta `dayStartLapsedAt`'ten yeniden hesaplanıyor.
- **SADE** = S/D'yi günün cevabı belirliyor: günün ilk üretim cevabı, o gün üretim cevabı yoksa ilk tanıma cevabı.
  Günün herhangi bir yanlışı kelimeyi zayıflatıyor ve vadeyi yarına alıyor (S/D'ye dokunmadan); sonraki doğrular hiçbir şeyi değiştirmiyor.
  Uygulama varsayımı: sonradan gelen üretim cevabı gün başından yeniden hesaplandığı için SADE de `dayStart*` alanlarını kullanıyor.

## Özet karar tablosu

| Ölçüt | V4F | SADE |
|---|---|---|
| Kullanıcının şikâyeti: "doğru bildim, sonra yanlış yaptım, hafızaya işlenmedi" | **İşleniyor**: S 30 → 11,4, ertesi gün doğruyla 13 gün | **İşlenmiyor**: S 82 kalıyor; ertesi gün doğruyla **83 gün sonra** (yanlış yalnızca bir gün ekliyor) |
| Sıra bağımsızlığı (300 rastgele gün, gün içi sıra karıştırıldı) | **0/300** fark | **292/300** fark; S oranı medyan ×1,9, en kötü ×25 |
| "Sabah doğru, akşam yanlış", 60 gün | S 0,3, D 10, zayıf | **S 107**, D 5, her gece zayıf / her sabah rozet |
| Tanıma doğrularıyla yanlışı silmek | kapalı | kapalı |
| Kolay üretim oyunuyla yanlışı silmek | **açık**: hatırlama Y + 2 ayrı oyunda D → hard, S 56 | kapalı (sonraki doğrular sayılmıyor) |
| Önce kolay oyun, sonra hatırlama yanlış | kapalı (again, 11,4) | **açık**: önce Harfleri Diz D, sonra hatırlama Y → S **71,7** (yalnız yarın sorulur) |
| %90 bilen, vade günü 1–10 oyun | 489–500/500 Öğrenildi | 488–498/500 |
| %90 bilen, her gün 3 / 10 oyun | **439 / 472** | 194 / 124 (her akşam yanlış → gün sonu zayıf) |
| %70 bilen, vade günü 2 / 5 / 10 oyun | **297** / 189 / 251 | 432 / 309 / **52** |
| Tahminci (yalnız tanıma %25 ya da karışık) | 0/500 | 0/500 |
| Word ek alanı | 5 (`lapsedAt` + 4 `dayStart*`) | 5 (aynı; sonradan gelen hatırlamayla yeniden hesap için) — o kural atılırsa **1** (`lapsedAt`) |
| ReviewLog ek alanı | **1** (`isPrimary`: yeniden sorma/tekrar tur işareti) | 0 |
| Kural sayısı (gün değerlendirmesi) | ~8 | ~4 |

## 1. Sezgi senaryoları — farklar

İki model 14 senaryonun 11'inde birebir aynı sonucu veriyor: salt doğru/yanlış, yanlış→doğru (yeniden sorma, ayrı tur ya da
tekrar tur), yanlış + tanıma doğruları, dün yanlış bugün doğru, yeni kelime, S=300. Ayrıldıkları üç senaryo:

| Senaryo | V4F | SADE |
|---|---|---|
| Doğru → (ayrı tur) bilerek yanlış | S 11,4 · Öğreniliyor · Yarın → ertesi gün doğru: 13 gün | S **82,1** · Öğreniliyor · Yarın → ertesi gün doğru: **83 gün** |
| Sabah doğru, akşam yanlış | aynı (11,4 → 13 gün) | aynı (82 → 83 gün) |
| D, D, Y (üç ayrı oyun) | hard: S 56 · 56 gün · rozet (zayıflamaz) | S 82 · Öğreniliyor · Yarın → 83 gün |

SADE'de akşamki yanlış kelimeyi yalnızca **ertesi güne** taşıyor. Ertesi gün bir doğru gelirse kelime, yanlış hiç
olmamış gibi 83 gün sonraya gidiyor. Bu, kullanıcının "yanlış hafızaya işlenmiyor" şikâyetinin aynısı. Ekranda
"Öğreniliyor · Yarın" doğru görünüyor ama dayanıklılık (S) yanlışı hiç görmüyor.

## 2. Öğrenme sonuçları

Tam tablo ekte. Özet:
- **Normal kullanım** (vadesinde bir kez, %90 ya da %70 bilen): iki model **aynı** sonucu veriyor (496/500 ve 464/500;
  Öğrenildi medyan 18. ve 24. gün). Aynı gün birden fazla cevap yoksa iki model aynı motor.
- **Aynı gün çok oynayan, iyi bilen**: V4F çok daha iyi. SADE'de akşamki tek bir yanlış kelimeyi her gece "zayıf"a
  döndürüyor (her gün 10 oyun, %90: gün sonunda canlı rozet 124/500, zayıf gün medyanı 78). S ise sabahki cevapla
  büyümeye devam ediyor; sayılar ile rozet birbirinden kopuyor.
- **Aynı gün çok oynayan, zayıf bilen (%70)**: vade günü 2 oyunda SADE daha iyi (432'ye 297). V4F'te iki cevaptan
  biri yanlışsa oran 1/2 çıkıyor, gün `again` sayılıyor; bu, 9-simulasyon-v4'teki O1 bulgusu. 10 oyunda ise V4F
  çok daha iyi (251'e 52).
- **Tahminciler**: iki modelde de 0/500. **Yalnız tanıma**: iki modelde aynı (zayıf gün medyanı 8, rozet yok).
  **30 gün ara**: aynı.

## 3. Oyunlanabilirlik

- V4F'te kalan açık: hatırlama yanlışından sonra **başka üretim oyunlarında** (Ters Yön, Harfleri Diz) 2 doğru → oran 1/3
  → hard, S 56, 56 gün. Cevap birkaç dakika önce görülmüş olduğu için bu kanıt zayıf. *Olası kapatma:* "Aynı Kelimelerle
  Tekrar" gibi, yanlıştan sonra **aynı oturumda** (ör. 30 dk içinde) gelen üretim cevaplarını da birincil saymamak. Bu,
  yalnızca yanlış→doğru yönünde küçük bir sıra etkisi getirir; o yön zaten nedenseldir, çünkü kullanıcı cevabı gördü.
- SADE'deki açık: gün **kolay bir üretim oyunuyla** açılırsa (Harfleri Diz), aynı gün sonra gelen hatırlama yanlışı S'ye
  hiç dokunmuyor (71,7). Kullanıcı bunu bilerek yapmasa da oyun sırası tamamen tesadüfi olduğu için sonuç rastgele.
- Tahminle "Öğrenildi": iki modelde de mümkün değil (0/500).

## 4. Sıra bağımlılığı — SADE'de ne kadar zararlı?

Çok zararlı. 300 rastgele günün 292'sinde sonuç değişiyor; S farkı medyanda 1,9 kat, en kötü durumda 25 kat.
"Sabah doğru, akşam yanlış" deseniyle 60 günde S **107**'ye çıkıyor, tersi sırada 0,3'te kalıyor. Aynı cevaplar gün
içinde yer değiştirince kelime ya ~3,5 ay sonrasına ya da her güne düşüyor. Kullanıcıya göre bu açıklanamaz: "dün de
bugün de aynı şeyi yaptım."

## 5. Karmaşıklık ve hata riski

| | V4F | SADE |
|---|---|---|
| Word alanları | `lapsedAt`, `dayStartStability`, `dayStartDifficulty`, `dayStartAt`, `dayStartLapsedAt` | Aynı 5 alan (sonradan gelen hatırlamayla yeniden hesap için). "Günün ilk cevabı, türü ne olursa olsun" denirse yalnız `lapsedAt`, ama o zaman widget'ın tanıma cevabı günün S'sini belirler. |
| ReviewLog | **+1 alan** (`isPrimary`; yeniden sorma ve tekrar tur cevaplarını ayırmak için, CloudKit'e ekleme) | değişiklik yok |
| Kurallar | gün başı dondurma, birincil filtre, üretim önceliği, oran eşikleri (3 dal), hard kaynağı, zayıflığı geri alma, 2.5 temizleme, learnedAt'i aynı gün geri alma | günün cevabını seçme, gün içi yanlış → zayıf/yarın, 2.5 temizleme, learnedAt |
| Hata riski | Orta-yüksek. Her cevapta günün bütün log'larını okuyup yeniden hesaplıyor. Öteki cihazdan geç gelen log, günün sonucunu bir sonraki cevaba kadar eski bırakır. `isPrimary`'yi oyunların doğru işaretlemesi gerekir (6+ oyun görünümü). Gün farkı takvim bileşeniyle alınmalı (9-simulasyon-v4 notu). | Düşük-orta. Tek bir "günün cevabı" seçimi; log'dan yalnızca ilk üretim cevabını bulmak. |
| Test yüzeyi | Büyük (oran sınırları, birincil ayrımı, geri alma) | Küçük |

## Her iki modelde ortak yeni bulgu (Orta): widget, hatırlamayı hiç sıraya sokmuyor

Her sabah widget'ta doğru cevap verilen bir kelimede `lastReviewedAt` her gün yenileniyor. Bu yüzden hafıza hiç
0,9'un altına inmiyor ve `isWeak` hiçbir zaman true olmuyor: kelime Günlük Tekrar'a (hatırlama) **120 günde yalnızca
3 kez** geliyor. Tanıma tavanı yüzünden S 20,9'da kalıyor, kelime asla "Öğrenildi" olmuyor (iki modelde de 0/500).
*Öneri:* tanıma cevabı `lastReviewedAt`'i (ekran/seçim çıpası) ilerletmesin ya da seçim, S<21 kelimede vade `now+S`'e
göre yapılsın; bu sayede tanıma, hatırlamanın yerini almasın.

## Öneri

**V4F.** Sıra bağımsızlığı tam (0/300), kullanıcının asıl şikâyetini (doğru bildikten sonraki yanlışın dayanıklılığa
işlenmemesi) gideriyor, aynı gün çok oynayan ve iyi bilen kullanıcıyı cezalandırmıyor. Normal kullanımda SADE ile aynı
sonucu veriyor. Bedeli daha fazla kural ve ReviewLog'a bir `isPrimary` alanı; bu bedel testle karşılanabilir.
SADE daha basit ama iki ciddi kusuru var: yanlışın S'ye işlenmemesi (şikâyetin kendisi) ve oyun sırasına göre ×25'e
varan rastgele sonuçlar. Bu ikisi, yeniden tasarımın çıkış noktası olan sorunlar.
V4F'e iki küçük ek önerilir: (1) yanlıştan sonra aynı oturumda (~30 dk) gelen üretim cevapları birincil sayılmasın
(kalan sulandırma açığı); (2) iki cevaplı gün için eşik kararı (1D+1Y: again mi hard mı; 9-simulasyon-v4 O1).

---

# Ek: ham çıktı (`python3 compare.py`)

## 1. Kullanıcı sezgisi senaryoları

Her satır: günün sonundaki durum (S · D · vade/durum metni · ekran %), sonra **ertesi gün vadesinde bir doğru** gelirse ne olduğu (yanlışın kalıcı etkisi). Başlangıç: S=30, D=5, son tekrar 30 gün önce, önce "Bugün".

| Senaryo | V4F gün sonu | V4F ertesi doğru | SADE gün sonu | SADE ertesi doğru |
|---|---|---|---|---|
| S=30 vadesinde doğru | S 82.1 · D 5.00 · 82 gün sonra · %100 · rozet | g112: S 198.5 · 198 gün sonra | S 82.1 · D 5.00 · 82 gün sonra · %100 · rozet | g112: S 198.5 · 198 gün sonra |
| S=30 vadesinde yanlış | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| Doğru → (ayrı tur, "bilerek") yanlış | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 82.1 · D 5.00 · Öğreniliyor · Yarın · %50 | g31: S 83.7 · 83 gün sonra |
| Yanlış → (tur içi yeniden sorma) doğru | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| Yanlış → (ayrı tur, farklı oyun) doğru | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| Yanlış → "Aynı Kelimelerle Tekrar" 2 tur doğru | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| Yanlış + 2 tanıma doğrusu (widget) | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| 2 tanıma doğrusu (widget, sabah) + hatırlama yanlış (akşam) | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| Sabah doğru, akşam yanlış (farklı oyun) | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 82.1 · D 5.00 · Öğreniliyor · Yarın · %50 | g31: S 83.7 · 83 gün sonra |
| Sabah yanlış, akşam doğru (farklı oyun) | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra | S 11.4 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.4 · 13 gün sonra |
| 3 tur: D, D, Y (farklı oyunlar) | S 56.0 · D 5.34 · 56 gün sonra · %100 · rozet | g86: S 137.0 · 137 gün sonra | S 82.1 · D 5.00 · Öğreniliyor · Yarın · %50 | g31: S 83.7 · 83 gün sonra |
| Dün yanlış, bugün doğru | S 13.4 · D 5.72 · 13 gün sonra · %100 | g44: S 36.8 · 37 gün sonra | S 13.4 · D 5.72 · 13 gün sonra · %100 | g44: S 36.8 · 37 gün sonra |
| Yeni kelime: yanlış → yeniden sorma doğru → ertesi gün doğru | S 2.8 · D 6.70 · 3 gün sonra · %100 | g4: S 8.8 · 8 gün sonra | S 2.8 · D 6.70 · 3 gün sonra · %100 | g4: S 8.8 · 8 gün sonra |
| S=300 vadesinde yanlış | S 52.0 · D 5.85 · Öğreniliyor · Yarın · %50 | g301: S 53.4 · 53 gün sonra | S 52.0 · D 5.85 · Öğreniliyor · Yarın · %50 | g301: S 53.4 · 53 gün sonra |

## 3. Oyunlanabilirlik

| Girişim (S=30 vadesinde) | V4F | SADE |
|---|---|---|
| Hatırlama yanlış + 5 tanıma doğrusu | again · S 11.4 · Öğreniliyor · Yarın | again · S 11.4 · Öğreniliyor · Yarın |
| Hatırlama yanlış + 2 Harfleri Diz doğrusu (ayrı oyun) | hard · S 56.0 · 56 gün sonra | again · S 11.4 · Öğreniliyor · Yarın |
| Hatırlama yanlış + 2 Ters Yön/hatırlama doğrusu (ayrı oyun) | hard · S 56.0 · 56 gün sonra | again · S 11.4 · Öğreniliyor · Yarın |
| Önce tanımada doğru (widget), sonra hatırlama yanlış | again · S 11.4 · Öğreniliyor · Yarın | again · S 11.4 · Öğreniliyor · Yarın |
| Önce Harfleri Diz doğru, sonra hatırlama yanlış | again · S 11.4 · Öğreniliyor · Yarın | again · S 71.7 · Öğreniliyor · Yarın |

## 4. Sıra bağımlılığı

- **V4F**: 300 rastgele 8-günlük dizide gün içi sıra karıştırılınca S/zayıflık/learnedAt farklı çıkan: 0/300 (karışık modlar; S oranı medyan ×1.00, en kötü ×1.0) · yalnız hatırlama: 0/300 (medyan ×1.00, en kötü ×1.0)
- **SADE**: 300 rastgele 8-günlük dizide gün içi sıra karıştırılınca S/zayıflık/learnedAt farklı çıkan: 292/300 (karışık modlar; S oranı medyan ×1.74, en kötü ×18.3) · yalnız hatırlama: 298/300 (medyan ×1.90, en kötü ×24.9)

| 60 gün, her gün aynı desen (yeni kelimeden) | V4F S / D / zayıf / learnedAt | SADE S / D / zayıf / learnedAt |
|---|---|---|
| sabah D, akşam Y | 0.3 / 10.00 / evet / yok | 107.0 / 5.00 / evet / yok |
| sabah Y, akşam D | 0.3 / 10.00 / evet / yok | 0.3 / 10.00 / evet / yok |
| D D Y | 41.6 / 7.27 / hayır / var | 107.0 / 5.00 / evet / yok |
| Y D D | 41.6 / 7.27 / hayır / var | 0.3 / 10.00 / evet / yok |
| 5D sonra 5Y | 0.3 / 10.00 / evet / yok | 107.0 / 5.00 / evet / yok |

## 2. Öğrenme sonuçları (500 tohum, 120 gün)

Hücre: **120. gün canlı Öğrenildi / 500** · learnedAt medyan günü (ulaşan sayısı) · zayıf gün medyanı.

| Kullanıcı | V4F | SADE |
|---|---|---|
| %90 bilen, vade günü 1 oyun | **496** · g18 (500) · zayıf 0 | **496** · g18 (500) · zayıf 0 |
| %90 bilen, vade günü 2 oyun | **489** · g18 (500) · zayıf 1 | **496** · g18 (500) · zayıf 1 |
| %90 bilen, vade günü 3 oyun | **500** · g18 (500) · zayıf 0 | **498** · g18 (500) · zayıf 1 |
| %90 bilen, vade günü 5 oyun | **497** · g21 (500) · zayıf 0 | **496** · g19 (500) · zayıf 3 |
| %90 bilen, vade günü 10 oyun | **500** · g26 (500) · zayıf 0 | **488** · g20 (500) · zayıf 7 |
| %70 bilen, vade günü 1 oyun | **464** · g24 (498) · zayıf 2 | **464** · g24 (498) · zayıf 2 |
| %70 bilen, vade günü 2 oyun | **297** · g42 (423) · zayıf 10 | **432** · g26 (494) · zayıf 5 |
| %70 bilen, vade günü 3 oyun | **443** · g31 (492) · zayıf 2 | **413** · g29 (481) · zayıf 10 |
| %70 bilen, vade günü 5 oyun | **189** · g54 (294) · zayıf 13 | **309** · g38 (441) · zayıf 28 |
| %70 bilen, vade günü 10 oyun | **251** · g54 (348) · zayıf 6 | **52** · g59 (121) · zayıf 92 |
| %90 bilen, HER gün 1 oyun | **251** · g12 (500) · zayıf 12 | **251** · g12 (500) · zayıf 12 |
| %90 bilen, HER gün 3 oyun | **439** · g11 (500) · zayıf 3 | **194** · g13 (500) · zayıf 33 |
| %90 bilen, HER gün 10 oyun | **472** · g16 (500) · zayıf 1 | **124** · g14 (500) · zayıf 78 |
| %70 bilen, HER gün 1 oyun | **14** · g49 (321) · zayıf 36 | **14** · g49 (321) · zayıf 36 |
| %70 bilen, HER gün 3 oyun | **15** · g54 (223) · zayıf 26 | **4** · g51 (289) · zayıf 79 |
| %70 bilen, HER gün 10 oyun | **0** · g— (0) · zayıf 42 | **0** · g56 (69) · zayıf 117 |
| Tahminci: yalnız tanıma %25 | **0** · g— (0) · zayıf 111 | **0** · g— (0) · zayıf 111 |
| Tahminci: tanıma %25 ×2 + hatırlama %5, her gün | **0** · g— (0) · zayıf 114 | **0** · g— (0) · zayıf 120 |
| Yalnız tanıma, %90 bilen | **0** · g— (0) · zayıf 8 | **0** · g— (0) · zayıf 8 |
| Widget sabah (hep doğru) + akşam hatırlama %60 | **0** · g— (0) · zayıf 0 | **0** · g— (0) · zayıf 0 |
| 20 gün ideal, 55 gün ara, dönüş doğru | 75. gün S 131.6, 119. gün S 131.6, zayıf hayır | 75. gün S 131.6, 119. gün S 131.6, zayıf hayır |
| 20 gün ideal, 55 gün ara, dönüş yanlış | 75. gün S 16.3, 119. gün S 50.1, zayıf evet | 75. gün S 16.3, 119. gün S 50.1, zayıf evet |
