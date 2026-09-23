import Charts
import SwiftData
import SwiftUI

/// Kelimelerin hafıza gücüne göre dağılımı: grafik, dilim dilim sayılar ve ortalama.
struct ProgressChartView: View {
    @Query private var words: [Word]

    private struct Slice: Identifiable {
        let bucket: MemoryStats.Bucket
        let count: Int
        var id: Int { bucket.id }
    }

    private var slices: [Slice] {
        let now = Date.now
        let buckets = words.map { MemoryStats.Bucket($0.memory(at: now)) }
        return MemoryStats.Bucket.allCases.map { bucket in
            Slice(bucket: bucket, count: buckets.count { $0 == bucket })
        }
    }

    private var average: Double? {
        let now = Date.now
        return MemoryStats.average(words.map { $0.memory(at: now) })
    }

    var body: some View {
        Form {
            Section {
                Chart(slices) { slice in
                    BarMark(
                        x: .value("Hafıza", slice.bucket.title),
                        y: .value("Kelime", slice.count)
                    )
                    .foregroundStyle(Self.color(for: slice.bucket))
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 4) {
                        if slice.count > 0 {
                            Text("\(slice.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 200)
                .padding(.vertical, 8)
            } header: {
                if let average {
                    Text("Ortalama hafıza \(MemoryStats.text(average))")
                }
            } footer: {
                Text("Hafıza, bir kelimeyi şu an hatırlama ihtimalin. Zamanla azalır; %90'ın altına inen kelime tekrara gelir. Unutmaya yakınken hatırlamak onu en çok güçlendirir.")
            }

            Section("Dağılım") {
                ForEach(slices) { slice in
                    LabeledContent {
                        Text("\(slice.count)")
                            .monospacedDigit()
                    } label: {
                        HStack(spacing: 10) {
                            MemoryRing(memory: slice.bucket.representative)
                            Text(slice.bucket.title)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("İlerleme")
    }

    private static func color(for bucket: MemoryStats.Bucket) -> Color {
        bucket.representative.map { MemoryStats.Level($0).color } ?? .gray.opacity(0.5)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProgressChartView()
    }
    .modelContainer(PreviewData.container)
}
#endif
