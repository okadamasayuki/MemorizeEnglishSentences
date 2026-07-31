import SwiftUI

/// ブロックカード。タップで展開(上に英文・下に和訳)、単語タップで意味、長押しで構文解析。
struct BlockCardView: View {
    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWordTap: (String) -> Void
    let onLongPress: () -> Void

    private var tokens: [WordToken] {
        WordTokenizer.tokenize(block.englishText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if isExpanded {
                Divider()
                Text(block.japaneseText ?? "(未翻訳 — ネットワークまたは言語データを確認してください)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button {
                        SpeechSynthesisService.shared.speak(block.englishText)
                    } label: {
                        Label("読み上げ", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                    Text("長押しで構文解析")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onToggle()
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}
