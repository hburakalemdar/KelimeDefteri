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
    static let hubGames: [GameMode] = [.quickRound, .multipleChoice, .match, .fillBlank, .letters]

    /// Kartın altındaki tek satırlık açıklama.
    var cardDetail: String {
        switch self {
        case .dailyReview: "Zayıflayan kelimeler"
        case .quickRound: "5 kelime, 1 dakika"
        case .multipleChoice: "4 seçenekten doğrusu"
        case .match: "Kelimeleri anlamlarıyla eşle"
        case .fillBlank: "Kitaptaki cümleyi tamamla"
        case .letters: "Harflerden kelimeyi kur"
        case .reverse: "Türkçeden İngilizceye"
        }
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
            deck.count >= 4 ? nil : "En az 4 kelime gerekli"
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

    static let maxLetters = 14

    init(count: Int, withSentence: Int, shortWords: Int) {
        self.count = count
        self.withSentence = withSentence
        self.shortWords = shortWords
    }

    /// (İngilizce, cümle) çiftlerinden.
    init(entries: [(english: String, example: String)]) {
        count = entries.count
        withSentence = entries.count { Self.sentence($0.example, contains: $0.english) }
        shortWords = entries.count { (1...Self.maxLetters).contains(Self.letterCount($0.english)) }
    }

    /// Cümlede kelimenin kendisi geçiyor mu (bkz. `ClozeSentence`).
    static func sentence(_ sentence: String, contains word: String) -> Bool {
        ClozeSentence(sentence: sentence, word: word) != nil
    }

    static func letterCount(_ word: String) -> Int {
        word.count { $0.isLetter }
    }
}
