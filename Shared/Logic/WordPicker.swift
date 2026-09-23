import Foundation

/// Tur için kelime seçimi ve sırası.
///
/// Sıra rastgeledir ama tekrara en çok ihtiyacı olan kelime öne gelme eğilimindedir:
/// her kelimenin bir ağırlığı vardır ve ağırlıklı, tekrarsız örnekleme yapılır.
/// Rastgele sayı üreteci dışarıdan verilir; testte sabit tohumla hep aynı sıra çıkar.
nonisolated enum WordPicker {
    struct Candidate<ID: Hashable> {
        let id: ID
        let weight: Double
        let isNew: Bool

        init(id: ID, weight: Double, isNew: Bool = false) {
            self.id = id
            self.weight = weight
            self.isNew = isNew
        }
    }

    /// Hiç çalışılmamış kelimenin ağırlığı.
    static let newWeight = 1.0
    /// Hiçbir kelime tamamen dışarıda kalmasın diye her ağırlığa eklenen pay.
    static let baseWeight = 0.1

    /// Geçici ağırlık (hafıza motoru gelene kadar): tekrar zamanını ne kadar geçtiği.
    /// Bir haftadan fazla geciken kelime en yüksek ağırlığı alır.
    static func delayWeight(dueDate: Date, isNew: Bool, now: Date) -> Double {
        if isNew { return newWeight }
        let overdueDays = max(0, now.timeIntervalSince(dueDate) / 86_400)
        return min(1, overdueDays / 7) + baseWeight
    }

    /// Ağırlıklı, tekrarsız sıra (Efraimidis–Spirakis): her kelimeye `u^(1/w)` anahtarı
    /// verilir, büyükten küçüğe dizilir.
    ///
    /// - `limit`: en fazla kaç kelime alınır; `maxNew`: bunların en fazla kaçı yeni olabilir.
    /// - `avoidingFirst`: önceki turun ilk kelimesi; mümkünse bu turun ilki olmaz.
    static func order<ID: Hashable, G: RandomNumberGenerator>(
        _ candidates: [Candidate<ID>],
        limit: Int? = nil,
        maxNew: Int? = nil,
        avoidingFirst previousFirst: ID? = nil,
        using generator: inout G
    ) -> [ID] {
        let ranked = candidates.map { candidate in
            let weight = max(candidate.weight, .leastNormalMagnitude)
            let u = Double.random(in: .leastNonzeroMagnitude..<1, using: &generator)
            return (candidate: candidate, key: log(u) / weight)
        }
        .sorted { $0.key > $1.key }
        .map(\.candidate)

        var picked: [Candidate<ID>] = []
        var newCount = 0
        for candidate in ranked {
            if let limit, picked.count >= limit { break }
            if candidate.isNew {
                if let maxNew, newCount >= maxNew { continue }
                newCount += 1
            }
            picked.append(candidate)
        }

        var ids = picked.map(\.id)
        if let previousFirst, ids.first == previousFirst {
            if ids.count > 1 {
                ids.swapAt(0, 1)
            } else if let other = ranked.first(where: { $0.id != previousFirst && (!$0.isNew || maxNew != 0) }) {
                // Tek kelimelik turda yerine başka bir kelime seçilebiliyorsa onu al.
                ids[0] = other.id
            }
        }
        return ids
    }

    /// Yanlış bilinen kelimenin sıraya yeniden gireceği yer: arada en az 2 kelime olsun,
    /// turda o kadar kelime yoksa en sona.
    static func reinsertionIndex(queueCount: Int) -> Int {
        min(2, queueCount)
    }
}

/// Tohumlanabilir rastgele sayı üreteci (SplitMix64). Aynı tohum hep aynı sırayı verir.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
