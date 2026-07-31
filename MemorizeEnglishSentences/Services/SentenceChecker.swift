import Foundation
import NaturalLanguage

/// 英文チェックの結果。
/// suspiciousWords はオレンジ表示する語、notes はカード内に出す指摘文。
struct SentenceIssues {
    var suspiciousWords: Set<String> = []
    var notes: [String] = []

    var isEmpty: Bool { suspiciousWords.isEmpty && notes.isEmpty }
}

/// スペルに加えて、OCR ミス・タイプミスにありがちなパターンを検査する。完全オフライン。
enum SentenceChecker {
    /// 母音字で始まっても "a" が正しい語(発音が子音で始まる)
    private static let aOkPrefixes = ["one", "once", "uni", "use", "user", "usual", "euro", "utility", "ufo"]
    /// 子音字で始まっても "an" が正しい語(発音が母音で始まる)
    private static let anOkPrefixes = ["hour", "honest", "honor", "honour", "heir"]

    @MainActor
    static func check(_ text: String) -> SentenceIssues {
        var issues = SentenceIssues()

        // 1. スペルチェック
        for word in SentenceValidator.misspelledWords(in: text) {
            issues.suspiciousWords.insert(word.lowercased())
        }

        let words = WordTokenizer.tokenize(text).map(\.normalized)

        // 2. 同じ語の連続(the the など)
        for index in words.indices.dropFirst()
        where !words[index].isEmpty && words[index] == words[index - 1] {
            issues.suspiciousWords.insert(words[index])
            addNote(&issues, "同じ語が連続")
        }

        // 3. 数字と文字が混ざった語(wor1d など。OCR ミスに多い)
        for word in words
        where word.rangeOfCharacter(from: .decimalDigits) != nil
            && word.rangeOfCharacter(from: .letters) != nil {
            issues.suspiciousWords.insert(word)
            addNote(&issues, "数字が混ざった語")
        }

        // 4. a / an の使い分け
        for index in words.indices.dropLast() {
            let article = words[index]
            let next = words[index + 1]
            guard article == "a" || article == "an", let first = next.first else { continue }
            let startsWithVowelLetter = "aeiou".contains(first)
            if article == "a", startsWithVowelLetter,
               !aOkPrefixes.contains(where: { next.hasPrefix($0) }) {
                addNote(&issues, "a/an の使い分けを確認")
            }
            if article == "an",
               !startsWithVowelLetter,
               !anOkPrefixes.contains(where: { next.hasPrefix($0) }) {
                addNote(&issues, "a/an の使い分けを確認")
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 5. 文頭が小文字
        if let first = trimmed.first, first.isLowercase, first.isLetter {
            addNote(&issues, "文頭が小文字")
        }

        // 6. 文末に句読点がない
        if let last = trimmed.last, !".!?\"'”’)".contains(last) {
            addNote(&issues, "文末に句読点がない")
        }

        // 7. 引用符・括弧の閉じ忘れ
        if trimmed.filter({ $0 == "\"" }).count % 2 != 0 {
            addNote(&issues, "引用符が閉じていない")
        }
        if trimmed.filter({ $0 == "(" }).count != trimmed.filter({ $0 == ")" }).count {
            addNote(&issues, "括弧が閉じていない")
        }

        // 8. 単語は正しくても文として成立していないケース(品詞解析で検査)
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            checkStructure(String(text[range]), issues: &issues)
            return true
        }

        return issues
    }

    /// 品詞タグ付けを使った文構造の検査。
    /// 動詞の欠落・名詞の羅列・機能語(冠詞/前置詞/代名詞など)の欠如を見る。
    /// 短い語句(5 語以下)は名詞句の見出しなどがありうるため対象外。
    private static func checkStructure(_ sentence: String, issues: inout SentenceIssues) {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var tags: [NLTag] = []
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            if let tag { tags.append(tag) }
            return true
        }

        // 名詞が 5 語以上連続 → 単語の羅列の可能性(文の長さに関わらず検査)
        var run = 0
        var maxRun = 0
        for tag in tags {
            if tag == .noun {
                run += 1
                maxRun = max(maxRun, run)
            } else {
                run = 0
            }
        }
        if maxRun >= 5 {
            addNote(&issues, "名詞の羅列になっている可能性")
        }

        guard tags.count >= 6 else { return }

        // 動詞が 1 つもない
        if !tags.contains(.verb) {
            addNote(&issues, "動詞が見つからない(文として不完全かも)")
        }

        // 機能語が極端に少ない(正常な英文はおおむね 3〜6 割が機能語)
        let functionTags: Set<NLTag> = [.determiner, .preposition, .pronoun, .conjunction, .particle]
        let functionCount = tags.filter { functionTags.contains($0) }.count
        if Double(functionCount) / Double(tags.count) < 0.2 {
            addNote(&issues, "文の形になっていない可能性")
        }
    }

    private static func addNote(_ issues: inout SentenceIssues, _ note: String) {
        if !issues.notes.contains(note) {
            issues.notes.append(note)
        }
    }
}
