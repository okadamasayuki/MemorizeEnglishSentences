import SwiftUI
import Translation

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MonsterEggView()
                }

                Section {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存") {
                        KeychainHelper.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        savedMessage = "保存しました"
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if KeychainHelper.hasKey {
                        Button("キーを削除", role: .destructive) {
                            KeychainHelper.delete()
                            apiKey = ""
                            savedMessage = "削除しました"
                        }
                    }
                    if let savedMessage {
                        Text(savedMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Anthropic API キー")
                } footer: {
                    Text("構文解析(文の長押し)に使用します。console.anthropic.com で取得できます。キーは端末の Keychain に保存されます。")
                }
            }
        }
        .task {
            apiKey = KeychainHelper.load() ?? ""
        }
    }
}
