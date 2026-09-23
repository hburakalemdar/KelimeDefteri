# 18 — SPEC-MOTOR2 v8 simülasyonu (kodlamadan önceki son sürüm)

Betik: `scratchpad/motor/sim_v8.py`. v7 betiği v8 kurallarına göre güncellendi:
- replay yalnızca `date > baseAt` olan logları işliyor;
- göçte `baseAt = max(son log, eski lastReviewedAt)`, hiç cevaplanmamış kelimede `baseAt = distantPast`;
- tanımanın zayıflığı kaldırması yalnız S<21'de;
- "zor" günde sabit `hard` notu, ağırlık en iyi bireysel doğrudan; eşitlikte önce ağırlık, sonra en erken cevap.

Çalıştırma: `python3 sim_v8.py a i t h e o m` → senaryolar, sezgi, §7.1, v8 özel testleri, sıra/geri alma, eşit zaman,
göç; `python3 sim_v8.py v p` → widget/göç testleri ve 500 tohumluk desenler.

Not: Ekteki "F) Göç senaryoları" bölümü karşılaştırma için v7 davranışını (`>=`) ve v7'nin `baseAt` tanımını da gösteriyor.
v8 sonuçları "H) v8 özel testleri" bölümünde.

## Sonuç: **Yüksek bulgu yok.**

## Bulgular

### Orta

**O1 — Göçte iki cihazın taban alanları karışırsa eski loglar iki kez işlenebilir.**
- A cihazı kelimeyi henüz `reviewCount == 0` olarak görüyor ve yalnızca `baseAt = distantPast` yazıyor. B cihazı (eski cevapları
  görmüş) tam taban yazıyor (`baseStability = 34,5`, `baseAt = g13`).
- CloudKit/SwiftData birleştirmesi **alan bazında** yapılırsa (`baseAt` A'dan, `base*` B'den), replay bütün eski logları
  S=34,5 tabanının üstüne yeniden işler. g48'deki bir doğrudan sonra S: kayıt bütün olarak B'den gelirse 93,5; A'dan gelirse 73,4
  (baştan replay); **karışık kayıtta 98,1**.
- Belge "kaydın tamamında son yazan kazanır" varsayıyor. SwiftData'nın birleştirme politikası alan bazında da çalışabilir.
- *Öneri:* göç, `baseAt`'i yazarken bütün `base*` alanlarını da açıkça yazsın (distantPast durumunda `baseStability = 0` vb.).
  Tek başına bu yeterli olmaz, çünkü karışma kayıt değil alan düzeyinde oluyor. Daha sağlam yol: `distantPast` yerine
  `reviewCount == 0` iken `baseAt = en eski logdan önce` gibi bir kural ya da cihazda birleştirme davranışının doğrulanması.
  Tek seferlik, dar bir pencere (kelimenin eski cevapları henüz eşitlenmemişken göç); cihazda doğrulanmalı.

**O2 — Günde 2 cevap hâlâ en kötü durum (açık karar).** %90 bilen, her gün oynayan kullanıcıda Öğrenildi: günde 1 oyun 241,
**2 oyun 102**, 3 oyun 366, 10 oyun 405 (/500). Vade günü oynayanda 486–499.

### Düşük

- **D1 — §7.1'in "Olgun (S≥21) kelime zayıfladıktan sonra iki farklı günde tanıma doğrusu" satırı "Yarın (sabit kalır)" diyor.** Vade
  gerçekten sabit (`lapsedAt + 1` = g301 04:00), ama gerçek zaman ilerlediği için metin g301'de "Bugün", g302'de **"1 gün gecikti"**
  oluyor. Kelime isDue ve Günlük Tekrar'a düşüyor; davranış doğru, satırın metni yanlış.
- **D2 — Eski sürümde bir yanlış günün *ikinci* cevabıysa ve Word kaydı, logundan önce öbür cihaza ulaştıysa:** eski kod
  `lastReviewedAt`'i ilerletmediği için `baseAt` 09:00'da kalıyor. 20:00'deki yanlış log gelince bir kez işleniyor: S 82,09 → 41,05.
  Eski motor bu yanlışta S'ye hiç dokunmamıştı, yani bu çift sayım değil, yanlışın ilk kez işlenmesi. Ancak taban hile yüzünden
  "zaten zayıf" sayıldığı için ×0,5 uygulanıyor (ilk zayıflamada tavan 27,18 olurdu). Tek seferlik, küçük.
- **D3 — Yalnız widget kullanan, olgun kelimesi olan kullanıcı.** Widget yanlışı S'yi çoğunlukla 21'in altına indiriyor; S≥21 kalıp
  zayıf olan ve widget'la hiç kurtulamayan kelime 180 günde 300 kelimede yalnızca 0–1. Yeni kural pratikte takılma yaratmıyor.

## Önceki bulguların durumu

| Bulgu | v8 sonucu |
|---|---|
| v7-Y1: son log iki kez sayılıyordu | **Kapandı.** Zayıf eski kelime (S=11,40): göçte S 11,40, "Öğreniliyor · Bugün", isDue; ertesi gün D → 13,34, "13 gün sonra". Son günü D, D, Y olan kelime S 20 / D 6,00 kalıyor; son log hard ise D 6,00 (değişmiyor). |
| v7-O1: Word logdan önce eşitlenmiş | Günün ilk cevabında (`lastReviewedAt` ilerliyor) **kapandı**: S 11,40, çift sayım yok. İkinci cevabında küçük bir kalıntı kalıyor (D2). |
| v7-O2: günde 2 cevap | Açık karar (O2). |
| v6: widget kilidi, göç çıpası, learnedAt | Hepsi kapalı kalıyor. Widget %100/%90 → 499/500 (medyan 21. gün); %90/%90 → 483/500. S=30, 30 gün gecikmiş, doğru → **125,46**. learnedAt korunuyor; 200 öğrenilmiş eski kelimede kayan **0**. |
| Yeni kural: S≥21 zayıf kelimede tanıma | Doğru çalışıyor. S=300 → Y → 51,96: 3 gün tanıma doğrusuna rağmen zayıf kalıyor, vade sabit (g301 04:00), isDue, ekran %50. Akşam hatırlama doğrusu → 56,36, zayıflık kalkıyor. S<21'de (S=11,4) iki tanıma günüyle kalkıyor (karşılaştırma). |
| Yeni kelime (distantPast) | Doğru: ilk yanlış + ertesi gün doğru → 2,82 (sıfırdan). |

## §7.1 doğrulaması

**Tablodaki her satır betikle birebir tutuyor (tek istisna D1):**
- Yeni kelime ilk yanlış 0,40 / 0,30, D 7,0, "Yarın"; iki turda Y→D 0,40.
- S=30 D→Y = Y→D = salt Y: 11,40 / 5,85 / "Yarın".
- Üç turda 1 Y (her sıra): 56,05 / 5,34 / "56 gün sonra" / learnedAt bugün.
- Yanlıştan 10 dk içinde 2 D → 11,40. Salt D: 82,09 / "82 gün sonra".
- Dün Y, bugün D: 13,38 / 5,72 / "13 gün sonra".
- Üst üste yanlışlar: 5,70 / 6,57 ve 2,85 / 7,19.
- S=300: 51,96 / 5,85 → 53,43 / 5,72 / "53 gün sonra".
- Tanımada şansla doğru, S=10: 20,90 / "11 gün sonra".
- Zayıf kelimede tanıma: 1. gün vade sabit, "Bugün"; 2. gün 14,95 / "12 gün sonra", zayıflık temizleniyor.
- Olgun zayıf kelime + 2 tanıma günü: zayıflık temizlenmiyor (metin D1).
- Olgun kelime yalnızca tanımayla: donuk; 40. gün "10 gün gecikti".
- 23:58/00:02 → 11,40, "Yarın". 03:58/04:02 → 13,38.
- İki cihaz, eşitlemeden sonra: 56,05 / 5,34.
- Geri alma: birebir.

## Ek kontroller

- **Sıra, iki cihaz, geri alma:**
  - Karıştırılmış log sırası 300/300 aynı; önbellek = tam replay, 300/300.
  - İki cihaz tam eşitlemeden sonra 300/300 aynı; eşitleme gecikirken geçici fark 170/300.
  - Son log silindiğinde 300/300 birebir geri dönüyor.
- **Eşit zaman damgası:** iki sırada da aynı sonuç (11,40).
- **Gelecek tarihli log:** `now`'da işlenmiyor, zamanı gelince işleniyor.
- **30 dk kapısı:** 1799 sn sonraki D sayılmıyor; 1800 ve 1801 sn sonraki sayılıyor (hard, 56,05).
- **Göç:**
  - `baseAt`'ten sonra tarihli geç log işleniyor; önce tarihli olan yok sayılıyor (belgenin kabul ettiği pencere).
  - İki cihaz farklı anda göç edip taban çakışırsa iki makul sonuç çıkıyor (`>` ile 38,45 / 37,76).
  - Alan karışması durumu O1'de.
- **Tahminciler:** 0/500. **Yalnız tanıma %90:** 0/500 (tasarım gereği).
- **04:00:** 23:58/00:02 aynı gün; 03:58/04:02 farklı gün.
- **30 gün ara:** dönüşte doğru S 95–131; yanlış 14, ertesi gün 16.
- **Sezgi senaryoları (v6/v7 ile aynı):**
  - Doğrudan 2 saat sonra yanlış → 11,40, "Yarın" (şikâyet çözülüyor).
  - Yanlış + tanıma doğruları → 11,40.
  - D, D, Y → 56,05.
  - Yeni kelime: yanlış → yeniden sorma doğru → ertesi gün doğru: 2,82 → 6,92.
- **Desenler v7 ile aynı:**
  - %90 bilen, vade günü 1–10 oyun: 486–499/500, medyan 15–25. gün.
  - %70 bilen, vade günü 1 oyun: 446/500.

---

# Ek: ham çıktı

## A) Senaryolar


#### Yeni kelime ilk doğru (hard)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g0 09:00 hard/recall | 1.20 | 6.000 | +0.99 (Yarın) | — | g0 04:00 | — | False | %98 | ✓ |

#### Yeni kelime ilk doğru (good)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g0 09:00 good/recall | 3.00 | 5.000 | +2.79 (3 gün sonra) | — | g0 04:00 | — | False | %99 | ✓ |

#### Yeni kelime ilk doğru (easy)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g0 09:00 easy/recall | 8.00 | 3.500 | +7.79 (8 gün sonra) | — | g0 04:00 | — | False | %99 | ✓ |

#### Yeni kelime: yanlış → 5 dk sonra yeniden sorma doğru → ertesi gün doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g0 09:00 again/recall | 0.40 | 7.000 | +0.79 (Yarın) | g0 04:00 | g0 04:00 | — | False | %50 | ✗ |
| g0 09:05 good/recall | 0.40 | 7.000 | +0.79 (Yarın) | g0 04:00 | g0 04:00 | — | False | %50 | ✗ |
| g1 09:00 good/recall | 2.82 | 6.700 | +2.61 (2 gün sonra) | — | g1 04:00 | — | False | %99 | ✓ |

#### S=30: doğru → 2 saat sonra yanlış (şikâyet)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 good/recall | 82.09 | 5.000 | +81.89 (82 gün sonra) | — | g30 04:00 | g30 04:00 | False | %99 | ✓ |
| g30 10:55 again/recall | 11.40 | 5.850 | +0.71 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: doğru → 5 dk sonra "Bir Tur Daha"da yanlış

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 good/recall | 82.09 | 5.000 | +81.89 (82 gün sonra) | — | g30 04:00 | g30 04:00 | False | %99 | ✓ |
| g30 09:05 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: yanlış → 10 ve 20 dk sonra doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:10 good/letters | 11.40 | 5.850 | +0.78 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:20 good/recall | 11.40 | 5.850 | +0.78 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: yanlış → 29. ve 45. dakikada doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:29 good/letters | 11.40 | 5.850 | +0.77 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:45 good/recall | 11.40 | 5.850 | +0.76 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: yanlış → 30. ve 45. dakikada doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:30 good/letters | 11.40 | 5.850 | +0.77 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:45 good/recall | 56.05 | 5.340 | +55.81 (56 gün sonra) | — | g30 04:00 | g30 04:00 | False | %99 | ✓ |

#### S=30: yanlış → 31. ve 45. dakikada doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:31 good/letters | 11.40 | 5.850 | +0.77 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:45 good/recall | 56.05 | 5.340 | +55.81 (56 gün sonra) | — | g30 04:00 | g30 04:00 | False | %99 | ✓ |

#### S=30: yanlış → 10 dk sonra 3 tanıma doğrusu

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:10 good/recog | 11.40 | 5.850 | +0.78 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:11 good/recog | 11.40 | 5.850 | +0.78 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 09:12 good/recog | 11.40 | 5.850 | +0.78 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: yanlış → 2 saat sonra 2 tanıma doğrusu (widget)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 10:55 good/recog | 11.40 | 5.850 | +0.71 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g30 12:50 good/recog | 11.40 | 5.850 | +0.63 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### S=30: sabah widget ×2 doğru (tek gün)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 good/recog | 30.00 | 5.000 | +0.00 (Bugün) | — | g0 09:00 | g30 04:00 | True | %90 | ✓ |
| g30 12:36 good/recog | 30.00 | 5.000 | -0.15 (Bugün) | — | g0 09:00 | g30 04:00 | True | %89 | ✓ |

#### S=10: sabah widget ×2 doğru (S<21)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g10 09:00 good/recog | 20.90 | 5.000 | +10.90 (11 gün sonra) | — | g0 09:00 | — | False | %94 | ✓ |
| g10 12:36 good/recog | 20.90 | 5.000 | +10.75 (11 gün sonra) | — | g0 09:00 | — | False | %94 | ✓ |

#### S=10: widget sabah, hatırlama akşam

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g10 09:00 good/recog | 20.90 | 5.000 | +10.90 (11 gün sonra) | — | g0 09:00 | — | False | %94 | ✓ |
| g10 20:00 good/recall | 31.63 | 5.000 | +30.97 (31 gün sonra) | — | g10 04:00 | g10 04:00 | False | %99 | ✓ |

#### S=10: hatırlama akşam, widget sonra

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g10 20:00 good/recall | 31.63 | 5.000 | +30.97 (31 gün sonra) | — | g10 04:00 | g10 04:00 | False | %99 | ✓ |
| g10 21:00 good/recog | 31.63 | 5.000 | +30.92 (31 gün sonra) | — | g10 04:00 | g10 04:00 | False | %99 | ✓ |

#### Zayıf kelime: tanıma 1. ve 2. gün

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g31 09:00 good/recog | 12.59 | 5.723 | -0.21 (Bugün) | g30 04:00 | g30 04:00 | — | True | %50 | ✓ |
| g32 09:00 good/recog | 14.95 | 5.614 | +12.75 (12 gün sonra) | — | g30 04:00 | — | False | %98 | ✓ |

#### 3 gün üst üste yanlış, sonra doğrular

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 09:00 again/recall | 11.40 | 5.850 | +0.79 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g31 09:00 again/recall | 5.70 | 6.572 | +0.79 (Yarın) | g31 04:00 | g31 04:00 | — | False | %50 | ✗ |
| g32 09:00 again/recall | 2.85 | 7.187 | +0.79 (Yarın) | g32 04:00 | g32 04:00 | — | False | %50 | ✗ |
| g33 09:00 good/recall | 4.73 | 6.859 | +4.52 (4 gün sonra) | — | g33 04:00 | — | False | %99 | ✓ |
| g34 09:00 good/recall | 6.60 | 6.580 | +6.40 (6 gün sonra) | — | g34 04:00 | — | False | %99 | ✓ |
| g35 09:00 good/recall | 8.49 | 6.343 | +8.28 (8 gün sonra) | — | g35 04:00 | — | False | %99 | ✓ |

#### 03:58 yanlış, 04:02 doğru

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g31 03:58 again/recall | 11.40 | 5.850 | +0.00 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g31 04:02 good/recall | 13.38 | 5.723 | +13.38 (13 gün sonra) | — | g31 04:00 | — | False | %99 | ✓ |

#### 23:58 yanlış, 00:02 doğru (4 dk, aynı gün)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 23:58 again/recall | 11.40 | 5.850 | +0.17 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g31 00:02 good/recall | 11.40 | 5.850 | +0.17 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

#### 23:00 yanlış, 01:00 doğru (aynı gün, 2 saat)

| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |
|---|---|---|---|---|---|---|---|---|---|
| g30 23:00 again/recall | 11.40 | 5.850 | +0.21 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |
| g31 01:00 good/recall | 11.40 | 5.850 | +0.12 (Yarın) | g30 04:00 | g30 04:00 | — | False | %50 | ✗ |

## B) Kullanıcı sezgisi senaryoları (gün sonu → ertesi vadesinde bir doğru)

| Senaryo | Gün sonu | Sonraki doğru |
|---|---|---|
| S=30 vadesinde doğru | S 82.09 · D 5.00 · 82 gün sonra · %99 · rozet · learnedAt | g112: S 198.53 · 198 gün sonra |
| S=30 vadesinde yanlış | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Doğru → 2 saat sonra bilerek yanlış | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Yanlış → 5 dk sonra yeniden sorma doğru | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Yanlış → 2 saat sonra başka oyunda doğru | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Yanlış + 2 tanıma doğrusu (2 ve 4 saat sonra) | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Sabah doğru, akşam yanlış | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Sabah yanlış, akşam doğru | S 11.40 · D 5.85 · Öğreniliyor · Yarın · %50 | g31: S 13.38 · 13 gün sonra |
| Üç oyun D, D, Y (2 saat arayla) | S 56.05 · D 5.34 · 56 gün sonra · %99 · rozet · learnedAt | g86: S 137.01 · 137 gün sonra |
| Dün yanlış, bugün doğru | S 13.38 · D 5.72 · 13 gün sonra · %99 | g44: S 36.78 · 36 gün sonra |
| Yeni: yanlış → yeniden sorma doğru → ertesi gün doğru | S 2.82 · D 6.70 · 2 gün sonra · %99 | g3: S 6.92 · 6 gün sonra |
| S=300 vadesinde yanlış | S 51.96 · D 5.85 · Öğreniliyor · Yarın · %50 | g301: S 53.43 · 53 gün sonra |

### §7.1 doğrulaması

| Satır | Belge | Betik |
|---|---|---|
| Yeni ilk Y (hatırlama) | 0,4/7,0/Yarın | S=0.40 D=7.00 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| Yeni ilk Y (tanıma) | 0,3/7,0 | S=0.30 D=7.00 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| Yeni iki turda Y→D (2 saat) | 0,4/7,0/Yarın | S=0.40 D=7.00 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| S=30 D→Y (2 saat) | 11,40/5,85/Yarın | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| S=30 Y→D (2 saat) | 11,40/5,85/Yarın | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| S=30 üç turda 1 Y (Y D D, 2 saat) | 56,05/5,34/+56/Öğrenildi | S=56.05 D=5.34 vade=56 gün sonra lapsed=— learnedAt=g30 Öğrenildi |
| S=30 üç turda 1 Y (D Y D, 2 saat) | 56,05/5,34/+56/Öğrenildi | S=56.05 D=5.34 vade=56 gün sonra lapsed=— learnedAt=g30 Öğrenildi |
| S=30 üç turda 1 Y (D D Y, 2 saat) | 56,05/5,34/+56/Öğrenildi | S=56.05 D=5.34 vade=56 gün sonra lapsed=— learnedAt=g30 Öğrenildi |
| S=30 salt D | 82,09/5,0/+82 | S=82.09 D=5.00 vade=82 gün sonra lapsed=— learnedAt=g30 Öğrenildi |
| S=30 salt Y | 11,40/5,85/Yarın | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| Dün Y bugün D | 13,38/5,72/+13 | S=13.38 D=5.72 vade=13 gün sonra lapsed=— learnedAt=— Olgun |
| 2. gün Y | 5,70/6,57 | S=5.70 D=6.57 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| 3. gün Y | 2,85/7,19 | S=2.85 D=7.19 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| S=300 Y | 51,96/5,85 | S=51.96 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| …ertesi gün D | 53,43/5,72/+53 | S=53.43 D=5.72 vade=53 gün sonra lapsed=— learnedAt=g301 Öğrenildi |
| Tanıma S=10 | 20,90/5,0/+21 | S=20.90 D=5.00 vade=11 gün sonra lapsed=— learnedAt=— Olgun |
| Zayıf, tanıma 1. gün | büyür/Yarın(sabit)/kalır | S=12.59 D=5.72 vade=Bugün lapsed=eski learnedAt=— Öğreniliyor |
| …2. gün | büyür/ileri/temizlenir | S=14.95 D=5.61 vade=12 gün sonra lapsed=— learnedAt=— Olgun |
| 23:58 Y / 00:02 D | 11,40/Yarın | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| 03:58 Y / 04:02 D | 13,38/+13/temizlenir | S=13.38 D=5.72 vade=13 gün sonra lapsed=— learnedAt=— Olgun |
| **Yeni satırlar** | | |
| D, 2 saat sonra Y | again 11,40 Öğreniliyor·Yarın | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| Y, 10 dk içinde 2 D | again 11,40 | S=11.40 D=5.85 vade=Yarın lapsed=bugün learnedAt=— Öğreniliyor |
| Y, 31. ve 45. dk D | hard 56,05 Öğrenildi | S=56.05 D=5.34 vade=56 gün sonra lapsed=— learnedAt=g30 Öğrenildi |
| Olgun (S=30) yalnız tanıma her gün D | S/anchor/vade değişmez; ekran düşer; vade gelince hatırlamaya düşer | 20. gün S=30.00 vade=g30 ekran %92; 40. gün S=30.00 isDue=True ekran %87, vade metni 10 gün gecikti |
| Olgun (S≥21) zayıf, 2 farklı günde tanıma D | temizlenmez / "Yarın" (sabit) | S=51.96 D=5.85 vade=1 gün gecikti lapsed=eski learnedAt=— Öğreniliyor |
| Tanımada şansla doğru S=10 (v8 metni) | 20,90 / "11 gün sonra" | S=20.90 D=5.00 vade=11 gün sonra lapsed=— learnedAt=— Olgun |
| Zayıf kelime tanımada D | vade değişmez (lapsedAt+1) | vade g31 g31 04:00, isDue(g31 09:01)=True |
| İki cihaz: A Y, B (A'yı görmeden) D, D; sonra eşitleme | eşitleme sonrası hard 56,05 | B eşitleme öncesi: S=82.09 (good); eşitleme sonrası replay: S=56.05 (hard) |
| Log silme (geri alma) | silmeden önceki duruma birebir döner | birebir (S 82.09, learnedAt var) |

## H) v8 özel testleri

**v7-Y1 — son log iki kez sayılıyor muydu?** (v8: `>` ve baseAt=max(son log, lastReviewedAt))

- Zayıf eski kelime (S=11,40, son log g100 09:00 Y, göç 18:00): S 11.40, "Öğreniliyor · Bugün", isDue True; ertesi gün D → S 13.34, "13 gün sonra"
- Son günü D, D, Y olan eski kelime (eski S=20): göç sonrası S 20.00, D 6.00
- Son log hard: S 20.00, D 6.00 (taban 6,00)

**v7-O1 — eski sürümde Word kaydı logdan önce eşitlenmişse**:
- (a) A'nın g30 10:00 yanlışı günün ilk cevabı (eski kod lastReviewedAt=10:00 yazar): baseAt g30 10:00; A'nın logu gelince S 11.40 (taban 11,40) → çift sayım **yok** ✓
- (b) A'nın g30 20:00 yanlışı günün 2. cevabı (eski kod lastReviewedAt'i 09:00'da bırakır, yalnızca vadeyi geçmişe atar): baseAt g30 09:00, taban zayıf; A'nın 20:00 logu gelince yeniden işlenir → S 41.05 (taban 82,09; eski motor yanlışta S'yi değiştirmemişti) → yanlış ilk kez S'ye işleniyor, ama "zaten zayıf" sayıldığı için ×0,5 (ilk zayıflama olsaydı 28.73/tavan 27.18)

**Yeni kelime (reviewCount == 0 → baseAt = distantPast)**:
- Hiç cevaplanmamış kelime: baseAt distantPast; ilk yanlış + ertesi gün doğru → S 2.82 (sıfırdan: 0,40 → 2,82 beklenir)
- İki cihaz, A kelimeyi reviewCount=0 görüp distantPast yazar, B tam taban yazar. g48 doğrudan sonra: B kazanırsa S 93.52; A kazanırsa (bütün eski loglar yeni motorla baştan) S 73.38; **alanlar karışırsa** (baseAt=distantPast + B'nin base S=34,5) S 98.09 — eski loglar tabanın üstüne ikinci kez işlenir.

**Yeni kural: S≥21 zayıf kelimede tanıma zayıflığı kaldırmaz**
- g300 09:00 again/recall: S 51.96, zayıf True, vade g301 04:00, isDue False, "Öğreniliyor · Yarın", ekran %50
- g301 09:00 good/recog: S 51.96, zayıf True, vade g301 04:00, isDue True, "Öğreniliyor · Bugün", ekran %50
- g302 09:00 good/recog: S 51.96, zayıf True, vade g301 04:00, isDue True, "Öğreniliyor · 1 gün gecikti", ekran %50
- g303 09:00 good/recog: S 51.96, zayıf True, vade g301 04:00, isDue True, "Öğreniliyor · 2 gün gecikti", ekran %50
- g303 20:00 hatırlama D: S 56.36, zayıf False, "56 gün sonra"
- Karşılaştırma S<21 (S=30 → 11,40): 2 tanıma gününden sonra zayıf False, S 14.95
- Yalnız widget (%90), başlangıç S=30, 180 gün: sonunda zayıf 22/300 (bunların S≥21 olup tanımayla asla kurtulamayanı 0); S medyanı 20.9
- Yalnız widget (%90), başlangıç S=100, 180 gün: sonunda zayıf 29/300 (bunların S≥21 olup tanımayla asla kurtulamayanı 1); S medyanı 20.4
- Yalnız widget (%90), başlangıç S=300, 180 gün: sonunda zayıf 0/300 (bunların S≥21 olup tanımayla asla kurtulamayanı 0); S medyanı 300.0

## E) Ek kontroller

- **(a) Sıra/iki cihaz** (300 rastgele 8 günlük log kümesi, günde 1–7 cevap 2–120 dk arayla, karışık mod/not): karıştırılmış sırayla replay = referans **300/300**; artımlı önbellek (cevap cevap) = tam replay **300/300**; iki cihaz tam eşitleme sonrası aynı **300/300**; eşitleme gecikmesi sürerken B'nin gördüğü sonuç farklı: 170/300 (geçici).
- **(b) Geri alma = log silme**: son logu silmek, o log hiç yazılmamış hâle birebir döndü (300/300); rastgele bir ara logu silmek tanım gereği tutarlı. Örnek: D (S 82.09, learnedAt g30) → Y (S 11.40, learnedAt yok) → Y geri alındı (S 82.09, learnedAt g30) — birebir.
  Not: önbellekte (Word) tutulan eski "geri alma listesi" gerekmez; ama `replay` her geri almada bütün logları okur (tek kelime, ucuz).

## E2) Eşit zaman damgası ve gelecek tarihli log

- Aynı saniyede D ve Y (iki sırada): S 11.40 / 11.40 — aynı (yanlış önce sıralanır → doğru 0 sn sonra, kapı içinde, sayılmaz → again)
- Gelecek tarihli log (cihaz saati 4 gün ileri): now anında yok sayıldı → S 82.09; 5 gün sonra işlenir.
- Y, 1799 sn sonra D, 45. dk D → again, S 11.40
- Y, 1800 sn sonra D, 45. dk D → hard, S 56.05
- Y, 1801 sn sonra D, 45. dk D → hard, S 56.05

## F) Göç senaryoları (v7)

**(1) baseAt = son log tarihi; `>=` ile o log yeniden işleniyor mu?** Eski motorda son gün (g50) üç cevap: D 09:00, D 11:00, Y 13:00; eski önbellek S=20 (eski motorun sonucu), zayıf (hile). Göç g50 20:00.

| Varsayım | göç sonrası S | lapsedAt | not |
|---|---|---|---|
| ge | 10.00 | g50 | son log (Y) tek başına yeniden işlendi: zaten zayıf → S×0,5 |
| gt | 20.00 | g50 | taban aynen korunur |
| ge, son log hard | S 20.00 D 6.19 | — | D yeniden +0,4 (çift sayım) |
| gt, son log hard | S 20.00 D 6.00 | — | taban |

**(2) Göç anında eşitlenmemiş log** (S=30 olgun, son yerel log g30 09:00; göç g31 20:00):
- baseAt'ten SONRA tarihli geç log (g31 Y): işlendi → S 10.53, zayıf True ✓
- baseAt'ten ÖNCE tarihli geç log (g29 Y): yok sayıldı → S 30.00, zayıf False (belgenin kabul ettiği dar pencere)

**(2b) Eski sürümde Word kaydı, logundan ÖNCE eşitlenmişse** (A cihazı g30 10:00 yanlış yaptı; A'nın Word kaydı B'ye ulaştı, logu ulaşmadı; B'nin son logu g30 09:00; B g30 20:00'de göç eder):
- A'nın logu gelince: S 11,40 (taban, yanlışı zaten içeriyor) → 5.70 (yanlış **ikinci kez** işlendi, "zaten zayıf" ×0,5).

**(3) İki cihaz farklı anda göç; taban çakışması** (eski sürümde A: g10 D, g20 D; B: g25 Y — B'nin logu A'ya göç anında ulaşmamış):
- A kazanır (baseAt g20): g40 doğrudan sonra S 38.45 (`>`), 38.45 (`>=`); learnedAt g20
- B kazanır (baseAt g25): g40 doğrudan sonra S 37.76 (`>`), 29.04 (`>=`); learnedAt yok
  Not: A tabanı kazanırsa B'nin g25 yanlışı baseAt'ten SONRA olduğu için işlenir (kayıp yok); B kazanırsa A'nın geçmişi tabanda. İki sonuç farklı ama ikisi de makul; §6 "birleştirmede eski baseAt kazanır" kuralı CloudKit'in kendi çakışma çözümünde uygulanamaz (son yazan kazanır).


## C) v6 bulgularının v7 testleri

**v6-Y1 — widget kilidi (S<21)**, 500 tohum, 120 gün:

| Widget / hatırlama | widget seçimi | Öğrenildi | learnedAt medyan günü (ulaşan) | hatırlama sorulan gün (medyan) | son S medyanı |
|---|---|---|---|---|---|
| %100 / %90 | yalnız isDue | **499**/500 | g21 (500) | 3 | 150.8 |
| %100 / %90 | her sabah | **496**/500 | g21 (500) | 3 | 150.8 |
| %90 / %90 | yalnız isDue | **483**/500 | g21 (500) | 4 | 134.4 |
| %90 / %90 | her sabah | **37**/500 | g50 (346) | 14 | 20.9 |
| %90 / %70 | yalnız isDue | **434**/500 | g25 (497) | 6 | 89.2 |
| %90 / %70 | her sabah | **32**/500 | g53 (293) | 17 | 20.9 |
| %90 / %30 | yalnız isDue | **135**/500 | g46 (251) | 44 | 5.7 |
| %90 / %30 | her sabah | **13**/500 | g62 (132) | 34 | 7.5 |
| %100 / %0 | yalnız isDue | **0**/500 | g— (0) | 120 | 0.3 |
| %100 / %0 | her sabah | **0**/500 | g— (0) | 120 | 0.3 |

Yalnız widget (Günlük Tekrar hiç açılmıyor), %100: Öğrenildi 0/500, son S medyanı 20.9, widget cevap sayısı medyanı 103, zayıf gün medyanı 0

Yalnız widget (Günlük Tekrar hiç açılmıyor), %90: Öğrenildi 0/500, son S medyanı 20.4, widget cevap sayısı medyanı 50, zayıf gün medyanı 9

İz (%100 widget, isDue; akşam isDue ise hatırlama doğru): g3:S8.0/vade g7 · g8:S18.8/vade g18 · g19:S20.9/vade g20 · g21:S20.9/vade g20 · g21 akşam hatırlama → S60.1/vade g81

**v6-Y2 — göç çıpası**: S=30 kelime, son tekrar g0 09:00 (log), vade g30; göç g60 12:00; g60 18:00 hatırlama doğru:

| baseAt karşılaştırması | S sonra | beklenen |
|---|---|---|
| ge | 125.46 | 125.46 |
| gt | 125.46 | 125.46 |

**v6-Y3 — learnedAt göçte korunuyor mu**: S=60, eski learnedAt g20, son tekrar g30 (log), vade g90; göç g40:
göç sonrası learnedAt g20; ilk tekrar sonrası g20; yanlış+toparlanma sonrası g20 → "Bu Hafta" sayımına **girmiyor**.
200 öğrenilmiş eski kelime, göçten sonra 14 gün çalışma: learnedAt'i göç sonrasına kayan kelime **0**.

**v6-O1 — zayıf göç kelimesi metni**: eski S=11,4, g100 09:00 yanlış (log), eski hileli vade g91; göç g100 18:00:
- baseAt ge: göç anında metin "Öğreniliyor · Yarın", isDue False, S 5.70 (eski önbellek 11,40), vade g101 04:00; ertesi gün doğru → S 7.60, "7 gün sonra"
- baseAt gt: göç anında metin "Öğreniliyor · Bugün", isDue True, S 11.40 (eski önbellek 11,40), vade g100 18:00; ertesi gün doğru → S 13.34, "13 gün sonra"

**v6-O2 — günde 2 cevap** (açık karar, v7'de değişmedi): aşağıdaki desen tablosunda %90 her gün 1/2/3 oyun.

## D) Desenler (500 tohum, 120 gün)

| Kullanıcı | Öğrenildi (canlı, 120. gün) | learnedAt medyan günü (ulaşan) | zayıf gün medyanı |
|---|---|---|---|
| %90 bilen, vade günü 1 oyun | **495**/500 | g15 (500) | 0 |
| %90 bilen, vade günü 2 oyun | **486**/500 | g15 (500) | 1 |
| %90 bilen, vade günü 3 oyun | **498**/500 | g15 (500) | 0 |
| %90 bilen, vade günü 5 oyun | **492**/500 | g15 (500) | 0 |
| %90 bilen, vade günü 10 oyun | **499**/500 | g25 (500) | 0 |
| %90 bilen, her gün 1 oyun | **241**/500 | g12 (500) | 12 |
| %90 bilen, her gün 2 oyun | **102**/500 | g23 (493) | 23 |
| %90 bilen, her gün 3 oyun | **366**/500 | g11 (500) | 6 |
| %90 bilen, her gün 5 oyun | **250**/500 | g16 (500) | 10 |
| %90 bilen, her gün 10 oyun | **405**/500 | g17 (500) | 3 |
| %70 bilen, vade günü 1 oyun | **446**/500 | g21 (497) | 2 |
| %70 bilen, vade günü 2 oyun | **283**/500 | g37 (416) | 10 |
| %70 bilen, vade günü 3 oyun | **359**/500 | g36 (468) | 4 |
| %70 bilen, vade günü 5 oyun | **189**/500 | g60 (268) | 15 |
| %70 bilen, vade günü 10 oyun | **66**/500 | g64 (101) | 34 |
| %70 bilen, her gün 1 oyun | **11**/500 | g45 (308) | 36 |
| %70 bilen, her gün 2 oyun | **0**/500 | g70 (6) | 61 |
| %70 bilen, her gün 3 oyun | **1**/500 | g50 (36) | 42 |
| %70 bilen, her gün 5 oyun | **0**/500 | g16 (2) | 56 |
| %70 bilen, her gün 10 oyun | **0**/500 | g— (0) | 63 |
| yalnız tanıma, tahminci %25 | **0**/500 | g— (0) | 113 |
| yalnız tanıma, %90 | **0**/500 | g— (0) | 10 |
| tahminci: 2 tanıma %25 + hatırlama %5, her gün | **0**/500 | g— (0) | 114 |

**Widget her sabah + vadesi gelince akşam Günlük Tekrar**

| Widget / hatırlama | widget seçimi | Öğrenildi | learnedAt medyan günü | hatırlama sorulan gün (medyan) | son gün S medyanı |
|---|---|---|---|---|---|
| %100 / %90 | her sabah (vadeye bakmadan) | **496**/500 | g21 (500) | 3 | 150.8 |
| %100 / %90 | yalnız isDue | **499**/500 | g21 (500) | 3 | 150.8 |
| %90 / %90 | her sabah (vadeye bakmadan) | **37**/500 | g50 (346) | 14 | 20.9 |
| %90 / %90 | yalnız isDue | **483**/500 | g21 (500) | 4 | 134.4 |
| %90 / %70 | her sabah (vadeye bakmadan) | **32**/500 | g53 (293) | 17 | 20.9 |
| %90 / %70 | yalnız isDue | **434**/500 | g25 (497) | 6 | 89.2 |
| %90 / %30 | her sabah (vadeye bakmadan) | **13**/500 | g62 (132) | 34 | 7.5 |
| %90 / %30 | yalnız isDue | **135**/500 | g46 (251) | 44 | 5.7 |

**30 gün ara**
- ara 20–50, dönüş doğru: dönüş günü S 95.1, ertesi gün 95.1, 119. gün 95.1
- ara 20–50, dönüş yanlış: dönüş günü S 13.8, ertesi gün 15.7, 119. gün 107.1
- ara 20–75, dönüş doğru: dönüş günü S 131.0, ertesi gün 131.0, 119. gün 131.0
- ara 20–75, dönüş yanlış: dönüş günü S 14.4, ertesi gün 16.3, 119. gün 45.5
