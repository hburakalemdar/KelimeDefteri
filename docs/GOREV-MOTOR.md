# Görev: hafıza ilerlemesi ve tur içi oyun mantığı yeniden tasarımı (23 Eylül 2026)

Devir notu. Kullanıcı tur özetinde "%99 → Şimdi", "%50 → 8 gün sonra" gibi saçma sonuçlar gördü; "bütün oyun ve modlar
için ilerleme ve tur içi oyun mantığı çok ciddi araştırılıp düşünülsün" dedi. Henüz KOD DEĞİŞİKLİĞİ ONAYI YOK:
önce tasarım belgesi, sonra kullanıcıya sade özet + karar noktaları, onaydan sonra uygulama.

Ön bulgular (ilk analiz): özet satırı üç anı karıştırıyor (✓/✗ ilk cevap, % tur başı, vade son cevap); "%50" lapse sabiti
(vade geçmişe konuyor); motor ile ekran farklı R kullanıyor; bugün eklenen aynı gün koruması (ReviewRecorder) aynı gün
yanlışı ya etkisiz ya "Şimdi" yapıyor, yanlış→doğru eski vadeyi geri getiriyor; hatırlama oyunlarında yanlış ×0.35;
learnedAt aynı gün yanlış→doğruda kayıyor.

## Plan
1. Paralel 4 ajan, raporlar scratchpad/motor/ altına: 1-ilerleme.md (motor denetimi, kod), 2-tur-ici.md (tur içi, kod),
   3-arastirma-motor.md, 4-arastirma-oyun.md (web).
2. sentezci → docs/SPEC-MOTOR2.md (tasarım: motor kuralları, tur içi akış, özet ekranı, göç, testler, karar noktaları).
3. denetleyici → SPEC'i raporlara ve koda karşı denetler; düzeltme.
4. Kullanıcıya sade özet, onay. Sonra uygulama (worktree ajanları), test, iki cihaza kurulum, commit/push (bu işler için
   önceki onay: parça bitince sormadan kur/commit/push).

## Durum
- [x] 1 (4 rapor scratchpad/motor/)  - [x] 2 (docs/SPEC-MOTOR2.md v2)  - [~] 3 (denetim-1 bitti, v2 için denetim-2 + simülasyon 6-simulasyon.md sürüyor)  - [ ] 4
- v3 yönü (denetim-2 + simülasyon sonrası): gün bazlı değerlendirme (gün başı S/D saklanır, günün cevaplarının bütünü
  tek güncelleme; sıra bağımlılığı yok), gün 04:00'te döner, seçim/sayaç vadeye bakar, tanıma iki farklı günde zayıflığı
  kaldırır, learnedAt yalnızca ilk kez. v3 sonrası: simülasyonu v3'e göre yeniden koştur (sim ajanı), gerekirse denetim-3.
- v4 sonrası: denetim (10-denetim-v4.md) 6 Yüksek, simülasyon (9-simulasyon-v4.md) 2 Yüksek; oran kuralı karmaşa üretiyor.
  Simülasyon ajanı V4F (oran + düzeltmeler) ile SADE (günün ilk hatırlama cevabı S/D'yi belirler; sonraki aynı gün yanlış
  yalnızca zayıf + vade yarın) modellerini karşılaştırıyor → 11-karsilastirma.md. Seçilen modelle SPEC v5, sonra denetim.
- V4F seçildi; SPEC v5 yazıldı. v5 için simülasyon (12-simulasyon-v5.md) + denetim sürüyor.
- v5 denetimi (13-denetim-v5.md) yine 5 Yüksek: artımlı alanlar (dayStart*, isPrimary, tanıma lastReviewedAt) birbirinden
  kopuyor. KARAR (yönetici): v6 mimarisi = durum ReviewLog'lardan yeniden oynatılarak hesaplanır (event sourcing):
  Word'deki S/D/due/lapsedAt/learnedAt yalnızca önbellek; taban = geçiş anındaki mevcut değerler (baseAt), sonrası
  loglardan gün gün (04:00) V4F kurallarıyla. Birincil/30 dk/yeniden sorma loglardan hesaplanır, saklanmaz. Geri alma =
  log silme. İki cihaz aynı loglarla aynı sonuç. 12-simulasyon-v5.md bekleniyor, sonra sentezci v6.
- SPEC v6 (replay) yazıldı; simülasyon (14-simulasyon-v6.md, sim_v6.py) + denetim (aa19… → 15-denetim-v6.md olarak kaydet) sürüyor.
- v6: mimari doğrulandı (sıra/iki cihaz/geri alma 300/300). Kalan: tanıma anchor, göç tabanı (baseAt=son log, baseAnchorAt, baseLearnedAt), lapsedAt alanı, tetikleyici. SPEC v7 yazılıyor; sonra son sim + denetim, sonra kullanıcıya §9 soruları.
