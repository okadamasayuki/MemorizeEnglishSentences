import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import Translation

/// 意味表示の対象になっている単語(シート表示用)
struct SelectedWord: Identifiable {
    let id = UUID()
    let word: String
}

/// 文中での単語の意味(Claude Code が事前生成し端末キャッシュに投入する)
struct WordSense {
    let posJa: String
    let meaningJa: String
}

/// 単語の意味データ。ポップアップ(シート)が直接監視する。
/// (シートのコンテンツは最初の表示時に親の @State の更新を
///  取りこぼすことがあるため、ObservableObject で確実に反映させる)
@MainActor
final class WordMeaningModel: ObservableObject {
    @Published var japanese: String?
    @Published var failed = false
    /// この文中での品詞(文脈対応の意味のときだけ入る)
    @Published var pos: String?

    func reset() {
        japanese = nil
        failed = false
        pos = nil
    }

    func apply(_ sense: WordSense) {
        japanese = sense.meaningJa
        pos = sense.posJa
    }
}

struct TranslationTimeoutError: Error {}

/// 翻訳にタイムアウトを付ける(起動直後はエラーも返さず固まることがあるため)
func translate(
    _ session: TranslationSession, _ text: String, timeoutSeconds: Double
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            try await session.translate(text).targetText
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            throw TranslationTimeoutError()
        }
        guard let result = try await group.next() else {
            throw TranslationTimeoutError()
        }
        group.cancelAll()
        return result
    }
}

/// 冠詞・代名詞・前置詞などの機能語。単語の意味の事前生成やヒント抽出の対象外にする
enum EnglishFunctionWords {
    static let set: Set<String> = [
        "a", "an", "the",
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their", "mine", "yours",
        "myself", "yourself", "himself", "herself", "itself", "ourselves", "themselves",
        "this", "that", "these", "those", "there", "here",
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "done", "doing",
        "have", "has", "had", "having",
        "will", "would", "can", "could", "should", "shall", "may", "might", "must",
        "and", "or", "but", "so", "because", "if", "when", "while", "as", "than", "then",
        "to", "of", "in", "on", "at", "by", "for", "with", "from", "about",
        "into", "over", "under", "after", "before", "between", "through",
        "out", "up", "down", "off", "not", "no", "nor",
        "who", "whom", "whose", "what", "which", "how", "where", "why", "whether",
        "some", "any", "such", "only", "just", "also", "too", "very",
        "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't",
        "shouldn't", "isn't", "aren't", "wasn't", "weren't", "you'll", "i'm", "it's",
    ]
}

/// 文脈つき単語意味の解決。Claude Code が事前生成した意味を、
/// ブロック英文のハッシュをキーにして端末キャッシュから引く(通信なし・オフライン)。
@MainActor
enum WordSenseLookup {
    static func cacheKey(word: String, blockText: String) -> String {
        let normalized = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "\(word.lowercased())|\(hash)"
    }

    static func cached(word: String, blockText: String, modelContext: ModelContext) -> WordSense? {
        fetchEntry(key: cacheKey(word: word, blockText: blockText), modelContext: modelContext)
    }

    /// 同じ単語がブロック内で別の意味で使われる場合に備え、
    /// 「単語#出現番号」のキーを先に引き、なければブロック共通のキーへフォールバックする
    static func cached(word: String, occurrence: Int, blockText: String, modelContext: ModelContext) -> WordSense? {
        let occurrenceKey = cacheKey(word: "\(word.lowercased())#\(occurrence)", blockText: blockText)
        if let sense = fetchEntry(key: occurrenceKey, modelContext: modelContext) {
            return sense
        }
        return cached(word: word, blockText: blockText, modelContext: modelContext)
    }

    private static func fetchEntry(key: String, modelContext: ModelContext) -> WordSense? {
        let descriptor = FetchDescriptor<WordSenseCacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        guard let entry = try? modelContext.fetch(descriptor).first else { return nil }
        return WordSense(posJa: entry.posJa, meaningJa: entry.meaningJa)
    }
}

/// 英文↔和訳の文ごとのペア(Claude Code が事前生成)の解決。
@MainActor
enum SentencePairLookup {
    struct Pair: Hashable {
        let en: String
        let ja: String
    }

    /// ブロック英文のハッシュをキーに、文ごとのペアを引く。無ければ nil。
    static func cached(blockText: String, modelContext: ModelContext) -> [Pair]? {
        let normalized = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        let target = String(key)
        let descriptor = FetchDescriptor<SentencePairCacheEntry>(
            predicate: #Predicate { $0.key == target }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let data = entry.pairsJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return nil }
        let pairs = raw.compactMap { dict -> Pair? in
            guard let en = dict["en"], let ja = dict["ja"] else { return nil }
            return Pair(en: en, ja: ja)
        }
        return pairs.isEmpty ? nil : pairs
    }
}

/// 単語翻訳のリクエストを、常駐している翻訳セッションへ流し込むための橋渡し。
/// (タップごとに invalidate() でセッションを作り直す方式は、シート表示と
///  タイミングが重なる初回タップで再実行されないことがあるため)
@MainActor
final class WordTranslationBroker {
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: String?
    private var retried = Set<String>()

    /// セッション作り直しリトライをまだ試していない単語か
    func shouldRetry(_ word: String) -> Bool {
        !retried.contains(word)
    }

    /// セッション作り直し後に再翻訳するため、単語を積み直す
    func stashForRetry(_ word: String) {
        retried.insert(word)
        pending = word
        continuation = nil
    }

    func requests() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.continuation = continuation
            if let pending {
                continuation.yield(pending)
                self.pending = nil
            }
        }
    }

    func request(_ word: String) {
        if let continuation {
            continuation.yield(word)
        } else {
            pending = word
        }
    }
}
