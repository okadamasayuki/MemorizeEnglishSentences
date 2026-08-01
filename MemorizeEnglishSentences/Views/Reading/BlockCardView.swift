import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると和訳を表示/非表示。
/// 和訳は英文1文ごと、その直下に対応する和訳が出るよう交互に並べる。
/// 単語長押しで意味を表示する。
struct BlockCardView: View {
    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    /// 長押しされた単語と、ブロック内で同じ単語の何回目の出現か(0始まり)
    let onWordTap: (String, Int) -> Void
    /// 英文↔和訳の文ごとのペア(nil ならブロック全体を1文として扱う)
    var sentencePairs: [SentencePairLookup.Pair]? = nil

    /// ブロック全体のトークン(単語長押しの出現番号はここを基準に数える)
    private var tokens: [WordToken] {
        WordTokenizer.tokenize(block.englishText)
    }

    /// 「文ごとのトークン列 + その和訳」に分けたグループ。
    /// ペアが無いブロックは、全文を1グループ(和訳はブロック全文)として扱う。
    private var groups: [(tokens: [WordToken], ja: String)] {
        let full = tokens
        guard let pairs = sentencePairs, !pairs.isEmpty else {
            return [(full, block.japaneseText ?? "")]
        }
        var result: [(tokens: [WordToken], ja: String)] = []
        var index = 0
        for pair in pairs {
            let count = WordTokenizer.tokenize(pair.en).count
            let end = min(index + count, full.count)
            result.append((Array(full[index..<end]), pair.ja))
            index = end
        }
        // トークン数が万一合わないときは、余りを最後のグループへ足す
        if index < full.count, !result.isEmpty {
            result[result.count - 1].tokens.append(contentsOf: full[index...])
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: isExpanded ? 12 : 6) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        FlowLayout(spacing: 4, lineSpacing: 6) {
                            ForEach(group.tokens) { token in
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
                        if isExpanded, !group.ja.isEmpty {
                            Text(group.ja)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                // カスタムレイアウトと縦積みしても1行に切り詰められないよう、
                                // 必要な行数の高さを必ず確保する
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
