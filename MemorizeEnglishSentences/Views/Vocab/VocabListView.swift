import SwiftData
import SwiftUI

/// 単語タブ。音声教材から抽出した英語フレーズと和訳のリスト。
/// カードをタップすると和訳を表示/非表示。単語の長押しで意味ポップアップ。
struct VocabListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VocabWord.index) private var words: [VocabWord]

    @State private var expandedIDs: Set<PersistentIdentifier> = []

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "単語がまだありません",
                        systemImage: "rectangle.stack"
                    )
                } else {
                    List {
                        ForEach(words) { word in
                            wordRow(word)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        context.delete(word)
                                        try? context.save()
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private func wordRow(_ word: VocabWord) -> some View {
        let isExpanded = expandedIDs.contains(word.persistentModelID)
        return VStack(alignment: .leading, spacing: 8) {
            Text(word.english)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isExpanded {
                Text(word.japanese)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedIDs.remove(word.persistentModelID)
                } else {
                    expandedIDs.insert(word.persistentModelID)
                }
            }
        }
    }
}
