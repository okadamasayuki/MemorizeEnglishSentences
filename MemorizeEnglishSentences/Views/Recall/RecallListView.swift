import SwiftData
import SwiftUI

struct RecallListView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "recall" },
        sort: \Passage.createdAt, order: .reverse
    ) private var passages: [Passage]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if passages.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "brain",
                        description: Text("右上の + から暗記したい英文を登録しましょう。")
                    )
                } else {
                    List {
                        ForEach(passages) { passage in
                            NavigationLink(value: passage) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rowText(for: passage))
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        statusBadge(passage.memorizationStatus)
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
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationDestination(for: Passage.self) { passage in
                RecallSessionView(passage: passage)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPassageView(purpose: .recall)
            }
        }
    }

    /// 一覧には日本語訳の先頭部分を表示する(和訳がなければタイトル)
    private func rowText(for passage: Passage) -> String {
        let japanese = passage.japaneseFullText.replacingOccurrences(of: "\n", with: " ")
        return japanese.isEmpty ? passage.title : japanese
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            context.delete(passages[offset])
        }
        try? context.save()
    }

    private func statusBadge(_ status: MemorizationStatus) -> some View {
        Image(systemName: status.iconName)
            .font(.footnote)
            .foregroundStyle(status.color)
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 0.8...: .green
        case 0.5..<0.8: .orange
        default: .red
        }
    }
}

extension MemorizationStatus {
    var color: Color {
        switch self {
        case .needsReview: .red
        case .normal: .orange
        case .memorized: .green
        }
    }
}
