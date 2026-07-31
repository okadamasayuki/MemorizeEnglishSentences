import SwiftData
import SwiftUI

struct RecallListView: View {
    @Environment(\.modelContext) private var context
    private static let sortOrder: [SortDescriptor<Passage>] = [
        SortDescriptor(\Passage.sortIndex),
        SortDescriptor(\Passage.createdAt, order: .reverse),
    ]
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "recall" },
        sort: sortOrder
    ) private var passages: [Passage]
    @State private var showingAdd = false
    @State private var path: [Passage] = []
    /// 覚えた!を一覧から隠す(アプリを閉じても記憶する)
    @AppStorage("hideMemorized") private var hideMemorized = false

    private var visiblePassages: [Passage] {
        hideMemorized ? passages.filter { $0.memorizationStatus != .memorized } : passages
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if passages.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "brain",
                        description: Text("右上の + から暗記したい英文を登録しましょう。")
                    )
                } else {
                    List {
                        ForEach(visiblePassages) { passage in
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
                            // 長押しドラッグ時はグレーのカード部分だけを持ち上げる
                            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: delete)
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
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
                // 覚えた!の表示/非表示(緑=表示中、グレー=非表示中)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hideMemorized.toggle()
                        }
                    } label: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(hideMemorized ? Color(.systemGray3) : Color.green)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPassageView(purpose: .recall)
            }
        }
        // 詳細画面(階層あり)ではタブバーを隠す。
        // iOS 18 では画面側の指定が効かないことがあるため、タブのルートで出し分ける
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.2), value: path.isEmpty)
    }

    /// 一覧には日本語訳の先頭部分を表示する(和訳がなければタイトル)
    private func rowText(for passage: Passage) -> String {
        let japanese = passage.japaneseFullText.replacingOccurrences(of: "\n", with: " ")
        return japanese.isEmpty ? passage.title : japanese
    }

    /// 長押しドラッグでの並べ替え。覚えた!を非表示中でも、
    /// 隠れている項目の位置は保ったまま表示中の項目だけ並べ替える
    private func move(from source: IndexSet, to destination: Int) {
        var visible = visiblePassages
        visible.move(fromOffsets: source, toOffset: destination)

        var all = passages
        if hideMemorized {
            var it = visible.makeIterator()
            for i in all.indices where all[i].memorizationStatus != .memorized {
                if let next = it.next() { all[i] = next }
            }
        } else {
            all = visible
        }
        for (index, passage) in all.enumerated() {
            passage.sortIndex = index
        }
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            context.delete(visiblePassages[offset])
        }
        try? context.save()
    }

    @ViewBuilder
    private func statusBadge(_ status: MemorizationStatus) -> some View {
        // 「どちらでもない」はアイコンなし
        if status != .normal {
            Image(systemName: status.iconName)
                .font(.footnote)
                .foregroundStyle(status.color)
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
