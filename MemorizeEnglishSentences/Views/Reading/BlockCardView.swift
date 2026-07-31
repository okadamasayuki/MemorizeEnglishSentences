import SwiftUI

/// ブロックカード。英文は常に表示し、カードをタップすると日本語訳を表示/非表示。
/// 単語タップで意味を表示。スピーカーで全文読み上げ(読んでいる単語は太字)。
struct BlockCardView: View {
    @ObservedObject private var playback = SpeechSynthesisService.shared

    let block: Block
    let isExpanded: Bool
    let onToggle: () -> Void
    let onWordTap: (String) -> Void

    private var tokens: [WordToken] {
        WordTokenizer.tokenize(block.englishText)
    }

    /// 各トークンの原文中の文字範囲(読み上げハイライト用)
    private var tokenRanges: [NSRange] {
        let nsText = block.englishText as NSString
        var result: [NSRange] = []
        var cursor = 0
        for token in tokens {
            let searchRange = NSRange(location: cursor, length: nsText.length - cursor)
            let range = nsText.range(of: token.display, options: [], range: searchRange)
            if range.location == NSNotFound {
                result.append(NSRange(location: NSNotFound, length: 0))
            } else {
                result.append(range)
                cursor = range.location + range.length
            }
        }
        return result
    }

    private var isSpeakingThisBlock: Bool {
        playback.speakingBlockID == block.persistentModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                FlowLayout(spacing: 4, lineSpacing: 6) {
                    ForEach(tokens) { token in
                        Text(token.display)
                            .font(.body)
                            // 読み上げ中の単語は太い下線(オーバーレイなのでレイアウトは動かない)
                            .overlay(alignment: .bottom) {
                                if isSpokenToken(token.id) {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(height: 3)
                                        .offset(y: 3)
                                }
                            }
                            .onTapGesture {
                                let word = token.normalized.isEmpty ? token.display : token.normalized
                                onWordTap(word)
                            }
                    }
                }

                VStack(spacing: 10) {
                    // 全文読み上げ(読み上げ中は停止ボタン)
                    Button {
                        if isSpeakingThisBlock {
                            playback.stop()
                        } else {
                            playback.speakBlock(block.englishText, id: block.persistentModelID)
                        }
                    } label: {
                        Image(systemName: isSpeakingThisBlock ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(isSpeakingThisBlock ? Color.red : Color.accentColor)
                    }
                    .buttonStyle(.borderless)

                    if block.isMarked {
                        Image(systemName: "bookmark.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
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
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onToggle()
        }
    }

    /// いま読み上げている単語かどうか
    private func isSpokenToken(_ index: Int) -> Bool {
        guard isSpeakingThisBlock,
              let range = playback.speakingRange,
              index < tokenRanges.count else { return false }
        let tokenRange = tokenRanges[index]
        guard tokenRange.location != NSNotFound else { return false }
        return NSIntersectionRange(range, tokenRange).length > 0
    }
}
