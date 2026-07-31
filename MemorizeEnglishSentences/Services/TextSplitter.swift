import Foundation
import NaturalLanguage

/// 入力テキストをブロックに分割する。
/// 改行で区切られた段落が複数あるとき(写真 OCR や段落貼り付け)は 1 段落 = 1 ブロック、
/// 段落がひとつだけのとき(音声入力など)は 1 文 = 1 ブロック。
enum TextSplitter {
    static func split(_ text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2 {
            // 段落単位でブロック化。短い断片(見出しの読み取り残りなど)は前の段落へ結合
            var merged: [String] = []
            for paragraph in paragraphs {
                if wordCount(paragraph) < 3, !merged.isEmpty {
                    merged[merged.count - 1] += " " + paragraph
                } else {
                    merged.append(paragraph)
                }
            }
            return merged
        }

        // 段落がひとつだけなら従来どおり文単位に分割
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

    /// テキストを文単位に分割する(構文解析でも使用)
    static func sentences(_ text: String) -> [String] {
        splitSentences(text)
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
