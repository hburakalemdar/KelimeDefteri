# Görev devri: yeni anlam öğretme (2026-09-26)

**BİTTİ (2026-09-26):** 9d8a60f + örnek veri; tasarım ve uygulama notları docs/SPEC-ANLAM.md.

## Durum
Bu oturumda bitti, commit + push edildi, iPhone 14 ve Mac'e kuruldu (321 test geçiyor):
- 08a625e yeniden eklemede cümle kaybı · d26b013 widget bugün cevaplananı atlar + anlamlar sırayla (`Word.meaningTurn` = logs.count, `ChoiceQuiz.meaning`)
- ba96005 + 520e542 Günlük Tekrar'da oyunlar (DailyMix, StudySession adımları, SPEC-OYUN §5.11)
- 2aec72d çok cümle modeli (`WordSentence`, SPEC-CUMLE.md)
- Mac ekranları ana oturumda -demo ile görsel kontrol edildi, sorun yok.

## Sıradaki iş: yeni anlam öğretme
Sorun: çalışılmış kelimeye yeni anlam eklenince (Anlamları Ekle / düzenleme formu) o anlam kelimenin eski hafıza
yüzdesini devralıyor; ReviewLog'da anlam kimliği yok. Güçlü kelimede yeni anlam haftalarca sorulmayabilir.

Okunacaklar: docs/PLAN-CUMLE-OYUN.md (İŞ 4 "Açık sorun" seçenekleri + Codex değerlendirmesindeki itirazlar),
docs/SPEC-CUMLE.md, docs/SPEC-OYUN.md §5.11, Shared/Logic/DailyMix.swift, StudySession.swift, ChoiceQuiz.swift.

Codex'in reddettiği/uyarıları (tasarım bunları karşılamalı):
- `newMeanings: String` alanı iki cihazda çakışır; anlam metni kimlik olamaz (yeniden adlandırma/silme/yazım farkı).
- Tanıtım bütün yazma yollarını kapsamalı (absorb, düzenleme formu, eski istemci).
- Başka anlamla verilen doğru cevap hedef anlamı "öğrenildi" saymamalı; hedef anlam soru → şık → ipucu → log boyunca taşınmalı.
- "5 yeni" bütçesi, kart/rozet/bildirim sayılarıyla birlikte ele alınmalı.

Çalışma şekli (kullanıcı onayladı): kararları kendin ver, önce kısa tasarım belgesi, uygulamayı general-purpose ajana
ver, sonra bağımsız Opus 5.5 incelemesi (Codex değil), bulguları düzelt, test geçince commit + push, cihazlara kur,
Mac görsel kontrolünü ana oturumda yap. Kullanıcı bilgisayar başında olmayabilir; takılma, sonunda sade özet ver.
Ortak ajan kuralları: scratchpad'deki ortak-kurallar.md yerine CLAUDE.md'deki derleme/test komutlarını görev metnine yaz.
