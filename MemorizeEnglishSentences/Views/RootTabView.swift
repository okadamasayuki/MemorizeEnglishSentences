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
            Tab("設定", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .task {
            SampleData.seedIfNeeded(context: context)
        }
    }
}
