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
