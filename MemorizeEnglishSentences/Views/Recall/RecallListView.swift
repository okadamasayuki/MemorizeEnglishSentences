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
                            HStack(spacing: 8) {
                                statusBadge(passage.memorizationStatus)
                                Text(rowText(for: passage))
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            // 見えない NavigationLink でシェブロンなしのカード遷移にする
                            .background(
                                NavigationLink(value: passage) { EmptyView() }
                                    .opacity(0)
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            // 一覧では明示的にタブバーを表示(戻り遷移と同時に復元させる)
            .toolbar(.visible, for: .tabBar)
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
