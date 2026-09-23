import Foundation

/// Ters Yön'de yazılan İngilizce cevabın kontrolü.
///
/// Sadeleştirilmiş hâller (`AnswerChecker.fold`) eşitse doğru; 5 ve daha uzun kelimelerde
/// en fazla 1 harf fark (eksik, fazla ya da yanlış harf) yazım hatası sayılır.
nonisolated enum ReverseChecker {
    enum Result: Equatable {
        case exact
        case typo
        case wrong
    }

    static let typoMinimumLength = 5

    static func check(_ answer: String, expected: String) -> Result {
        let given = AnswerChecker.fold(answer)
        let target = AnswerChecker.fold(expected)
        guard !given.isEmpty else { return .wrong }
        if given == target { return .exact }
        let letters = target.count { $0.isLetter }
        if letters >= typoMinimumLength, distance(given, target, limit: 1) <= 1 { return .typo }
        return .wrong
    }

    /// Levenshtein uzaklığı; `limit`i aşınca erken döner.
    static func distance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if current.min()! > limit { return limit + 1 }
            previous = current
        }
        return a.isEmpty ? b.count : previous[b.count]
    }
}
