import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると日本語訳を表示/非表示。
/// 単語タップで意味を表示。
struct BlockCardView: View {
    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWordTap: (String) -> Void

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
        // どこまで読んだかの目印(しおり)
        .overlay(alignment: .topTrailing) {
            if block.isMarked {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onToggle()
        }
    }
}
