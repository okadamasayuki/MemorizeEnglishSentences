import SwiftUI

/// 単語の意味(日本語)+発音読み上げの bottom sheet。
/// 翻訳処理は親ビュー側で行い、結果だけを受け取って表示する
/// (シート内で translationTask を使うと iOS がクラッシュするため)。
struct WordPopupView: View {
    let word: String
    @ObservedObject var meaning: WordMeaningModel
    @Environment(\.openURL) private var openURL

    private var japanese: String? { meaning.japanese }
    private var failed: Bool { meaning.failed }

    /// URL 用にエンコードした単語
    private var encodedWord: String {
        word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
    }

    /// Google 翻訳 iOS アプリ(英→日)を開く URL スキーム
    private var googleTranslateAppURL: URL? {
        URL(string: "googletranslate://?sl=en&tl=ja&text=\(encodedWord)")
    }

    /// アプリ未インストール時のフォールバック(ブラウザ版)
    private var googleTranslateWebURL: URL? {
        URL(string: "https://translate.google.com/?sl=en&tl=ja&text=\(encodedWord)&op=translate")
    }

    /// Google 翻訳を開く。まずアプリ、ダメならブラウザ
    private func openGoogleTranslate() {
        guard let appURL = googleTranslateAppURL else {
            if let web = googleTranslateWebURL { openURL(web) }
            return
        }
        openURL(appURL) { accepted in
            if !accepted, let web = googleTranslateWebURL { openURL(web) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // 英単語の右に日本語訳を表示
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word)
                    .font(.title2.bold())
                if let japanese {
                    Text(":")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(japanese)
                        .font(.title3)
                } else if failed {
                    Text("(翻訳できませんでした)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }

            HStack(spacing: 12) {
                Button {
                    SpeechSynthesisService.shared.speak(word)
                } label: {
                    Label("発音", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                // この単語を入れた Google 翻訳アプリをワンタップで開く(無ければブラウザ)
                Button {
                    openGoogleTranslate()
                } label: {
                    Label("Google翻訳", systemImage: "character.bubble")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }
}
