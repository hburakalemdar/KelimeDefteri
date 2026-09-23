# Görev: GELECEK.md 4–6. adımlar (23 Eylül 2026)

Devir notu. Kullanıcı 4 (telefona yayılma), 5 (motivasyon), 6 (Mac uyarlaması) adımlarının hepsini istedi.
Onaylar: widget için yeni App ID (`com.burakalemdar.KelimeDefteri.KelimeWidget`) kaydı ve App Group bağlama;
her parça bitip testler geçince **sormadan** cihazlara kur, commit et, push et. CloudKit şemasını üretime aktarma
ayrı onay ister (dokunma). İş bitince bu dosyayı sil, CALISMA-RAPORU'na bölüm ekle.

## Plan
- **Aşama 1 (paralel worktree ajanları):**
  - W: widget eklentisi (etkileşimli soru widget'ı, kilit ekranı özeti, StandBy, Denetim Merkezi / Eylem düğmesi
    kontrolü → Hızlı Tur), cevaplanabilir bildirim. pbxproj'a yeni hedef.
  - M: günlük hedef halkası, seri, "Öğrenildi" rozeti, haftalık özet (iOS). `KelimeDefteri/Views/Games/*`'a dokunmaz.
- **Aşama 2:** birleştir, kilit ekranı widget'ına halka/seri bağla (gerekirse), kur, commit/push.
- **Aşama 3 (ajan):** Mac: oyunlar menü çubuğu penceresinde (oyunlar Shared'a taşınır, klavye; Eşleştir sürükle-bırak),
  halka/seri Mac'te de. Kur, commit/push.

## Durum
- [x] Aşama 1 W  - [x] Aşama 1 M (main'e birleşti)  - [x] Aşama 2 (49ffc59 push; kilit ekranı halkası ayrı ajan)  - [ ] Aşama 3
- ONAYLANDI, ajan çalışıyor: Paylaş sayfası alt listesine Action Extension "Kelime Defteri'ne Ekle" (yeni App ID com.burakalemdar.KelimeDefteri.KelimeEylem) + panodan ekleme App Intent'i (Arka Dokunma/Eylem düğmesi).
