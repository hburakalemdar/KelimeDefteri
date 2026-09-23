import Foundation

/// Eşleştir oyununun tahtası: solda kelimeler, sağda karışık anlamlar. Kimlikler kelimenin turdaki sırasıdır.
nonisolated struct MatchBoard: Equatable {
    enum Result: Equatable {
        case matched(Int)
        case mismatched(left: Int, right: Int)
    }

    /// Sol sütun sırası (kelime kimlikleri).
    let left: [Int]
    /// Sağ sütun sırası: anlamı hangi kelimeye ait.
    let right: [Int]
    private(set) var matched: Set<Int> = []
    /// Eşleşmeden önce yanlış bir çifte girmiş kelimeler.
    private(set) var mistaken: Set<Int> = []
    private(set) var errors = 0

    init<G: RandomNumberGenerator>(count: Int, using generator: inout G) {
        left = Array(0..<count)
        var shuffled = Array(0..<count).shuffled(using: &generator)
        // Anlamlar hep kelimelerle aynı hizada durmasın.
        if count > 1, shuffled == left { shuffled.swapAt(0, 1) }
        right = shuffled
    }

    var isComplete: Bool { matched.count == left.count }

    /// Sol `leftID` ile sağdaki `rightID` anlamı seçildi.
    mutating func pick(left leftID: Int, right rightID: Int) -> Result {
        if leftID == rightID {
            matched.insert(leftID)
            return .matched(leftID)
        }
        errors += 1
        if !matched.contains(leftID) { mistaken.insert(leftID) }
        if !matched.contains(rightID) { mistaken.insert(rightID) }
        return .mismatched(left: leftID, right: rightID)
    }

    /// Eşleşen kelimenin notu: hiç yanlış çifte girmediyse `good`, girdiyse `again`.
    func grade(for id: Int) -> AnswerGrade {
        mistaken.contains(id) ? .again : .good
    }
}
