import SwiftUI

struct RootTabView: View {
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
    }
}
