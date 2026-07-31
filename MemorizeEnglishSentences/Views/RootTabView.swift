import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

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
            SampleData.applyDefaultStatusIfNeeded(context: context)
            SampleData.splitReadingAndRecallIfNeeded(context: context)
            StudyTimeTracker.shared.sessionStarted()
        }
        // アプリを使っている間だけ勉強時間を計測する
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                StudyTimeTracker.shared.sessionStarted()
            default:
                StudyTimeTracker.shared.sessionEnded()
            }
        }
    }
}
