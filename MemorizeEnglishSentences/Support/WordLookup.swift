import Foundation
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

    func reset() {
        japanese = nil
        failed = false
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
