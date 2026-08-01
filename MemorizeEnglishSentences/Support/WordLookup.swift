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

/// 単語の意味データ。ポップアップ(シート)が直接監視する。
/// (シートのコンテンツは最初の表示時に親の @State の更新を
///  取りこぼすことがあるため、ObservableObject で確実に反映させる)
@MainActor
final class WordMeaningModel: ObservableObject {
    @Published var japanese: String?
    @Published var failed = false
    /// この文中での品詞(文脈対応の意味のときだけ入る)
    @Published var pos: String?
    /// 文脈に合わせた意味かどうか(Claude API 由来)
    @Published var isContextual = false

    func reset() {
        japanese = nil
        failed = false
        pos = nil
        isContextual = false
    }

    func apply(_ sense: WordSense) {
        japanese = sense.meaningJa
        pos = sense.posJa
        isContextual = true
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

/// 文脈つき単語意味の解決(Claude API + キャッシュ)。
/// キャッシュはブロック英文のハッシュで引くため、同じブロック内なら再課金なしで即表示できる
@MainActor
enum WordSenseLookup {
    /// 単語を含む文をテキストから取り出す(見つからなければ全文を使う)
    static func sentence(containing word: String, in text: String) -> String {
        let sentences = TextSplitter.split(text)
        let target = word.lowercased()
        for sentence in sentences {
            let words = WordTokenizer.tokenize(sentence).map(\.normalized)
            if words.contains(target) {
                return sentence
            }
        }
        return text
    }

    static func cacheKey(word: String, blockText: String) -> String {
        let normalized = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "\(word.lowercased())|\(hash)"
    }

    static func cached(word: String, blockText: String, modelContext: ModelContext) -> WordSense? {
        let key = cacheKey(word: word, blockText: blockText)
        let descriptor = FetchDescriptor<WordSenseCacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        guard let entry = try? modelContext.fetch(descriptor).first else { return nil }
        return WordSense(posJa: entry.posJa, meaningJa: entry.meaningJa)
    }

    /// API から取得してキャッシュする。失敗したら nil(呼び出し側が従来手段へフォールバック)
    static func fetch(word: String, blockText: String, modelContext: ModelContext) async -> WordSense? {
        let sentence = sentence(containing: word, in: blockText)
        guard let sense = try? await ClaudeAPIService.wordSense(word: word, sentence: sentence) else {
            return nil
        }
        let entry = WordSenseCacheEntry(
            key: cacheKey(word: word, blockText: blockText),
            word: word,
            posJa: sense.posJa,
            meaningJa: sense.meaningJa
        )
        modelContext.insert(entry)
        try? modelContext.save()
        return sense
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
