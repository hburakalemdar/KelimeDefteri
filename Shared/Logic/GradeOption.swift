import Foundation

/// Cevap açıldıktan sonra gösterilen notlandırma düğmesi.
struct GradeOption: Equatable, Identifiable {
    let title: String
    let systemImage: String
    /// Basınca kelime bilinmiş mi sayılır.
    let known: Bool
    /// Öne çıkan (dolu) düğme; Mac'te Return ile de basılır.
    let isPrimary: Bool

    var id: String { title }
}

extension StudySession.Verdict {
    /// Sonuca göre sunulacak düğmeler, soldan sağa.
    ///
    /// Uygulama sonucu bildiğinde kullanıcıya bir daha sormaz: doğru cevap bilinmiş,
    /// yanlış cevap bilinmemiş sayılır ve tek "Devam" düğmesi öne çıkar. Yanlışta yine de
    /// "Doğru Say" sunulur; kontrol eşanlamlıyı tanımayabilir. Yalnızca cevaba bakıldığında
    /// ne bilindiği belli olmadığı için Bildim / Bilemedim sorulur.
    var gradeOptions: [GradeOption] {
        switch self {
        case .correct, .almost, .synonymOf:
            [GradeOption(title: "Devam", systemImage: "arrow.right", known: true, isPrimary: true)]
        case .incorrect:
            [
                GradeOption(title: "Doğru Say", systemImage: "checkmark", known: true, isPrimary: false),
                GradeOption(title: "Devam", systemImage: "arrow.right", known: false, isPrimary: true),
            ]
        case .peeked:
            [
                GradeOption(title: "Bilemedim", systemImage: "xmark", known: false, isPrimary: false),
                GradeOption(title: "Bildim", systemImage: "checkmark", known: true, isPrimary: false),
            ]
        }
    }
}

extension AnswerGrade {
    /// Hatırlama oyunlarında (Günlük Tekrar, Hızlı Tur, Ters Yön) cevaptan çıkarılan not.
    ///
    /// Yazarak doğru bilinen kelimede hız belirleyicidir: `max(2.5, 0.5 × harf)` saniyeden kısa `easy`,
    /// `max(8, 1.2 × harf)` saniyeden kısa `good`, üstü `hard` (`letters`: cevabı beklenen kelimenin harf
    /// sayısı). Cevaba bakıp "Bildim" denmesi, yazım hatasıyla doğru ("Neredeyse"), Ters Yön'de eşanlamlı
    /// kelime ve "Doğru Say" (kullanıcının kendi beyanı) zorlanarak hatırlamak (`hard`) sayılır.
    static func recall(verdict: StudySession.Verdict, known: Bool, responseTime: Double, letters: Int = 0) -> AnswerGrade {
        guard known else { return .again }
        switch verdict {
        case .peeked, .almost, .synonymOf, .incorrect: return .hard
        case .correct:
            if responseTime < max(2.5, 0.5 * Double(letters)) { return .easy }
            return responseTime < max(8, 1.2 * Double(letters)) ? .good : .hard
        }
    }

    /// Tanıma oyunlarında (Çoktan Seçmeli, Eşleştir, Boşluğu Doldur) doğru cevap hiçbir zaman `easy` değildir.
    static func recognition(correct: Bool) -> AnswerGrade {
        correct ? .good : .again
    }
}
