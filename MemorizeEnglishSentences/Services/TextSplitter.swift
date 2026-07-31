import Foundation
import NaturalLanguage

/// 入力テキストを 1 文 = 1 ブロックに分割する
enum TextSplitter {
    static func split(_ text: String) -> [String] {
        // 空行があれば先に段落分割
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var sentences: [String] = []
        for paragraph in paragraphs {
            sentences.append(contentsOf: splitSentences(paragraph))
        }

        // 3 語未満の断片は前ブロックへ結合
        var merged: [String] = []
        for sentence in sentences {
            if wordCount(sentence) < 3, !merged.isEmpty {
                merged[merged.count - 1] += " " + sentence
            } else {
                merged.append(sentence)
            }
        }

        // 句読点が全く無い長文は約 25 語毎のチャンク分割にフォールバック
        return merged.flatMap { chunkIfNeeded($0) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                result.append(sentence)
            }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func chunkIfNeeded(_ sentence: String, maxWords: Int = 40, chunkSize: Int = 25) -> [String] {
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maxWords else { return [sentence] }
        return stride(from: 0, to: words.count, by: chunkSize).map { start in
            words[start..<min(start + chunkSize, words.count)].joined(separator: " ")
        }
    }
}
