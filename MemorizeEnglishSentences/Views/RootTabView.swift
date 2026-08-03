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
            SampleData.removeReadingPassagesIfNeeded(context: context)
            SampleData.seedBookPhotosIfNeeded(context: context)
            VocabSeedData.seedIfNeeded(context: context)
            SampleData.cleanupWordCacheIfNeeded(context: context)
            // Mac(Claude Code)からの英文修正・文章追加を取り込み、最新の登録内容を書き出す
            MacBridge.applyCorrectionsIfAny(context: context)
            MacBridge.importPassagesIfAny(context: context)
            MacBridge.importWordSensesIfAny(context: context)
            MacBridge.importSentencePairsIfAny(context: context)
            MacBridge.applyTranslationsIfAny(context: context)
            MacBridge.applyDeletionsIfAny(context: context)
            MacBridge.exportPassages(context: context)
            MacBridge.exportKatakanaReadings(context: context)
            MacBridge.exportVoices()
        }
    }
}
