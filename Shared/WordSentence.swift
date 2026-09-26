import Foundation
import SwiftData

/// Kelimenin kitapta geçtiği bir cümle ve (isteğe bağlı) hangi anlamıyla geçtiği.
///
/// Her cümle ayrı bir iCloud kaydıdır: iki cihazda aynı anda eklenen cümlelerin ikisi de kalır. Bütün alanların
/// varsayılanı var (CloudKit). Tasarım: `docs/SPEC-CUMLE.md`.
@Model
final class WordSentence {
    /// Kalıcı kimlik; her cihazda aynı. Aynı zamanlı kayıtlar arasında sıralamayı ve kopya temizliğinde
    /// hangisinin kalacağını belirler (her cihaz aynı kaydı seçsin).
    var sentenceID: String = UUID().uuidString
    var text: String = ""
    /// Cümlenin bağlı olduğu anlam, `Word.turkish` içindeki yazılışıyla; boş = anlamı belirsiz.
    /// Kimlik değil metin: anlam yeniden adlandırılırsa bağ kopar, cümle belirsiz sayılır (etiket silinmez).
    var meaning: String = ""
    var createdAt: Date = Date.now
    /// Kelimenin sadeleştirilmiş İngilizcesi (`AnswerChecker.fold`). Kelimesi silinmiş bir kopyaya bağlı gelen cümle
    /// (birleştirmeden sonra başka cihazdan eklendi) bakımda aynı anahtarlı kelimeye bağlanır; boşsa bağlanmaz.
    var wordKey: String = ""
    var word: Word?

    init(text: String, meaning: String = "", createdAt: Date = .now) {
        self.text = text
        self.meaning = meaning
        self.createdAt = createdAt
    }

    /// Karşılaştırma anahtarı: boşluklar tek boşluğa indirilir, büyük/küçük harf ve noktalama korunur.
    /// Çok satırlı alıntının satır sonları da boşluk sayılır (metnin kendisi değişmez).
    nonisolated static func key(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
