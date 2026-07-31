import Foundation

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

        return issues
    }

    private static func addNote(_ issues: inout SentenceIssues, _ note: String) {
        if !issues.notes.contains(note) {
            issues.notes.append(note)
        }
    }
}
