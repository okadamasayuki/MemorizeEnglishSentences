import SwiftUI
import SwiftData

@main
struct MemorizeEnglishSentencesApp: App {
    init() {
        // 重さ調査用(原因が取れたら外す)
        PerfLog.startWatchdog()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.light) // 常に白ベースのライト外観で表示
        }
        .modelContainer(for: [
            Passage.self,
            Block.self,
            WordCacheEntry.self,
            WordSenseCacheEntry.self,
            SentencePairCacheEntry.self,
            RecallAttempt.self,
            VocabWord.self,
            Idiom.self,
            LookedUpWord.self,
        ])
    }
}
