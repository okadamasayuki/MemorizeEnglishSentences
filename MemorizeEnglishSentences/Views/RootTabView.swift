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
        }
        .task {
            SampleData.seedIfNeeded(context: context)
            SampleData.applyDefaultStatusIfNeeded(context: context)
            SampleData.splitReadingAndRecallIfNeeded(context: context)
        }
    }
}
