import SwiftUI

/// ブロックカード。英文と和訳を常に表示。単語タップで意味、長押しで構文解析。
struct BlockCardView: View {
    let block: Block
    let onWordTap: (String) -> Void
    let onLongPress: () -> Void

    private var tokens: [WordToken] {
        WordTokenizer.tokenize(block.englishText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                FlowLayout(spacing: 4, lineSpacing: 6) {
                    ForEach(tokens) { token in
                        Text(token.display)
                            .font(.body)
                            .onTapGesture {
                                let word = token.normalized.isEmpty ? token.display : token.normalized
                                onWordTap(word)
                            }
                    }
                }
                Button {
                    SpeechSynthesisService.shared.speak(block.englishText)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }

            Text(block.japaneseText ?? "(未翻訳 — ネットワークまたは言語データを確認してください)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onLongPressGesture {
            onLongPress()
        }
    }
}
