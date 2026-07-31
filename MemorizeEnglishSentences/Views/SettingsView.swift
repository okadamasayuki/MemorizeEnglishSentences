import SwiftUI
import Translation

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var savedMessage: String?
    @State private var translationStatusText = ""

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Text("構文解析は Claude API(クラウド)を使用するため、ネットワーク接続と API キーが必要で、利用量に応じて課金されます。同じ文の再解析はキャッシュされ課金されません。それ以外の機能(翻訳・音声入力・読み上げ・暗記)はすべてオフラインで動作します。")
                        .font(.footnote)
                } header: {
                    Text("構文解析について")
                }

                Section {
                    Text(translationStatusText.isEmpty ? "確認中..." : translationStatusText)
                        .font(.footnote)
                    Text("言語データは iOS の 設定 → アプリ → 翻訳 から事前にダウンロードすることもできます。翻訳はシミュレータでは動作しません(実機が必要です)。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("翻訳言語データ")
                }
            }
            .navigationTitle("設定")
        }
        .task {
            apiKey = KeychainHelper.load() ?? ""
            let status = await TranslationAvailability.status()
            translationStatusText = TranslationAvailability.statusMessageJa(status)
        }
    }
}
