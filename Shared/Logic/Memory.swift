import Foundation

/// Hafıza motoru: FSRS-4.5 unutma eğrisine dayanan dayanıklılık (S) ve zorluk (D) güncellemesi.
///
/// S gün cinsindendir: son cevaptan S gün sonra kelimeyi hatırlama ihtimali %90'a iner.
/// Sıradaki tekrar bu ana konur. Ayrıntılar `docs/SPEC-OYUN.md` §2.
nonisolated enum Memory {
    struct Result: Equatable {
        let stability: Double
        let difficulty: Double
        let due: Date
    }

    static let dayLength: TimeInterval = 86_400
    /// Sıradaki tekrar bu hatırlama ihtimaline göre konur.
    static let targetRetention = 0.9
    static let minimumStability = 0.3
    static let difficultyRange = 1.0...10.0

    private static let firstStability = [0.4, 1.2, 3.0, 8.0]
    private static let firstDifficulty = [7.0, 6.0, 5.0, 3.5]

    /// Hatırlama ihtimali: `(1 + 19/81 · t / S) ^ −0.5`. `t = S` iken 0.9.
    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + 19.0 / 81.0 * max(elapsedDays, 0) / stability, -0.5)
    }

    static func review(
        stability: Double,
        difficulty: Double,
        lastReviewedAt: Date?,
        grade: AnswerGrade,
        weight: Double,
        now: Date
    ) -> Result {
        let index = grade.rawValue - 1
        let newStability: Double
        let newDifficulty: Double

        if stability <= 0 {
            newStability = max(minimumStability, firstStability[index] * weight)
            newDifficulty = firstDifficulty[index]
        } else {
            // Son tekrar zamanı bilinmiyorsa kelime tam vaktinde soruluyor sayılır (R = 0.9).
            let elapsed = lastReviewedAt.map { now.timeIntervalSince($0) / dayLength } ?? stability
            let r = retrievability(elapsedDays: elapsed, stability: stability)
            switch grade {
            case .again:
                newStability = max(minimumStability, stability * (weight == 1 ? 0.35 : 0.5))
            case .hard, .good, .easy:
                let growth = exp(1.5) * (11 - difficulty) * pow(stability, -0.2) * (exp(1.2 * (1 - r)) - 1)
                let multiplier = switch grade {
                case .hard: 0.5
                case .easy: 1.5
                default: 1.0
                }
                newStability = stability * (1 + growth * multiplier * weight)
            }
            newDifficulty = nextDifficulty(difficulty, grade: grade)
        }
        return Result(
            stability: newStability,
            difficulty: newDifficulty,
            due: now.addingTimeInterval(newStability * dayLength)
        )
    }

    /// Nota göre zorluk değişir, sonra 5'e doğru %5 yaklaşır ve 1…10 içinde kalır.
    static func nextDifficulty(_ difficulty: Double, grade: AnswerGrade) -> Double {
        let delta = switch grade {
        case .again: 1.0
        case .hard: 0.4
        case .good: -0.2
        case .easy: -0.6
        }
        let moved = difficulty + delta
        let reverted = moved + (5 - moved) * 0.05
        return min(max(reverted, difficultyRange.lowerBound), difficultyRange.upperBound)
    }
}
