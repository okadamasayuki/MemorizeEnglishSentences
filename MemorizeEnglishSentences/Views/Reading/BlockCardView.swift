import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると日本語訳を表示/非表示。
/// 単語長押しで意味を表示する。
struct BlockCardView: View {
    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    /// 長押しされた単語と、ブロック内で同じ単語の何回目の出現か(0始まり)
    let onWordTap: (String, Int) -> Void

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
                            .foregroundStyle(Color.primary)
                            // 長押しで単語の意味を表示(タップはカードの和訳切り替えに回す)
                            .onLongPressGesture {
                                let word = token.normalized.isEmpty ? token.display : token.normalized
                                onWordTap(word, WordTokenizer.occurrence(of: token, in: tokens))
                            }
                    }
                }

                if block.isMarked {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(width: 24, height: 24)
                }
            }

            if isExpanded {
                Text(block.japaneseText ?? "(未翻訳 — ネットワークまたは言語データを確認してください)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
