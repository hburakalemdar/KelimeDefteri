import SwiftData
import SwiftUI

/// Bir kelimenin tüm bilgisi ve ilerlemesi; Kişiler'deki kart gibi. Düzenle formu açar.
struct WordDetailView: View {
    let word: Word
    @Query private var words: [Word]
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.english)
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .textSelection(.enabled)
                        Spacer(minLength: 12)
                        Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                            Speaker.shared.speak(word.english)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                    Text(word.turkish)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.tint)
                        .textSelection(.enabled)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            }

            if !word.definition.isEmpty {
                Section("Anlamı") {
                    Text(word.definition)
                        .textSelection(.enabled)
                }
            }

            if !word.example.isEmpty {
                Section("Kitaptaki Cümle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AttributedString(quoting: word.example, highlighting: word.english))
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !word.source.isEmpty {
                            Label(word.source, systemImage: "book.closed")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if !word.source.isEmpty {
                Section("Kaynak") {
                    Label(word.source, systemImage: "book.closed")
                }
            }

            let related = word.related(in: words)
            if !related.isEmpty {
                Section("İlişkili") {
                    ForEach(related) { other in
                        NavigationLink(value: other) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.english)
                                    .font(.system(.body, design: .serif, weight: .semibold))
                                Text(other.turkish)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section("İlerleme") {
                LabeledContent("Hafıza") {
                    MemoryRing(memory: word.memory(), size: 18, text: .trailing)
                }
                LabeledContent("Sıradaki tekrar", value: Leitner.dueDescription(for: word.dueDate))
                LabeledContent("Tekrar sayısı", value: "\(word.reviewCount)")
                if word.reviewCount > 0 {
                    LabeledContent(
                        "Doğru bilme",
                        value: (Double(word.correctCount) / Double(word.reviewCount))
                            .formatted(.percent.precision(.fractionLength(0)))
                    )
                }
                LabeledContent("Eklendi", value: word.createdAt.formatted(date: .long, time: .omitted))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Düzenle") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                WordFormView(mode: .edit(word))
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewData.container
    let word = try! container.mainContext.fetch(FetchDescriptor<Word>()).first!
    return NavigationStack {
        WordDetailView(word: word)
    }
    .modelContainer(container)
}
#endif
