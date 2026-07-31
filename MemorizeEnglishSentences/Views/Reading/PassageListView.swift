import SwiftData
import SwiftUI

struct PassageListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Passage.createdAt, order: .reverse) private var passages: [Passage]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if passages.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "book",
                        description: Text("右上の + から英文を登録しましょう。音声入力でもペーストでも OK です。")
                    )
                } else {
                    List {
                        ForEach(passages) { passage in
                            NavigationLink(value: passage) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(passage.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(passage.blocks.count) 文 ・ \(passage.createdAt.formatted(date: .abbreviated, time: .omitted))")
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
                ReadingView(passage: passage)
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
                AddPassageView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            context.delete(passages[offset])
        }
        try? context.save()
    }
}
