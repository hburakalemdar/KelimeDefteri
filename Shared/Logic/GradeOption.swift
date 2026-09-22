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
        case .correct:
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
