import CryptoKit
import Foundation
import SwiftData

/// 構文解析のキャッシュ付き呼び出し(同じ文の再解析で課金しない)
enum SyntaxAnalyzer {
    @MainActor
    static func analyze(sentence: String, context: ModelContext) async throws -> SyntaxAnalysis {
        let hash = hash(of: sentence)

        let descriptor = FetchDescriptor<SyntaxCacheEntry>(
            predicate: #Predicate { $0.sentenceHash == hash }
        )
        if let cached = try? context.fetch(descriptor).first,
           let data = cached.resultJSON.data(using: .utf8),
           let analysis = try? JSONDecoder().decode(SyntaxAnalysis.self, from: data) {
            return analysis
        }

        let result = try await ClaudeAPIService.analyzeSyntax(sentence: sentence)
        if let data = try? JSONEncoder().encode(result),
           let json = String(data: data, encoding: .utf8) {
            context.insert(SyntaxCacheEntry(sentenceHash: hash, sentence: sentence, resultJSON: json))
            try? context.save()
        }
        return result
    }

    private static func hash(of sentence: String) -> String {
        let normalized = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
