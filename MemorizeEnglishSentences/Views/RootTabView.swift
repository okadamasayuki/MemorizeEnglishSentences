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
            Tab("単語", systemImage: "textformat.abc") {
                VocabListView()
            }
        }
        .task {
            SampleData.seedIfNeeded(context: context)
            SampleData.applyDefaultStatusIfNeeded(context: context)
            SampleData.splitReadingAndRecallIfNeeded(context: context)
            SampleData.seedBookPhotosIfNeeded(context: context)
            VocabSeedData.seedIfNeeded(context: context)
        }
    }
}
