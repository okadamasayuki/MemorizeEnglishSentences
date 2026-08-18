import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    /// 選択中のタブ
    @State private var selection = 0
    /// 音読タブが再タップされた回数(前回位置に戻すシグナル)
    @State private var readingReselect = 0

    var body: some View {
        TabView(selection: Binding(
            get: { selection },
            set: { newValue in
                // すでに音読タブにいる状態で音読タブを再タップした
                if newValue == 0, selection == 0 {
                    readingReselect += 1
                }
                selection = newValue
            }
        )) {
            Tab("音読", systemImage: "book.fill", value: 0) {
                PassageListView(reselectSignal: readingReselect)
            }
            // 例文を音読しながら熟語を覚えるタブ
            Tab("熟語", systemImage: "text.book.closed.fill", value: 3) {
                IdiomListView()
            }
            Tab("暗記", systemImage: "brain.fill", value: 1) {
                RecallListView()
            }
            // アプリへの改善要望を書き留めて、Mac の Claude Code へ送るタブ
            Tab("改善", systemImage: "lightbulb", value: 4) {
                ImprovementListView()
            }
        }
        // 動作検証用: memoeng://tab/3 のようなURLでタブを切り替えられる
        // (シミュレーターで切替の重さを自動計測するのに使う)
        .onOpenURL { url in
            if url.host() == "tab", let value = Int(url.lastPathComponent) {
                selection = value
            }
        }
        .task {
            // 一度きりの初期化・移行(フラグ済みなら即 return で軽い)
            SampleData.seedIfNeeded(context: context)
            SampleData.applyDefaultStatusIfNeeded(context: context)
            SampleData.splitReadingAndRecallIfNeeded(context: context)
            SampleData.removeReadingPassagesIfNeeded(context: context)
            SampleData.seedBookPhotosIfNeeded(context: context)
            SampleData.cleanupWordCacheIfNeeded(context: context)
            // 単語タブは廃止。単語データを一度だけ削除する(他タブには影響なし)
            SampleData.removeVocabIfNeeded(context: context)
            // 履歴タブも廃止。履歴データを一度だけ削除する
            SampleData.removeLookupHistoryIfNeeded(context: context)
            // Mac(Claude Code)からの取り込み(ファイルが無ければ即 return で軽い)
            MacBridge.applyCorrectionsIfAny(context: context)
            MacBridge.importPassagesIfAny(context: context)
            MacBridge.importIdiomsIfAny(context: context)
            MacBridge.importWordSensesIfAny(context: context)
            MacBridge.importSentencePairsIfAny(context: context)
            MacBridge.applyTranslationsIfAny(context: context)
            MacBridge.applyDeletionsIfAny(context: context)

            // 最新状態の書き出し(全ブロック)は重いので、起動直後の操作を
            // ブロックしないよう別スレッドで後回しに実行する
            let container = context.container
            Task.detached(priority: .utility) {
                // 起動直後の操作(スクロール・再生開始)と競合しないよう一呼吸置いてから書き出す
                try? await Task.sleep(for: .seconds(15))
                let bg = ModelContext(container)
                MacBridge.exportPassages(context: bg)
                MacBridge.exportIdioms(context: bg)
                // 学習状態のバックアップ(万一の消失時に復元するための保険)
                MacBridge.exportLearningState(context: bg)
            }
        }
    }
}
