import Foundation

/// Harfleri Diz bulmacası: kelimenin harfleri karışık taşlar olarak verilir, kullanıcı yuvalara dizer.
///
/// Yalnızca harfler yuvaya girer; boşluk ve tire gibi işaretler yerinde sabit durur.
/// Karşılaştırma büyük/küçük harf ve aksan gözetmez.
nonisolated struct LetterPuzzle: Equatable {
    enum Cell: Equatable {
        /// Harf yuvası; değer yuvanın sırası.
        case slot(Int)
        /// Sabit karakter (boşluk, tire, kesme işareti).
        case fixed(Character)
    }

    /// Ekranda soldan sağa hücreler.
    let layout: [Cell]
    /// Doğru harfler, yuva sırasıyla.
    let answer: [Character]
    /// Karışık taşlar; kimlik dizideki yer.
    let tiles: [Character]
    /// Her yuvada hangi taş duruyor.
    private(set) var slots: [Int?]
    private(set) var mistakes = 0
    private(set) var isRevealed = false

    init<G: RandomNumberGenerator>(word: String, using generator: inout G) {
        var layout: [Cell] = []
        var answer: [Character] = []
        for character in word.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isLetter {
                layout.append(.slot(answer.count))
                answer.append(character)
            } else {
                layout.append(.fixed(character))
            }
        }
        self.layout = layout
        self.answer = answer
        var shuffled = answer.shuffled(using: &generator)
        // Taşlar tesadüfen doğru sırada gelmesin (bütün harfler aynı değilse).
        if Set(answer.map(Self.fold)).count > 1 {
            while shuffled.map(Self.fold) == answer.map(Self.fold) {
                shuffled.shuffle(using: &generator)
            }
        }
        tiles = shuffled
        slots = Array(repeating: nil, count: answer.count)
    }

    var isFull: Bool { !slots.contains(nil) }

    var isCorrect: Bool {
        isFull && zip(slots, answer).allSatisfy { tile, letter in Self.fold(tiles[tile!]) == Self.fold(letter) }
    }

    /// Henüz yuvaya konmamış taşlar.
    var freeTiles: [Int] {
        let used = Set(slots.compactMap { $0 })
        return tiles.indices.filter { !used.contains($0) }
    }

    /// Taşı ilk boş yuvaya koyar.
    mutating func place(tile: Int) {
        guard !isRevealed, !slots.contains(tile), let empty = slots.firstIndex(of: nil) else { return }
        slots[empty] = tile
    }

    /// Yuvadaki harfi taşlara geri gönderir.
    mutating func remove(slot: Int) {
        guard !isRevealed, slots.indices.contains(slot) else { return }
        slots[slot] = nil
    }

    /// Klavyeden yazılan harfe uyan ilk serbest taş (büyük/küçük harf ve aksan gözetmez); yoksa `nil`.
    func freeTile(matching character: Character) -> Int? {
        let key = Self.fold(character)
        return freeTiles.first { Self.fold(tiles[$0]) == key }
    }

    /// En sağdaki dolu yuva (klavyede ⌫ onu boşaltır); hepsi boşsa `nil`.
    var lastFilledSlot: Int? {
        slots.lastIndex { $0 != nil }
    }

    /// Yuvalar dolunca çağrılır: doğruysa true; yanlışsa hata sayılır ve false (harfler yerinde kalır).
    mutating func check() -> Bool {
        guard isFull else { return false }
        if isCorrect { return true }
        mistakes += 1
        return false
    }

    /// Cevabı açar: yuvalar doğru harflerle dolar.
    mutating func reveal() {
        var remaining = Array(tiles.indices)
        slots = answer.map { letter in
            let index = remaining.firstIndex { Self.fold(tiles[$0]) == Self.fold(letter) }!
            return remaining.remove(at: index)
        }
        isRevealed = true
    }

    /// 0 hata `good`, 1–2 hata `hard`, cevabı açmak ya da 3+ hata `again`.
    var grade: AnswerGrade {
        if isRevealed || mistakes > 2 { return .again }
        return mistakes == 0 ? .good : .hard
    }

    /// Taşta ve yuvada gösterilen hâli: küçük harf (büyük harfli taş kelimenin ilk harfini ele vermesin).
    static func display(_ character: Character) -> String {
        String(character).lowercased(with: Locale(identifier: "en_US"))
    }

    static func fold(_ character: Character) -> String {
        String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }
}
