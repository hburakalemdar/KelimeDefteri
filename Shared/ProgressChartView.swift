import Charts
import SwiftData
import SwiftUI

/// Kelimelerin Leitner kutularına dağılımı: grafik ve kutu kutu sayılar.
struct ProgressChartView: View {
    @Query private var words: [Word]

    private struct Bucket: Identifiable {
        let box: Int
        let count: Int
        var id: Int { box }
    }

    private var buckets: [Bucket] {
        (0...Leitner.maxBox).map { box in
            Bucket(box: box, count: words.count { min(max($0.box, 0), Leitner.maxBox) == box })
        }
    }

    var body: some View {
        Form {
            Section {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Kutu", "\(bucket.box)"),
                        y: .value("Kelime", bucket.count)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.35 + 0.65 * Double(bucket.box) / Double(Leitner.maxBox)))
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 4) {
                        if bucket.count > 0 {
                            Text("\(bucket.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxisLabel("Kutu", alignment: .center)
                .frame(height: 200)
                .padding(.vertical, 8)
            } footer: {
                Text("Bildiğin kelime bir üst kutuya çıkar ve daha seyrek sorulur; bilemediğin kelime yeni kutusuna döner.")
            }

            Section("Kutular") {
                ForEach(buckets) { bucket in
                    LabeledContent {
                        Text("\(bucket.count)")
                            .monospacedDigit()
                    } label: {
                        HStack(spacing: 10) {
                            BoxRing(box: bucket.box)
                            Text("Kutu \(bucket.box)")
                            Text(Leitner.boxDescription(bucket.box))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("İlerleme")
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
