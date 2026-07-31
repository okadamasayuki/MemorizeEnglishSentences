import Foundation

// MARK: - 解析結果モデル

struct SyntaxElement: Codable, Hashable {
    let text: String
    /// S / V / O / C / M / Aux
    let role: String
    let noteJa: String

    enum CodingKeys: String, CodingKey {
        case text
        case role
        case noteJa = "note_ja"
    }
}

struct SyntaxAnalysis: Codable, Hashable {
    /// SV | SVC | SVO | SVOO | SVOC
    let pattern: String
    let elements: [SyntaxElement]
    let explanationJa: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case elements
        case explanationJa = "explanation_ja"
    }

    var patternLabelJa: String {
        switch pattern {
        case "SV": "第1文型 SV"
        case "SVC": "第2文型 SVC"
        case "SVO": "第3文型 SVO"
        case "SVOO": "第4文型 SVOO"
        case "SVOC": "第5文型 SVOC"
        default: pattern
        }
    }
}

// MARK: - エラー

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case unauthorized
    case rateLimited
    case refusal
    case offline
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "API キーが設定されていません。設定タブで Anthropic API キーを入力してください。"
        case .unauthorized:
            "API キーが正しくありません。設定タブで確認してください。"
        case .rateLimited:
            "リクエストが多すぎます。しばらく待ってから再試行してください。"
        case .refusal:
            "この文は解析できませんでした。"
        case .offline:
            "ネットワークに接続できません。構文解析にはインターネット接続が必要です。"
        case .invalidResponse:
            "解析結果を読み取れませんでした。もう一度お試しください。"
        case .http(let code, let message):
            "エラーが発生しました (\(code)): \(message)"
        }
    }
}

// MARK: - API サービス

/// Claude API (POST /v1/messages) を URLSession 直叩きで呼び出し、
/// structured outputs で構文解析結果を JSON として確実に取得する。
enum ClaudeAPIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"

    static func analyzeSyntax(sentence: String) async throws -> SyntaxAnalysis {
        guard let apiKey = KeychainHelper.load(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "enum": ["SV", "SVC", "SVO", "SVOO", "SVOC"],
                ],
                "elements": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string"],
                            "role": [
                                "type": "string",
                                "enum": ["S", "V", "O", "C", "M", "Aux"],
                            ],
                            "note_ja": ["type": "string"],
                        ],
                        "required": ["text", "role", "note_ja"],
                        "additionalProperties": false,
                    ],
                ],
                "explanation_ja": ["type": "string"],
            ],
            "required": ["pattern", "elements", "explanation_ja"],
            "additionalProperties": false,
        ]

        let prompt = """
        次の英文を英語の五文型 (SV/SVC/SVO/SVOO/SVOC) で構文解析してください。

        - 文中のすべての語句を、文頭から順番どおりに elements に割り当てること
        - role は S(主語) / V(動詞) / O(目的語) / C(補語) / M(修飾語) / Aux(助動詞) を使うこと
        - note_ja には各要素の日本語での短い説明(例: 「主語: 彼は」)を書くこと
        - explanation_ja には文全体の構造を日本語学習者向けにわかりやすく解説すること

        英文: \(sentence)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": schema,
                ],
            ],
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ClaudeAPIError.unauthorized
        case 429:
            throw ClaudeAPIError.rateLimited
        default:
            throw ClaudeAPIError.http(http.statusCode, errorMessage(from: data))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.invalidResponse
        }

        // stop_reason を確認してから content を読む
        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            throw ClaudeAPIError.refusal
        }

        guard
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
            let textData = text.data(using: .utf8),
            let analysis = try? JSONDecoder().decode(SyntaxAnalysis.self, from: textData)
        else {
            throw ClaudeAPIError.invalidResponse
        }
        return analysis
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return "不明なエラー"
        }
        return message
    }
}
