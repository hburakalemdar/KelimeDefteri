import SwiftData
import SwiftUI

struct WordListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, weak, strong, new
        var id: Self { self }

        var title: String {
            switch self {
            case .all: "Tümü"
            case .weak: "Zayıf"
            case .strong: "Güçlü"
            case .new: "Yeni"
            }
        }

        /// Zayıf, Güçlü ve Yeni birbirini dışlar: yeni kelimenin hafızası henüz yok.
        func includes(_ word: Word, now: Date) -> Bool {
            switch self {
            case .all: true
            case .weak: !word.isNew && word.isWeak(at: now)
            case .strong: !word.isNew && !word.isWeak(at: now)
            case .new: word.isNew
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case newest, alphabetical, memory, hardest
        var id: Self { self }

        var title: String {
            switch self {
            case .newest: "Eklenme Tarihi"
            case .alphabetical: "A–Z"
            case .memory: "Hafıza"
            case .hardest: "En Zor"
            }
        }
    }

    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var editing: Word?
    @AppStorage("wordListFilter") private var filter: Filter = .all
    @AppStorage("wordListSort") private var sort: Sort = .newest

    private var rows: [Word] {
        let query = AnswerChecker.fold(searchText)
        let now = Date.now
        let matching = words.filter { word in
            filter.includes(word, now: now) && (query.isEmpty
                || AnswerChecker.fold(word.english).contains(query)
                || AnswerChecker.fold(word.turkish).contains(query))
        }
        return switch sort {
        case .newest: matching
        case .alphabetical: matching.sorted { $0.english.localizedStandardCompare($1.english) == .orderedAscending }
        // Yeni kelimelerin hafızası ve zorluğu henüz belli değil; bu iki sıralamada sona kalırlar.
        case .memory: matching.sorted { ($0.memory(at: now) ?? 2) < ($1.memory(at: now) ?? 2) }
        case .hardest: matching.sorted { ($0.isNew ? -1 : $0.difficulty) > ($1.isNew ? -1 : $1.difficulty) }
        }
    }

    var body: some View {
        NavigationStack {
            List(rows) { word in
                NavigationLink(value: word) {
                    WordRow(word: word)
                }
                .swipeActions {
                    // Sistem uygulamalarındaki gibi yalnızca simge; "Sil" adı VoiceOver için kalır.
                    Button(role: .destructive) {
                        context.delete(word)
                    } label: {
                        Label("Sil", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
                .contextMenu {
                    Button("Düzenle", systemImage: "pencil") { editing = word }
                    Button("Dinle", systemImage: "speaker.wave.2") { Speaker.shared.speak(word.english) }
                    Divider()
                    Button("Sil", systemImage: "trash", role: .destructive) {
                        context.delete(word)
                    }
                }
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Henüz Kelime Yok",
                        systemImage: "books.vertical",
                        description: Text("Okurken takıldığın kelimeleri Ekle sekmesinden kaydet.")
                    )
                } else if rows.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if rows.isEmpty {
                    ContentUnavailableView {
                        Label("“\(filter.title)” Boş", systemImage: "line.3.horizontal.decrease")
                    } actions: {
                        Button("Tümünü Göster") { filter = .all }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "İngilizce ya da Türkçe ara")
            .navigationTitle("Kelimelerim")
            .navigationSubtitle(words.isEmpty ? "" : DeckSummary.text(for: words))
            .navigationDestination(for: Word.self) { word in
                WordDetailView(word: word)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Göster", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Sırala", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Süz ve Sırala", systemImage: "line.3.horizontal.decrease")
                    }
                    .tint(filter == .all ? nil : .accentColor)
                }
            }
            .sheet(item: $editing) { word in
                NavigationStack {
                    WordFormView(mode: .edit(word))
                }
            }
        }
    }
}

private struct WordRow: View {
    let word: Word

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.english)
                    .font(.system(.body, design: .serif, weight: .semibold))
                Text(word.turkish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MemoryRing(memory: word.memory(), size: 18, text: .trailing)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    WordListView()
        .modelContainer(PreviewData.container)
}
#endif
