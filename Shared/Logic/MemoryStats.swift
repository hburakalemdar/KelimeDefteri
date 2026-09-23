import Foundation

/// Hafıza yüzdesinin gösterimi ve defter geneli dağılımı.
nonisolated enum MemoryStats {
    /// Halka rengi için üç düzey.
    enum Level: Equatable {
        case strong, fading, weak

        init(_ memory: Double) {
            self = memory >= 0.85 ? .strong : memory >= 0.60 ? .fading : .weak
        }
    }

    /// "%62" ya da "Yeni". Aşağı yuvarlanır: %90'ın altına inmiş (zayıf) kelime %90 görünmesin.
    static func text(_ memory: Double?) -> String {
        guard let memory else { return "Yeni" }
        return "%\(percent(memory))"
    }

    static func percent(_ memory: Double) -> Int {
        Int((min(max(memory, 0), 1) * 100 + 1e-9).rounded(.down))
    }

    /// İlerleme ekranındaki dağılım dilimleri.
    enum Bucket: Int, CaseIterable, Identifiable {
        case new, below50, below70, below85, below95, top

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .new: "Yeni"
            case .below50: "%0–50"
            case .below70: "%50–70"
            case .below85: "%70–85"
            case .below95: "%85–95"
            case .top: "%95+"
            }
        }

        /// Dilimi temsil eden hafıza değeri (halkanın doluluğu ve rengi için); yenide `nil`.
        var representative: Double? {
            switch self {
            case .new: nil
            case .below50: 0.35
            case .below70: 0.6
            case .below85: 0.78
            case .below95: 0.9
            case .top: 0.98
            }
        }

        init(_ memory: Double?) {
            guard let memory else { self = .new; return }
            self = switch memory {
            case ..<0.5: .below50
            case ..<0.7: .below70
            case ..<0.85: .below85
            case ..<0.95: .below95
            default: .top
            }
        }
    }

    /// Yeni kelimeler hariç ortalama; hiç çalışılmış kelime yoksa `nil`.
    static func average(_ memories: [Double?]) -> Double? {
        let studied = memories.compactMap { $0 }
        guard !studied.isEmpty else { return nil }
        return studied.reduce(0, +) / Double(studied.count)
    }
}
