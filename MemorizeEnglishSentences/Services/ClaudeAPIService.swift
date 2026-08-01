import Foundation

/// 文中での単語の意味(文脈対応)
struct WordSense: Codable {
    let posJa: String
    let meaningJa: String

    enum CodingKeys: String, CodingKey {
        case posJa = "pos_ja"
        case meaningJa = "meaning_ja"
    }
}

enum ClaudeAPIError: Error {
    case noAPIKey
    case httpError(Int)
    case refusal
    case badResponse
}

/// Claude API(Messages API)を URLSession で直接呼び出す。
/// 単語がその文の中でどの品詞・意味で使われているかを structured outputs で確実に JSON 取得する。
enum ClaudeAPIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"

    static var isConfigured: Bool {
        KeychainHelper.load(for: KeychainHelper.anthropicAPIKey) != nil
    }

    /// ブロック内の複数単語の意味をまとめて取得する(事前生成用。1ブロック1リクエスト)
    static func blockWordSenses(blockText: String, words: [String]) async throws -> [String: WordSense] {
        let itemSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "word": ["type": "string", "description": "対象の単語(与えられた表記のまま)"],
                "pos_ja": ["type": "string", "description": "この文章中でのこの単語の品詞。日本語で(例: 名詞、動詞、形容詞、副詞、前置詞)"],
                "meaning_ja": ["type": "string", "description": "この文章中でのこの単語の意味。簡潔な日本語の訳語(目安15文字以内)"],
            ],
            "required": ["word", "pos_ja", "meaning_ja"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["senses": ["type": "array", "items": itemSchema]],
            "required": ["senses"],
            "additionalProperties": false,
        ]

        let prompt = """
        次の英文の中で使われている各単語について、この文章の中で使われている品詞と意味を日本語で答えてください。\
        同じ単語に複数の意味がある場合も、必ずこの文章で使われている意味だけを答えてください。\
        与えられた全単語について漏れなく答えてください。

        英文: \(blockText)

        単語: \(words.joined(separator: ", "))
        """

        let text = try await sendMessage(prompt: prompt, schema: schema, maxTokens: 3000)
        struct BlockSenses: Codable {
            struct Item: Codable {
                let word: String
                let posJa: String
                let meaningJa: String
                enum CodingKeys: String, CodingKey {
                    case word
                    case posJa = "pos_ja"
                    case meaningJa = "meaning_ja"
                }
            }
            let senses: [Item]
        }
        guard let data = text.data(using: .utf8) else { throw ClaudeAPIError.badResponse }
        let decoded = try JSONDecoder().decode(BlockSenses.self, from: data)
        var result: [String: WordSense] = [:]
        for item in decoded.senses {
            result[item.word.lowercased()] = WordSense(posJa: item.posJa, meaningJa: item.meaningJa)
        }
        return result
    }

    /// 文脈つきで単語の意味を取得する
    static func wordSense(word: String, sentence: String) async throws -> WordSense {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "pos_ja": [
                    "type": "string",
                    "description": "この文中でのこの単語の品詞。日本語で(例: 名詞、動詞、形容詞、副詞、前置詞)",
                ],
                "meaning_ja": [
                    "type": "string",
                    "description": "この文中でのこの単語の意味。単語カードに載せるような簡潔な日本語の訳語(目安15文字以内)。文全体の訳ではなく単語の訳",
                ],
            ],
            "required": ["pos_ja", "meaning_ja"],
            "additionalProperties": false,
        ]

        let prompt = """
        次の英文の中で使われている単語「\(word)」について、この文中での品詞と意味を日本語で答えてください。\
        同じ単語に複数の意味がある場合も、必ずこの文で使われている意味だけを答えてください。

        英文: \(sentence)
        """

        let text = try await sendMessage(prompt: prompt, schema: schema, maxTokens: 300)
        guard let senseData = text.data(using: .utf8) else { throw ClaudeAPIError.badResponse }
        return try JSONDecoder().decode(WordSense.self, from: senseData)
    }

    /// Messages API へ structured outputs つきでリクエストし、テキスト(JSON文字列)を返す
    private static func sendMessage(prompt: String, schema: [String: Any], maxTokens: Int) async throws -> String {
        guard let apiKey = KeychainHelper.load(for: KeychainHelper.anthropicAPIKey) else {
            throw ClaudeAPIError.noAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": prompt]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeAPIError.httpError(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.badResponse
        }
        // stop_reason を確認してから content を読む
        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            throw ClaudeAPIError.refusal
        }
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw ClaudeAPIError.badResponse
        }
        return text
    }
}
