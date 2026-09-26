import SwiftData
import SwiftUI

/// Kelime listesi penceresi: sıralanabilir tablo, arama, ekleme, düzenleme (çift tık) ve silme (⌫).
struct WordsWindow: View {
    @Query private var words: [Word]
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var selection = Set<Word.ID>()
    @State private var sortOrder = [KeyPathComparator(\Word.createdAt, order: .reverse)]
    @State private var editing: Word?
    @State private var isAdding = false

    private var rows: [Word] {
        let query = AnswerChecker.fold(searchText)
        let matching = query.isEmpty ? words : words.filter {
            AnswerChecker.fold($0.english).contains(query) || AnswerChecker.fold($0.turkish).contains(query)
        }
        return matching.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("İngilizce", value: \.english) { word in
                Text(word.english)
                    .font(.system(.body, design: .serif).weight(.semibold))
            }
            TableColumn("Türkçe", value: \.turkish)
            TableColumn("Cümle") { word in
                // İlk cümle tek satır; başka cümleleri varsa sayısı. Hepsi imleç ipucunda.
                let sentences = word.sentenceTexts
                if let first = sentences.first {
                    HStack(spacing: 4) {
                        Text(first)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        if sentences.count > 1 {
                            Text("+\(sentences.count - 1)")
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .help(sentences.joined(separator: "\n\n"))
                }
            }
            .width(min: 120, ideal: 220)
            TableColumn("Hafıza", value: \.memorySortValue) { word in
                MemoryRing(memory: word.memory(), size: 14, text: .trailing, isLapsed: word.isLapsed)
                    .foregroundStyle(.secondary)
                    .help(word.isNew ? "Henüz çalışılmadı" : word.isLapsed ? "Yanlış bildin; tekrar edilecek" : "Şu an hatırlama ihtimali")
            }
            .width(min: 60, ideal: 70, max: 80)
            TableColumn("Sıradaki tekrar", value: \.dueDate) { word in
                // Yanlış bilinen kelime vadesi gelmemiş olsa da turuncu "Tekrar edilecek · Yarın" yazar.
                if word.isLapsed {
                    Text(LapsedLabel.text(for: word))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                } else {
                    Text(Leitner.dueDescription(for: word.dueDate))
                        .foregroundStyle(word.isDue(at: .now) ? Color.accentColor : .secondary)
                        .monospacedDigit()
                }
            }
            .width(min: 90, ideal: 150)
        }
        .contextMenu(forSelectionType: Word.ID.self) { ids in
            if ids.count == 1, let word = word(for: ids.first) {
                Button("Düzenle…") { editing = word }
            }
            if !ids.isEmpty {
                Button("Sil", role: .destructive) { delete(ids) }
            }
        } primaryAction: { ids in
            editing = word(for: ids.first)
        }
        .onDeleteCommand { delete(selection) }
        .overlay {
            if words.isEmpty {
                ContentUnavailableView(
                    "Henüz kelime yok",
                    systemImage: "books.vertical",
                    description: Text("Okurken takıldığın kelimeleri ekle ya da herhangi bir uygulamada seçip ⇧⌘E'ye bas.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "İngilizce ya da Türkçe ara")
        .navigationTitle("Kelimelerim")
        .navigationSubtitle(subtitle)
        // Pencere açılınca hafıza alanları cevap kayıtlarından yeniden hesaplanır.
        .onAppear { MemoryCache.refreshAll(in: context) }
        .toolbar {
            ToolbarItemGroup {
                Button("Sil", systemImage: "trash") { delete(selection) }
                    .disabled(selection.isEmpty)
                    .help("Seçili kelimeleri sil (⌫)")
                Button("Kelime ekle", systemImage: "plus") { isAdding = true }
                    .keyboardShortcut("n")
                    .help("Kelime ekle (⌘N)")
            }
        }
        .sheet(item: $editing) { word in
            NavigationStack {
                WordFormView(mode: .edit(word))
            }
            .frame(width: 460, height: 400)
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                WordFormView(mode: .add) { _ in isAdding = false }
            }
            .frame(width: 460, height: 400)
        }
    }

    private var subtitle: String { DeckSummary.text(for: words) }

    private func word(for id: Word.ID?) -> Word? {
        guard let id else { return nil }
        return words.first { $0.id == id }
    }

    private func delete(_ ids: Set<Word.ID>) {
        for word in words where ids.contains(word.id) {
            context.delete(word)
        }
        context.saveLogging()
        selection.subtract(ids)
    }
}
