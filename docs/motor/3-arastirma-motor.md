Bu yeterli. Şimdi son raporu hazırlayabilirim.

---

**S1 — Tanıma vs hatırlama, testing effect'te tür farkı, guessing sorunu**

- Retrieval practice (kısa cevap, çoktan seçmeli, serbest hatırlama) hepsi tekrar okumaya göre üstün, ancak formatlar arası fark var: "Multiple-choice tests tend to produce smaller testing effects than do cued-recall tests, largely attributed to the different processing that the two formats induce." [1]
- "Production tests are usually in the form of free recall, short-answer essay, and fill-in-the-blank, whereas recognition tests are in the form of multiple-choice questions and 'true or false.'" [1]
- Literatürde net uzlaşı yok: "Some studies reported that tests involving a production task provide greater benefit than a recognition task, whereas other studies reported otherwise." (çelişki, kaynak içinde belirtiliyor) [1]
- İyi tasarlanmış çoktan seçmeli sorular yanlış şıkları da hatırlamayı tetikleyebiliyor, bu da salt tanımadan farklı bir işlem: "multiple-choice questions can be constructed to induce retrieval of information pertaining to the incorrect alternatives" [1] (dolaylı)
- Quizlet Learn: doğru cevapladıkça kolay çoktan seçmeliden zor yazma sorusuna geçiş yapıyor: "as you answer more questions correctly, you advance from easier multiple choice questions to more difficult written questions"; tamamlama koşulu "a user must correctly answer every term in a set twice." [2]
- Quizlet'in gerekçesi: "when you answer written questions from memory... this requires effortful retrieval or 'recall'... Meanwhile, multiple choice questions are designed to get you through more questions in less time, with the added bonus of helping you learn the incorrect answer choices." [2]
- Duolingo HLR modelinde çoktan seçmeli şansla-doğru (guessing) sorununu egzersiz türüne göre ayrı ağırlıklandırdığına dair bir ifade bulunamadı; model `session_seen`/`session_correct` ve `history_seen`/`history_correct` sayaçlarıyla lexeme bazında genel doğruluğu besliyor, format ayrımı dokümanlarda görünmüyor [3][4].
- Genel SRS pratiğinde çoktan seçmeli şans düzeltmesi (guessing correction) için formül/psikometrik yaklaşım aranan sorguda bulunamadı; item response theory tarafına işaret ediliyor ama kaynak verilmiyor.

**S2 — Cevap süresinden otomatik not türetme**

- "Response latency is a strong signal and SM-2 ignores it entirely... Instant recall and dredging it up after eight seconds are very different memory states that produce identical grades." [5] (dolaylı önerme: modern algoritmalar yanıt süresini kullanmayı düşünebilir)
- Response time'ın tanımı: "the mean time needed for users to recall flashcard answers—the time from when the card is viewed until when the answer is submitted. Lower response time on cards answered correctly means the user is more familiar with the material." [6]
- Otomatik/kendi kendine not verme riski (kullanıcı davranışı, FSRS bağlamında): "a lot of learners press 'Hard' on cards they actually failed, because 'Again' feels like a penalty... if you glance at a card, feel a flicker of familiarity, and press 'Good,' you are grading recognition rather than recall." [7] (kullanıcı-notu güvenilirliği sorunu, otomatik notlamayı savunan dolaylı argüman)
- Brainscape/SuperMemo tarzı güven-tabanlı (confidence-based) derecelendirme: kullanıcı 1-5 arası güven puanı veriyor, algoritma düşük güvenli kartları önceliklendiriyor — bu yine kullanıcı girişli, tam otomatik latency-tabanlı not değil [8].
- Yanıt süresini doğrudan not'a (Again/Hard/Good/Easy) çeviren, üretimde kullanılan somut bir uygulama/algoritma (formülüyle) aranan sorguda bulunamadı; KARL (arXiv) çalışması yanıt doğruluğu+süresini öğrenme sonucu ölçütü olarak inceliyor ama grade-türetme formülü doğrulanamadı [6][9].

**S3 — FSRS'te farklı egzersiz türlerini tek karta yazma, geliştirici görüşleri**

- Aynı kelime için iki kart tipi (recognition ve reproduction/fill-in-blank) kullanan bir kullanıcı, FSRS'in başlangıç aralıklarını aşırı uzun hesapladığını bildirdi: "I suspect the problem is that the second card type is usually shown shortly after the first one, and so there is a knowledge transfer that FSRS is not aware of." [10]
- Kullanıcı manuel parametre müdahalesi yaptı: "I had to manually adjust the first 4 parameters to prevent the interval from going straight to 3-4 months when pressing good or easy." Ve FSRS v5'te sorunun büyüdüğünü belirtti: "I've been trying FSRS v5 for a few days, it seems to have exaggerated the problem even more." [10]
- Bu issue'da open-spaced-repetition geliştiricilerinden resmi bir çözüm/"partial credit" önerisi bulunamadı (sadece kullanıcı gözlemi ve topluluk tartışması görüldü); geliştirici yanıtı doğrulanamadı.
- FSRS'in kendisi grade'i (Again/Hard/Good/Easy) ayırt ediyor ama kayıp fonksiyonunda ikili basitleştirme de var: "To calculate the loss, the grade is converted into a binary value: 0 if it's Again, 1 otherwise. This doesn't mean that FSRS itself treats grades as binary, of course it can tell the difference between Hard, Good and Easy." [7]
- Farklı "review kind" (ör. multiple-choice vs yazma) için ayrı ağırlıklandırma FSRS-5/6 dokümantasyonunda resmi bir özellik olarak bulunamadı (aranan: "review kind" FSRS parametre, egzersiz-tipi ağırlığı).

**S4 — Aynı gün çoklu tekrar, kısa vadeli stabilite, relearning, leech**

- FSRS-6'da aynı gün tekrar sonrası stabilite formülü: "S'(S,G) = S · e^(w17 · (G - 3 + w18)) · S^(-w19), where S increases faster when it's small and slower when it's large." [11]
- Kısıt: "While neither FSRS-5 nor FSRS-6 have a proper model of short-term memory, they have a crude heuristic." [11] (dolaylı: aynı gün içi tekrarlar tam bir bilişsel modele değil, sezgisel düzeltmeye dayanıyor)
- Anki learning/relearning steps: "When a card is first seen, it's placed in the learning queue. There, it goes through a series of intervals... The default is two steps: 1min and then 10min." "Relearning Steps: These are the same as learning steps, but for lapsed cards. When you fail a review card (press Again), the card goes through relearning steps, before it becomes a review card again." [12]
- Lapse sayacı ve leech: "Each time a review card lapses (is failed while it is in review mode), a counter increases. When this counter reaches 8, Anki tags the note as a leech and suspends the card." [13][12]
- Post-lapse stability (yanlış cevap sonrası stabilite güncellemesi) FSRS'te "Again" derecesiyle ayrı formülle işleniyor: "Again places the card into relearning mode with significantly decreased stability and increased difficulty" [7] (dolaylı; kaynak resmi FSRS formülünü değil genel açıklamayı veriyor, birebir katsayı doğrulanamadı).

**S5 — Duolingo HLR: egzersiz/lexeme düzeyi güncelleme, oturum içi sayım**

- Model: "p = 2^(-Δ/h)" olasılık, "h_Θ = 2^(Θ·x)" half-life; Θ özellik ağırlıkları vektörü. [3]
- Özellik seti lexeme bazlı: "one tag for each word in the vocabulary (e.g. the lexeme tag for word 'camera' is 'camera'.N.SG)"; lexeme_string formatı: "surface-form/lemma<pos>[<modifiers>...]" [3][4]
- Oturum içi tekrarlar ayrı sayaçlarla tutuluyor, half-life'a girdi oluyor: `session_seen`/`session_correct` = "times the user saw/got correct the word/lexeme during this lesson/practice"; `history_seen`/`history_correct` = "total times user has seen/been correct for the word/lexeme prior to this lesson/practice." [4]
- Egzersiz formatına (reverse translate, listen, speak vb.) göre ayrı ağırlıklandırma dokümanlarda doğrulanamadı: "dokümanda bu alanlardan bahsedilse de farklı egzersiz türlerine ilişkin detay bulunmamaktadır" — WebFetch aracının kendi ifadesi, birincil PDF metni ayrıştırılamadığı için doğrudan alıntı yapılamadı. [3]

**Bulunamayanlar**
- Çoktan seçmeli şans-düzeltmeli (guessing-corrected) olasılık formülü kullanan somut bir SRS uygulaması (aranan: "guessing correction formula spaced repetition multiple choice")
- Duolingo HLR'nin egzersiz formatına (multiple choice/reverse translate/listen/speak) göre ayrı ağırlık verip vermediğine dair birincil metinden birebir alıntı (PDF metin çıkarımı başarısız oldu)
- Yanıt süresinden doğrudan Again/Hard/Good/Easy notu türeten, formülü yayımlanmış üretim uygulaması (aranan: "response time to grade conversion formula flashcard app")
- fsrs-rs/ts-fsrs resmi belgelerinde "review kind" veya çoklu egzersiz tipi / partial credit için özel API/parametre (aranan: "fsrs review kind multiple exercise types api")
- open-spaced-repetition ekibinin (resmi blog/repo) çoklu egzersiz türü konusunda açık görüşü (yalnızca kullanıcı raporu bulundu, geliştirici yanıtı yok)

**Kaynaklar**
[1] https://pubmed.ncbi.nlm.nih.gov/30113206/ · hakemli (The Role of Retrieval in Answering Multiple-choice Questions)
[2] https://quizlet.com/blog/introducing-the-new-quizlet-learn · kurum (Quizlet resmi blog)
[3] https://research.duolingo.com/papers/settles.acl16.pdf · resmi/birincil (Duolingo Research, Settles & Meeder 2016)
[4] https://github.com/duolingo/halflife-regression/blob/master/README.md · resmi/birincil (Duolingo GitHub)
[5] https://domenic.me/fsrs/ · blog
[6] https://arxiv.org/pdf/2402.12291 · hakemli/preprint (KARL)
[7] https://flashcards-open-source-app.com/blog/again-vs-hard-fsrs-flashcards/ · blog
[8] https://www.brainscape.com/academy/confidence-based-repetition-definition/ · kurum/blog
[9] https://arxiv.org/pdf/2402.12291 · hakemli/preprint (tekrar referans, aynı kaynak farklı bölüm)
[10] https://github.com/open-spaced-repetition/fsrs4anki/issues/677 · resmi/birincil (open-spaced-repetition GitHub issue, kullanıcı raporu)
[11] https://expertium.github.io/Algorithm.html · blog (Expertium, FSRS ekibiyle bağlantılı teknik açıklama)
[12] https://docs.ankiweb.net/deck-options.html · resmi/birincil (Anki Manual)
[13] https://docs.ankiweb.net/leeches.html · resmi/birincil (Anki Manual)

Not: Rapor dosyaya yazılamadı çünkü bu ajanın yalnızca WebSearch/WebFetch araçları var, dosya yazma aracı yok. İstenen dosya yolu: `<geçici dosya>` — çağıran ajan bu metni oraya kaydedebilir.