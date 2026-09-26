import SwiftUI

/// Turdaki sıradaki soru, adım türüne göre: yazarak cevap (`RecallQuestionView`), ısınma için Çoktan Seçmeli
/// ya da üretim için Harfleri Diz. Cevabı `session` kaydeder; seçmeli ve harf sorularında kayıt ve ilerleme
/// adım kimliğiyle yapılır, gecikmiş geçiş başka bir adımı ilerletemez. iPhone'da `RecallGameView`, Mac'te `MacStudyView`.
struct DailyStepView: View {
    let session: StudySession
    /// İlişkili kelimeler, çeldiriciler ve silinme denetimi için bütün defter.
    let words: [Word]

    var body: some View {
        // Silinmiş kelime çizilmez; oyun kimlik kümesi değişince onu atlar.
        if let step = session.currentStep, !step.word.isGone(from: words.aliveIDs) {
            switch step.kind {
            case .recall:
                RecallQuestionView(session: session, words: words)
            case .choice(let options, let correctIndex):
                ChoiceQuestionView(
                    options: options,
                    correctIndex: correctIndex,
                    onAnswer: { session.answer(.recognition(correct: $0), step: step.id) },
                    onNext: { session.next(from: step.id) }
                ) { revealed in
                    GameWordCard(word: step.word, showsMeanings: revealed)
                }
                .id(step.id)
            case .letters(let puzzle):
                LettersQuestionView(
                    word: step.word,
                    puzzle: puzzle,
                    onAnswer: { session.answer($0, step: step.id) },
                    onNext: { session.next(from: step.id) }
                )
                .id(step.id)
            }
        }
    }
}
