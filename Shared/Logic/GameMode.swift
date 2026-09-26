import Foundation

/// Cevaptan çıkarılan not. Kullanıcıya sorulmaz (bkz. spec §2).
nonisolated enum AnswerGrade: Int, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var isCorrect: Bool { self != .again }
}

/// Kelimenin sorulduğu oyun türü. `rawValue` `ReviewLog.mode`'a yazılır; değiştirilmemeli.
nonisolated enum GameMode: String, CaseIterable, Sendable {
    case dailyReview = "daily"
    case quickRound = "quick"
    case multipleChoice = "choice"
    case match = "match"
    case fillBlank = "blank"
    case letters = "letters"
    case reverse = "reverse"

    var title: String {
        switch self {
        case .dailyReview: "Günlük Tekrar"
        case .quickRound: "Hızlı Tur"
        case .multipleChoice: "Çoktan Seçmeli"
        case .match: "Eşleştir"
        case .fillBlank: "Boşluğu Doldur"
        case .letters: "Harfleri Diz"
        case .reverse: "Ters Yön"
        }
    }

    /// Cevabın hafızaya etkisi: kelimeyi hatırlamak, seçeneklerde tanımaktan daha değerlidir.
    var weight: Double {
        switch self {
        case .dailyReview, .quickRound, .reverse: 1.0
        case .letters: 0.8
        case .multipleChoice, .match, .fillBlank: 0.6
        }
    }
}

// MARK: - Oyun merkezi

extension GameMode {
    /// Oyun merkezinde kartı gösterilen oyunlar, sırasıyla. Her oyun yapıldıkça buraya eklenir.
    static let hubGames: [GameMode] = [.quickRound, .multipleChoice, .match, .fillBlank, .letters, .reverse]

    /// Kartın altındaki kısa açıklama; dar kartta bir satıra sığsın diye kısa tutulur.
    var cardDetail: String {
        switch self {
        case .dailyReview: "Zayıflayan kelimeler"
        case .quickRound: "\(StudySession.quickCount) kelime, ~\(Self.quickRoundMinutes) dakika"
        case .multipleChoice: "4 seçenekten doğrusu"
        case .match: "Anlamıyla eşle"
        case .fillBlank: "Cümleyi tamamla"
        case .letters: "Harflerden kelimeyi kur"
        case .reverse: "Türkçeden İngilizceye"
        }
    }

    /// Hızlı Tur'un tahmini süresi (dakika, en yakına yuvarlanır): 5 kelime × 25 sn ≈ 2 dakika.
    static var quickRoundMinutes: Int {
        max(1, Int((Double(StudySession.quickCount) * RoundText.secondsPerWord / 60).rounded()))
    }

    var systemImage: String {
        switch self {
        case .dailyReview: "rectangle.stack.fill"
        case .quickRound: "bolt.fill"
        case .multipleChoice: "checklist"
        case .match: "square.grid.2x2.fill"
        case .fillBlank: "text.cursor"
        case .letters: "textformat.abc"
        case .reverse: "arrow.left.arrow.right"
        }
    }

    /// Kelime sayısı yetmiyorsa kartta açıklama yerine yazılacak neden; oynanabiliyorsa `nil`.
    func unavailableReason(for deck: GameDeck) -> String? {
        switch self {
        case .dailyReview, .quickRound, .reverse:
            deck.count >= 1 ? nil : "En az 1 kelime gerekli"
        case .multipleChoice, .match:
            // Ortak anlamlı kelimeler birbirinin çeldiricisi/eşi olamaz; farklı anlam sayısı yetmeli.
            deck.distinctMeaningCount >= 4 ? nil : "Farklı anlamlı 4 kelime gerekli"
        case .fillBlank:
            deck.withSentence >= 4 ? nil : "Cümlesi olan 4 kelime gerekli"
        case .letters:
            deck.shortWords >= 1 ? nil : "En fazla 14 harfli kelime gerekli"
        }
    }
}

/// Oyunların oynanabilirliği için defterin özeti.
nonisolated struct GameDeck: Equatable {
    var count: Int
    /// Kitaptaki cümlesinde kelimenin kendisi geçen kelimeler (Boşluğu Doldur).
    var withSentence: Int
    /// En fazla 14 harfli kelimeler (Harfleri Diz).
    var shortWords: Int
    /// Farklı Türkçe anlam sayısı: ortak anlamı olan kelimeler (`ChoiceQuiz.shareMeaning`) tek küme sayılır
    /// (Çoktan Seçmeli, Eşleştir).
    var distinctMeaningCount: Int

    static let maxLetters = 14

    /// `distinctMeaningCount` verilmezse `count` sayılır.
    init(count: Int, withSentence: Int, shortWords: Int, distinctMeaningCount: Int? = nil) {
        self.count = count
        self.withSentence = withSentence
        self.shortWords = shortWords
        self.distinctMeaningCount = distinctMeaningCount ?? count
    }

    /// (İngilizce, cümleler, Türkçe) üçlülerinden; cümlelerinden birinde boşluk açılabilen kelime sayılır.
    init(entries: [(english: String, sentences: [String], turkish: String)]) {
        count = entries.count
        withSentence = entries.count { entry in entry.sentences.contains { Self.sentence($0, contains: entry.english) } }
        shortWords = entries.count { (1...Self.maxLetters).contains(Self.letterCount($0.english)) }
        distinctMeaningCount = Self.distinctMeaningCount(entries.map(\.turkish))
    }

    /// Ortak anlamı olan Türkçe karşılıklar zincirleme tek kümede toplanır; küme sayısı döner.
    /// Anlamı boş olan kayıt kimseyle ortak değildir, kendi başına bir kümedir.
    static func distinctMeaningCount(_ turkish: [String]) -> Int {
        var parent = Array(turkish.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        var owner: [String: Int] = [:]
        for (index, text) in turkish.enumerated() {
            for meaning in Set(AnswerChecker.meanings(in: text)) {
                if let other = owner[meaning] {
                    parent[root(index)] = root(other)
                } else {
                    owner[meaning] = index
                }
            }
        }
        return Set(turkish.indices.map(root)).count
    }

    /// Cümlede kelimenin kendisi geçiyor mu (bkz. `ClozeSentence`).
    static func sentence(_ sentence: String, contains word: String) -> Bool {
        ClozeSentence(sentence: sentence, word: word) != nil
    }

    static func letterCount(_ word: String) -> Int {
        word.count { $0.isLetter }
    }
}
