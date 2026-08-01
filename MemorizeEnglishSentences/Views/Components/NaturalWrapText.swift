import SwiftUI

/// 行末まで詰めて折り返す日本語テキスト表示。
/// iOS の「単語のまとまり優先」改行は OS 側で強制されて無効化できないため、
/// 文字単位で自前レイアウト(FlowLayout)して確実に行末まで詰める。
/// 句読点などは直前の文字とまとめて、行頭に来ないようにする。
struct NaturalWrapText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, paragraph in
                FlowLayout(spacing: 0, lineSpacing: 6) {
                    ForEach(Array(chunks(of: String(paragraph)).enumerated()), id: \.offset) { _, chunk in
                        Text(chunk)
                            .font(.title3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 行頭に来てほしくない記号は直前の文字に、英数字の連続は 1 かたまりにする
    private func chunks(of paragraph: String) -> [String] {
        let leadingForbidden: Set<Character> = [
            "。", "、", ",", ".", "!", "?", "!", "?", "」", "』", ")", ")",
            "ー", "…", "っ", "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
            "ッ", "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ",
        ]
        var result: [String] = []
        for character in paragraph {
            let isASCIIWordChar = character.isASCII && (character.isLetter || character.isNumber)
            if let last = result.last {
                // 英単語・数値は分割しない
                if isASCIIWordChar, let lastChar = last.last, lastChar.isASCII,
                   lastChar.isLetter || lastChar.isNumber {
                    result[result.count - 1] = last + String(character)
                    continue
                }
                if leadingForbidden.contains(character) {
                    result[result.count - 1] = last + String(character)
                    continue
                }
            }
            result.append(String(character))
        }
        return result
    }
}
