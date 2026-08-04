import SwiftUI

/// 単語の意味(日本語)+発音読み上げの bottom sheet。
/// 翻訳処理は親ビュー側で行い、結果だけを受け取って表示する
/// (シート内で translationTask を使うと iOS がクラッシュするため)。
struct WordPopupView: View {
    let word: String
    @ObservedObject var meaning: WordMeaningModel

    private var japanese: String? { meaning.japanese }
    private var failed: Bool { meaning.failed }

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

            // 音声が聞けない場面用の読み方(カタカナ)。熟語(スペースを含む)は規則生成が
            // 不自然になるので出さない
            let pronunciation = word.contains(" ") ? "" : KatakanaPronunciation.katakana(for: word)
            if !pronunciation.isEmpty {
                Text(pronunciation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                SpeechSynthesisService.shared.speak(word)
            } label: {
                Label("発音", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}
