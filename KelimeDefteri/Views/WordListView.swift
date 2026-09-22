import SwiftData
import SwiftUI

struct WordListView: View {
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var editing: Word?

    private var filtered: [Word] {
        let query = AnswerChecker.fold(searchText)
        guard !query.isEmpty else { return words }
        return words.filter {
            AnswerChecker.fold($0.english).contains(query) || AnswerChecker.fold($0.turkish).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !words.isEmpty && searchText.isEmpty {
                    Section {
                        StatsLine(words: words)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Section {
                    ForEach(filtered) { word in
                        Button {
                            editing = word
                        } label: {
                            WordRow(word: word)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Sil", systemImage: "trash", role: .destructive) {
                                context.delete(word)
                            }
                        }
                    }
                }
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Henüz kelime yok",
                        systemImage: "books.vertical",
                        description: Text("Okurken takıldığın kelimeleri Ekle sekmesinden kaydet.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "İngilizce ya da Türkçe ara")
            .navigationTitle("Kelimelerim")
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
                    .font(.system(.title3, design: .serif).weight(.semibold))
                Text(word.turkish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            BoxDots(box: word.box)
        }
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    WordListView()
        .modelContainer(PreviewData.container)
}
#endif
