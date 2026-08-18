import Foundation

/// タップ可能な単語トークン。表示用は句読点を保持、翻訳/照合用は小文字化・句読点除去。
struct WordToken: Identifiable, Hashable {
    let id: Int
    let display: String
    let normalized: String
}

enum WordTokenizer {
    /// 同じ英文を何度もトークン化しないためのメモ(一覧のスクロール中は
    /// 同じブロックが描画のたびにトークン化されるため、ここが重さの主因になる)。
    private static var cache: [String: [WordToken]] = [:]
    private static let cacheLock = NSLock()

    static func tokenize(_ text: String) -> [WordToken] {
        cacheLock.lock()
        if let hit = cache[text] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let tokens = text.split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .map { index, word in
                WordToken(id: index, display: String(word), normalized: normalize(String(word)))
            }

        cacheLock.lock()
        if cache.count > 8000 { cache.removeAll(keepingCapacity: true) }
        cache[text] = tokens
        cacheLock.unlock()
        return tokens
    }

    /// トークンが「同じ単語の何回目の出現か」(0始まり)。
    /// 同じ単語がブロック内で別の意味で使われる場合の訳し分けキーに使う
    static func occurrence(of token: WordToken, in tokens: [WordToken]) -> Int {
        let word = token.normalized.isEmpty ? token.display : token.normalized
        return tokens.prefix(token.id).count { candidate in
            (candidate.normalized.isEmpty ? candidate.display : candidate.normalized) == word
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
