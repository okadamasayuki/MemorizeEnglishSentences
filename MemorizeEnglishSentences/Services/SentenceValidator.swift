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
}
