import SwiftData
import SwiftUI

struct RecallListView: View {
    @Query(sort: \Passage.createdAt, order: .reverse) private var passages: [Passage]

    var body: some View {
        NavigationStack {
            Group {
                if passages.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "brain",
                        description: Text("音読タブで英文を登録すると、ここで暗記練習ができます。")
                    )
                } else {
                    List(passages) { passage in
                        NavigationLink(value: passage) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(passage.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text("\(passage.blocks.count) 文")
                                    if let latest = passage.latestAttempt {
                                        Text("直近正答率 \(Int(latest.accuracy * 100))%")
                                            .foregroundStyle(accuracyColor(latest.accuracy))
                                    } else {
                                        Text("未挑戦")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("暗記")
            .navigationDestination(for: Passage.self) { passage in
                RecallSessionView(passage: passage)
            }
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 0.8...: .green
        case 0.5..<0.8: .orange
        default: .red
        }
    }
}
