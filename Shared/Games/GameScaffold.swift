import SwiftUI

/// Oyun sayfalarının ortak kabuğu.
/// iOS'ta tam ekran açılır: NavigationStack, solda Kapat, ortada ilerleme.
/// Mac'te menü penceresinin içinde durur: üstte "Oyunlar"a dönüş (Esc) ve sağda ilerleme.
struct GameScaffold<Header: View, Content: View>: View {
    /// Tur sürerken üst çubuk görünür; tur özetinde gizlenir.
    let showsBar: Bool
    let onClose: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content()
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsBar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { onClose() }
                                .accessibilityLabel("Kapat")
                        }
                        ToolbarItem(placement: .principal) {
                            header()
                        }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            if showsBar {
                HStack(spacing: 10) {
                    MacBackButton(action: onClose)
                    Spacer(minLength: 8)
                    header()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            content()
        }
        #endif
    }
}

#if os(macOS)
/// Menü penceresinde oyundan oyun merkezine dönüş düğmesi; Esc ile de basılır.
struct MacBackButton: View {
    var title = "Oyunlar"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.backward")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.cancelAction)
        .help("\(title) (Esc)")
    }
}
#endif

/// Oyun kartlarının platforma göre ölçüsü ve zemini: iOS'ta gruplu liste kartı, Mac'te menü
/// penceresinin malzemesi üstünde soluk kutu.
enum GameStyle {
    #if os(iOS)
    static let cardRadius: CGFloat = 26
    static let cardPadding: CGFloat = 20
    static let tileRadius: CGFloat = 16
    static var cardFill: Color { Color(.secondarySystemGroupedBackground) }
    static var pageBackground: Color { Color(.systemGroupedBackground) }
    /// Soru kartındaki İngilizce kelime.
    static let headline = Font.system(.largeTitle, design: .serif, weight: .semibold)
    #else
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let tileRadius: CGFloat = 12
    static var cardFill: HierarchicalShapeStyle { .quinary }
    static var pageBackground: Color { .clear }
    static let headline = Font.system(size: 28, weight: .semibold, design: .serif)
    #endif
}

extension View {
    /// Oyunlardaki soru kartı: iç boşluk, tam genişlik, yuvarlak köşeli zemin.
    func gameCard() -> some View {
        padding(GameStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GameStyle.cardFill, in: .rect(cornerRadius: GameStyle.cardRadius, style: .continuous))
    }

    /// Oyun sayfasının kenar boşlukları: iOS'ta sistem boşluğu, Mac'in dar menü penceresinde 14 pt.
    func gamePagePadding() -> some View {
        #if os(iOS)
        padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        #else
        padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        #endif
    }

    /// Alt çubuğun (Devam, Göster, not düğmeleri) kenar boşlukları.
    func gameBarPadding() -> some View {
        #if os(iOS)
        padding(.horizontal)
            .padding(.vertical, 12)
        #else
        padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, 4)
        #endif
    }

    /// Uygulama arka plana gidince (Mac'te menü penceresi kapanınca) cevap süresini durdurur,
    /// geri gelince sürdürür.
    func pausesClock(_ pause: @escaping () -> Void, resume: @escaping () -> Void) -> some View {
        modifier(ClockPauser(pause: pause, resume: resume))
    }
}

private struct ClockPauser: ViewModifier {
    let pause: () -> Void
    let resume: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        #if os(iOS)
        content.onChange(of: scenePhase) { old, new in
            if new == .active { resume() } else if old == .active { pause() }
        }
        #else
        // Menü çubuğu penceresi kapanınca görünüm kaybolur; açılınca yeniden görünür.
        content
            .onDisappear { pause() }
            .onAppear { resume() }
        #endif
    }
}

/// Oyunların üstündeki ince ilerleme çubuğu ve "3/10".
struct GameProgressHeader: View {
    let done: Int
    let total: Int
    /// Eşleştir gibi soru sırası olmayan oyunlarda yalnızca çubuk gösterilir.
    var showsCount = true

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(width: 150)
            if showsCount {
                Text("\(min(done + 1, total))/\(total)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) kelimeden \(min(done + 1, total)). kelime")
    }
}

extension GameMode {
    var color: Color {
        switch self {
        case .dailyReview: .blue
        case .quickRound: .orange
        case .multipleChoice: .blue
        case .match: .green
        case .fillBlank: .purple
        case .letters: .pink
        case .reverse: .cyan
        }
    }
}
