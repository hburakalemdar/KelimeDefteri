Yeterli materyal toplandı. Bu subagent'ın dosya yazma aracı yok, bu yüzden raporu doğrudan yanıt olarak veriyorum (ana ajan dosyaya kendisi kaydedebilir).

S1 — Tur içi hata tekrarı, tur bitişi, ilerleme çubuğu
- Duolingo derste hata yapılan öğeyi hemen değil, dersin sonunda tekrar sorar: "At the end of a lesson, you'll review any mistakes you made. We wait until the end of the lesson to take advantage of a little spaced repetition!" [1]
- Duolingo'nun kişiselleştirilmiş pratik derslerinde hangi kelime/gramerin tekrar edileceği aralıklı tekrar + doğruluk oranıyla seçiliyor (dolaylı) [1]
- Anki öğrenme adımlarında (learning steps) yanlış cevap kartı baştaki adıma resetler; ör. adımlar "1m 10m" ise "Again" basılan yeni kart 1 dakika sonra tekrar gelir, doğru cevaplanana kadar o ilk adımda döngüye girer, doğru cevaplanınca bir sonraki adıma geçer [2]
- Quizlet Learn'de her kart "henüz öğrenilmedi" ile başlar, bir doğru cevaptan sonra "tanıdık", iki veya daha fazla doğru cevaptan sonra "ustalaşıldı" olur; henüz öğrenilmemiş/tanıdık kartlar turda mastered kartlardan daha sık tekrar eder [3]
- Quizlet turları 7 sorudan oluşur, en düşük Leitner kutusundaki terimler önce sorulur; kutu, soru tipini belirler: yeni terimde çoktan seçmeli, oturmaya başlayınca yazarak hatırlama, kutu 4'te "mastered" [3]
- Her Quizlet oturumu, önceki oturumun saklı durumundan değil, o anki canlı cevaplardan destenin yeniden sıralandığı bir "placement" turuyla açılır (dolaylı) [3]
- Duolingo tur içi ilerleme çubuğu: kullanıcı forumlarında ilerleme çubuğunun bazen geri gittiği bildiriliyor, ancak bu resmi kaynakta bilinen bir hata (bug) olarak ele alınıyor, tasarım kararı olarak değil (dolaylı, kaynak topluluk/wiki, resmi değil) [4]

Bulunamayanlar
- Memrise oturum "rounds" yapısının resmi/güncel açıklaması (aranan: Memrise session rounds structure repeat mistakes)
- Duolingo'da tur içinde bir hatanın kaç kez/hangi aralıkla tekrar sorulduğuna dair tam sayısal kural (yalnızca "ders sonunda" bilgisi doğrulandı)

S2 — Tur sonu ekranı, yüzde/olasılık, önce→sonra, cezalandırıcı olmama
- Anki'de "Again/Hard/Good/Easy" düğmeleri her birinin bir sonraki aralığını (dakika/gün) gösterir; ör. "Again" 10 dakika sonra, "Good" 1 gün sonra gösterir, tekrar "Good" ile 3 güne çıkar [5]
- Bu tasarımın kafa karıştırıcı yanı: yeni kullanıcılar süre etiketinin "kolaylık algısıyla" arttığını beklemiyor — kısa aralığı "iyi", uzun aralığı "kötü" sanabiliyorlar [5]
- Cezalandırıcı geri bildirim: sadece kırmızı X yerine, doğru cevabı bağlamıyla gösteren, tam hatayı vurgulayan, kısa açıklama içeren ve aynı örüntüyü sonraki bir alıştırmada tekrar eden geri bildirim daha faydalı görülüyor [6]
- Ceza temelli (can/heart) sistemlerin erken bırakma oranıyla ilişkili olduğu, sınırsız pratik modellerinin motive kullanıcıyı daha uzun tuttuğu belirtiliyor (dolaylı, pazar analizi) [6]
- Kırmızı aşırı kullanıldığında stres, kafa karışıklığı ve bilişsel yükü artırıyor; ikon/boşluk/ince çerçeve gibi görsel ipuçları kırmızı olmadan da mesajı destekleyebiliyor [6]
- WaniKani'de bir madde doğru cevaplanınca SRS aşaması bir basamak yukarı çıkıyor, yanlış cevaplanınca ilerlemeye ne kadar gidildiğine, madde tipine (radikal/kanji/kelime) ve kaç kez yanlış cevaplandığına bağlı olarak bir veya daha fazla basamak aşağı iniyor [7]
- WaniKani inceleme oturumunda her madde bitince yeni SRS seviyesini gösteren bir popover çıkıyor, genelde yalnızca geniş kategoriyi (Apprentice/Guru gibi) gösteriyor, daha ayrıntılı değil [7]
- Kullanıcılar eski "Session Review" özet sayfasının (oturum sonunda hangi maddelerin tekrar gözden geçirilmek istendiğini gösteren) kaldırılmasını eksik buluyor — bu bir topluluk şikayeti, WaniKani'nin resmi duruşu değil [7]

Bulunamayanlar
- WaniKani/Anki/Quizlet'in "yüzde/olasılık göstermek kafa karıştırıyor" konusunda doğrudan resmi/araştırma kaynağı bulunamadı, yalnızca dolaylı UX genel prensipleri bulundu (aranan: percentage probability confusing spaced repetition mastery display research)
- Duolingo ders sonu ekranının somut bileşenleri (XP, doğruluk yüzdesi vb.) için resmi kaynak doğrulanamadı

S3 — Çeldirici seçimi, küçük koleksiyon
- Çoktan seçmeli kelime sorularında çeldiricilerin hedef kelimeyle aynı sözcük türünde (part of speech) olması temel kural [8]
- Ek ilkeler: çeldiricilerin zorluk seviyesi doğru cevaba yakın olmalı, seçenekler yaklaşık aynı uzunlukta olmalı, seçenekler arasında eş anlamlı çift bulunmamalı, doğru cevabın zıt anlamlısı çeldirici olarak kullanılmamalı [8]
- Otomatik çeldirici üretiminde kaynaklar: (a) okuma parçasındaki, hedef kelimeyle aynı sözcük türü ve zamanda olan eş anlamlılar (aynı konuyu paylaştığı varsayımıyla), (b) WordNet taksonomisinde hedef kelimenin "kardeşleri" (aynı üst kavramı paylaştığı için anlamca yakın ama farklı) [8]
- Küçük deste/az kart sayısında spesifik ürün davranışı (ör. Quizlet/Anki'nin 4-10 kartlık destede çeldirici nasıl ürettiği) için doğrudan kaynak bulunamadı

Bulunamayanlar
- Küçük koleksiyonda (4-10 kelime) ticari uygulamaların (Duolingo, Quizlet, Memrise) somut davranışı — "yeterli çeldirici yok" durumunda ne yaptıkları (aranan: small vocabulary deck insufficient distractors app behavior, Quizlet minimum terms multiple choice)

S4 — Yazarak cevaplama toleransı
- Duolingo, öğrenci cevabını büyük bir kabul edilebilir cevap kümesindeki en yakın referans cevapla, token düzeyinde Levenshtein (düzenleme) mesafesiyle karşılaştırıyor; büyük/küçük harf, noktalama ve aksan farkları yok sayılıyor [9]
- Levenshtein mesafesi küçükse (string uzunluğuna göre) sistem yüksek puan veriyor (ör. 1.0 üzerinden 0.9), yazım hatasına rağmen "fonksiyonel olarak doğru" kabul ediliyor [9]
- Anki'nin "type in the answer" kart tipinde yerleşik yazım toleransı yok: yazılan metin tek bir hedef alanla tam (exact) karşılaştırılıyor; sistem farkı gösteriyor ama doğru/yanlış kararını (review rating) kullanıcı kendisi veriyor, otomatik puanlamıyor [10]

Bulunamayanlar
- "Birden çok kabul edilebilir Türkçe/İngilizce anlam" durumunda somut ürün örneği (aranan: multiple acceptable translations vocabulary app scoring)

S5 — Aynı gün tekrar oynama, massed practice
- Genel bilişsel araştırma (spacing effect): öğrenciler bir liste içindeki öğeleri kısa sürede yoğun tekrarlamaktansa, zaman içine yayılmış birkaç oturumda çalıştıklarında daha etkili öğreniyor [11]
- Massed practice (az sayıda, uzun oturum) genelde daha az etkili bir öğrenme yöntemi olarak görülüyor; spacing, massing'den daha fazla öğrenme sağlıyor [11]
- Bir oturumda bilgiyle tekrar tekrar karşılaşmak hızla "bilme yanılsaması" (illusion of knowing) yaratıyor; hızlı öğrenilen bilgi genelde hızlı unutuluyor [11]
- Anlık tekrar bilgiyi kısa süre (birkaç saniye/dakika) hatırlamaya yardım ediyor ama bir gün/hafta sonra hatırlamayı zorlaştırabiliyor [11]

Bulunamayanlar
- "Bir tur daha" tuşuna basıldığında aynı gün içinde spesifik olarak ticari bir uygulamanın (Duolingo/Anki/Quizlet) ne yaptığına dair doğrudan kaynak (aranan: Duolingo Anki same day replay second session design)

Kaynaklar
[1] https://blog.duolingo.com/spaced-repetition-for-learning/ · kurum (resmi blog)
[2] https://forums.ankiweb.net/t/how-can-i-make-anki-show-a-card-the-next-day-after-pressing-again-twice-deeper-recall-after-repeated-failures/62678 · forum
[3] https://quizlet.com/blog/introducing-the-new-quizlet-learn · kurum (resmi blog)
[4] https://duolingo.fandom.com/f/p/4400000000000174297 · blog/forum (wiki, resmi değil)
[5] https://github.com/ankidroid/Anki-Android/issues/11675 · resmi (proje deposu, geliştirici tartışması)
[6] https://www.psd-dude.com/tutorials/resources/user-interface-design.aspx · blog
[7] https://knowledge.wanikani.com/wanikani/srs-stages/ ve https://community.wanikani.com/t/already-missing-the-session-review-summary-page/61068 · kurum (resmi bilgi bankası) / forum
[8] https://link.springer.com/article/10.1186/s41039-018-0082-z · hakemli (Research and Practice in Technology Enhanced Learning)
[9] https://research.duolingo.com/papers/settles.slam18.pdf · resmi (araştırma yayını)
[10] https://forums.ankiweb.net/t/type-in-the-answer/17035 · forum
[11] https://en.wikipedia.org/wiki/Distributed_practice ve https://www.learningscientists.org/blog/2023/11/16 · kurum/blog