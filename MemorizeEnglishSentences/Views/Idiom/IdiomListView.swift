import SwiftData
import SwiftUI

/// 熟語タブ。熟語+例文を表示し、カードをタップすると意味(和訳)を表示する暗記カード。
/// 「覚えた/要復習」で管理し、要復習だけに絞り込める。
struct IdiomListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Idiom.number) private var idioms: [Idiom]
    @AppStorage("idiomReviewOnly") private var reviewOnly = false
    /// 意味を表示中のカード
    @State private var revealed: Set<Int> = []

    private var shown: [Idiom] {
        reviewOnly ? idioms.filter { $0.memorizationStatus == .needsReview } : idioms
    }

    var body: some View {
        NavigationStack {
            Group {
                if idioms.isEmpty {
                    ContentUnavailableView(
                        "熟語がまだありません",
                        systemImage: "text.book.closed",
                        description: Text("写真から熟語を取り込むと、ここでカード学習できます。")
                    )
                } else {
                    List {
                        ForEach(shown) { idiom in
                            card(idiom)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("熟語")
            .toolbar {
                if !idioms.isEmpty {
                    ToolbarItem(placement: .principal) {
                        Text("\(idioms.count)語中 覚えた \(memorizedCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            reviewOnly.toggle()
                        } label: {
                            Image(systemName: reviewOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(reviewOnly ? Color.orange : Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var memorizedCount: Int {
        idioms.filter { $0.memorizationStatus == .memorized }.count
    }

    @ViewBuilder
    private func card(_ idiom: Idiom) -> some View {
        let isRevealed = revealed.contains(idiom.number)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(idiom.phrase)
                    .font(.title3.bold())
                Spacer()
                if idiom.memorizationStatus != .normal {
                    Image(systemName: idiom.memorizationStatus.iconName)
                        .foregroundStyle(idiom.memorizationStatus == .memorized ? .green : .orange)
                }
            }
            // 例文(熟語部分を太字にする)
            exampleText(idiom)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if isRevealed {
                Divider()
                Text(idiom.meaning)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                if !idiom.exampleJa.isEmpty {
                    Text(idiom.exampleJa)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // 覚えた / 要復習 の切り替え
                HStack(spacing: 8) {
                    ForEach([MemorizationStatus.needsReview, .normal, .memorized]) { status in
                        Button {
                            idiom.memorizationStatus = (idiom.memorizationStatus == status) ? .normal : status
                            try? context.save()
                        } label: {
                            Label(status.labelJa, systemImage: status.iconName)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Capsule().fill(color(status).opacity(idiom.memorizationStatus == status ? 0.25 : 0.08)))
                                .foregroundStyle(color(status))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            } else {
                Text("タップして意味を表示")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isRevealed { revealed.remove(idiom.number) } else { revealed.insert(idiom.number) }
            }
        }
    }

    private func color(_ status: MemorizationStatus) -> Color {
        switch status {
        case .needsReview: .orange
        case .normal: .secondary
        case .memorized: .green
        }
    }

    /// 例文中の熟語(中身のある語)を太字にして表示する
    private func exampleText(_ idiom: Idiom) -> Text {
        let keywords = Set(
            idiom.phrase.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 3 }  // A/B/to/on などは太字にしない
        )
        var result = Text("")
        for (i, word) in idiom.example.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            let bare = word.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
            let piece = Text(String(word))
            result = result + (i == 0 ? piece : Text(" ") + piece).bold(shouldBold(bare, keywords))
        }
        return result
    }

    private func shouldBold(_ bare: String, _ keywords: Set<String>) -> Bool {
        keywords.contains { bare == $0 || bare.hasPrefix($0) || $0.hasPrefix(bare) }
    }
}

private extension Text {
    func bold(_ on: Bool) -> Text { on ? self.bold() : self }
}
