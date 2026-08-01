import SwiftData
import SwiftUI

/// 設定タブ。Anthropic API キーの入力(Keychain 保存)と、単語の意味の一括事前生成。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var apiKeyInput = ""
    @State private var isConfigured = ClaudeAPIService.isConfigured
    @State private var savedMessage: String?
    @StateObject private var pregenerator = WordSensePregenerator()
    @Query private var senseEntries: [WordSenseCacheEntry]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("生成済みの単語")
                        Spacer()
                        Text("\(senseEntries.count) 語")
                            .foregroundStyle(.secondary)
                    }
                    if pregenerator.isRunning {
                        HStack {
                            ProgressView()
                            Text(pregenerator.progressText ?? "生成中...")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("中断", role: .destructive) {
                                pregenerator.cancel()
                            }
                        }
                    } else {
                        Button("全文章の単語の意味を事前生成") {
                            pregenerator.start(modelContext: context)
                        }
                        .disabled(!isConfigured)
                    }
                    if let result = pregenerator.resultText {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("単語の意味の事前生成")
                } footer: {
                    Text("""
                    登録済みの全英文について、単語(a や the などの機能語を除く)の「その文中での品詞と意味」をまとめて生成し、端末に保存します。以後の長押しは通信なし・追加料金なしで表示されます。

                    ・APIキーの設定が必要です
                    ・1ブロックにつき1回のAPI呼び出しを行います(全体で数分・数百円程度の従量課金)
                    ・生成済みの単語は飛ばすので、途中で中断しても再実行で続きから進みます。新しい文章を取り込んだあとに再実行すると、その分だけ追加生成されます
                    """)
                }
                Section {
                    HStack {
                        Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isConfigured ? .green : .secondary)
                        Text(isConfigured ? "APIキー設定済み" : "APIキー未設定")
                    }
                    SecureField("sk-ant-... を入力", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存") {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainHelper.save(trimmed, for: KeychainHelper.anthropicAPIKey)
                        apiKeyInput = ""
                        isConfigured = true
                        savedMessage = "保存しました"
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isConfigured {
                        Button("キーを削除", role: .destructive) {
                            KeychainHelper.delete(for: KeychainHelper.anthropicAPIKey)
                            isConfigured = false
                            savedMessage = nil
                        }
                    }
                    if let savedMessage {
                        Text(savedMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Anthropic APIキー")
                } footer: {
                    Text("""
                    キーを設定すると、単語を長押ししたときに「その文の中での品詞と意味」を表示できるようになります(例: run が「経営する」の意味で使われている文では、走るではなく経営するを表示)。

                    ・キーは console.anthropic.com で取得できます
                    ・キーはこの端末のKeychainにのみ保存されます
                    ・この機能はネット接続が必要で、APIの従量課金が発生します(1回あたりごくわずか)。一度調べた単語は文ごとに記憶され、再課金されません
                    ・キー未設定でも、従来どおり内蔵辞書とApple翻訳で意味を表示します
                    """)
                }
            }
            .navigationTitle("設定")
        }
    }
}
