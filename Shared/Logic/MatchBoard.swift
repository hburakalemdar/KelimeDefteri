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
    /// Eşleşmeden önce yanlış bir çiftte "soru" rolünde olmuş kelimeler. Yanlış çiftte yalnızca ilk
    /// dokunulan (soru rolündeki) kutunun kelimesi sayılır: kullanıcı onun eşini arıyordu; öbür kutunun
    /// kelimesini yanlış bilmiş değildir.
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

    /// Sol `leftID` ile sağdaki `rightID` anlamı seçildi. `questionIsLeft`: ilk dokunulan (soru rolündeki)
    /// kutu soldaki mi; yanlış çiftte hata o kutunun kelimesine yazılır.
    mutating func pick(left leftID: Int, right rightID: Int, questionIsLeft: Bool = true) -> Result {
        if leftID == rightID {
            matched.insert(leftID)
            return .matched(leftID)
        }
        errors += 1
        let question = questionIsLeft ? leftID : rightID
        if !matched.contains(question) { mistaken.insert(question) }
        return .mismatched(left: leftID, right: rightID)
    }

    /// Eşleşen kelimenin notu: hiç yanlış anlamla eşleştirilmediyse `good`, eşleştirildiyse `again`.
    func grade(for id: Int) -> AnswerGrade {
        mistaken.contains(id) ? .again : .good
    }
}
