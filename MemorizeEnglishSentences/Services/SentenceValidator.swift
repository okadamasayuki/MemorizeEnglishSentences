import UIKit

/// OCR の読み取りミスなどで英文として不自然な語が混ざっていないかを
/// iOS 内蔵のスペルチェッカーで検査する(完全オフライン)。
enum SentenceValidator {
    /// 英単語として認識できない語を返す(空なら問題なし)
    @MainActor
    static func misspelledWords(in text: String) -> [String] {
        let checker = UITextChecker()
        let nsText = text as NSString
        var results: [String] = []
        var location = 0

        while location < nsText.length {
            let range = checker.rangeOfMisspelledWord(
                in: text,
                range: NSRange(location: 0, length: nsText.length),
                startingAt: location,
                wrap: false,
                language: "en"
            )
            guard range.location != NSNotFound else { break }
            let word = nsText.substring(with: range)
            // 数字のみ・1 文字などは対象外
            if word.count >= 2, word.rangeOfCharacter(from: .letters) != nil {
                results.append(word)
            }
            location = range.location + range.length
        }
        return results
    }

    /// OCR の綴りミスを内蔵スペルチェッカーで自動補正する。
    /// 誤りと判定された語だけを、確信度の高い候補(先頭文字が同じで編集距離が近い)に
    /// 置き換える。原文の大文字小文字パターンは保つ。
    @MainActor
    static func autocorrected(_ text: String) -> String {
        let checker = UITextChecker()
        let nsText = NSMutableString(string: text)
        var location = 0

        while location < nsText.length {
            let range = checker.rangeOfMisspelledWord(
                in: nsText as String,
                range: NSRange(location: 0, length: nsText.length),
                startingAt: location,
                wrap: false,
                language: "en"
            )
            guard range.location != NSNotFound else { break }
            let word = nsText.substring(with: range)

            if word.count >= 2,
               let guesses = checker.guesses(
                   forWordRange: range, in: nsText as String, language: "en"
               ),
               let best = guesses.first(where: { isConfidentCorrection(from: word, to: $0) }) {
                let replacement = matchCase(of: word, to: best)
                nsText.replaceCharacters(in: range, with: replacement)
                location = range.location + (replacement as NSString).length
            } else {
                location = range.location + range.length
            }
        }
        return nsText as String
    }

    /// 自動補正してよい候補か(先頭文字が同じ・長さが近い・編集距離が小さい)
    private static func isConfidentCorrection(from word: String, to guess: String) -> Bool {
        guard guess.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let a = word.lowercased()
        let b = guess.lowercased()
        guard a.first == b.first else { return false }
        guard abs(a.count - b.count) <= 1 else { return false }
        return editDistance(a, b) <= 2
    }

    /// 元の単語の大文字小文字パターンを補正後の語に反映する
    private static func matchCase(of original: String, to replacement: String) -> String {
        if original == original.uppercased() { return replacement.uppercased() }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var dp = Array(0...y.count)
        for i in 1...max(1, x.count) where !x.isEmpty {
            var prev = dp[0]
            dp[0] = i
            for j in 1...y.count {
                let temp = dp[j]
                dp[j] = x[i - 1] == y[j - 1] ? prev : min(prev, dp[j], dp[j - 1]) + 1
                prev = temp
            }
        }
        return dp[y.count]
    }
}
