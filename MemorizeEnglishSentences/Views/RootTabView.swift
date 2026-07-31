import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            Tab("音読", systemImage: "book.fill") {
                PassageListView()
            }
            Tab("暗記", systemImage: "brain.fill") {
                RecallListView()
            }
            // 単語カードの束をイメージしたアイコン
            Tab("単語", systemImage: "rectangle.stack.fill") {
                VocabListView()
            }
        }
        .task {
            SampleData.seedIfNeeded(context: context)
            SampleData.applyDefaultStatusIfNeeded(context: context)
            SampleData.splitReadingAndRecallIfNeeded(context: context)
            SampleData.seedBookPhotosIfNeeded(context: context)
            VocabSeedData.seedIfNeeded(context: context)
            // Mac(Claude Code)からの英文修正を取り込み、最新の登録内容を書き出す
            MacBridge.applyCorrectionsIfAny(context: context)
            MacBridge.exportPassages(context: context)
            MacBridge.exportVoices()
        }
    }
}
