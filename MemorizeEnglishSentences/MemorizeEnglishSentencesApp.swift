import SwiftUI
import SwiftData

@main
struct MemorizeEnglishSentencesApp: App {
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
            RecallAttempt.self,
            VocabWord.self,
        ])
    }
}
