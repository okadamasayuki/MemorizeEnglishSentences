import SwiftUI
import SwiftData

@main
struct MemorizeEnglishSentencesApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            Passage.self,
            Block.self,
            WordCacheEntry.self,
            RecallAttempt.self,
            SyntaxCacheEntry.self,
        ])
    }
}
