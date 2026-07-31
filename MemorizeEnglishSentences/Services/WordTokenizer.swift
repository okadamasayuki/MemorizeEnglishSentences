import Foundation

/// タップ可能な単語トークン。表示用は句読点を保持、翻訳/照合用は小文字化・句読点除去。
struct WordToken: Identifiable, Hashable {
    let id: Int
    let display: String
    let normalized: String
}

enum WordTokenizer {
    static func tokenize(_ text: String) -> [WordToken] {
        text.split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .map { index, word in
                WordToken(id: index, display: String(word), normalized: normalize(String(word)))
            }
    }

    /// 小文字化し、前後の句読点を除去する("I'm" のようなアポストロフィは保持)
    static func normalize(_ word: String) -> String {
        var characters = CharacterSet.alphanumerics
        characters.insert(charactersIn: "'’")
        return word.lowercased()
            .trimmingCharacters(in: characters.inverted)
    }
}
