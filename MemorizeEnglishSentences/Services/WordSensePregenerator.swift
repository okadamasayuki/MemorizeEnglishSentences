import Foundation
import SwiftData

/// 登録済みの全ブロックについて、内容語(機能語以外)の「文中での意味」を
/// 一括生成してキャッシュする。1ブロック1リクエストで、生成済みの単語は飛ばすので
/// 途中で止めても再開でき、二重課金にならない。
@MainActor
final class WordSensePregenerator: ObservableObject {
    @Published var isRunning = false
    @Published var progressText: String?
    @Published var resultText: String?

    private var task: Task<Void, Never>?

    func start(modelContext: ModelContext) {
        guard !isRunning else { return }
        isRunning = true
        resultText = nil
        task = Task { await run(modelContext: modelContext) }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(modelContext: ModelContext) async {
        defer {
            isRunning = false
            progressText = nil
        }

        let descriptor = FetchDescriptor<Block>()
        guard let blocks = try? modelContext.fetch(descriptor), !blocks.isEmpty else {
            resultText = "対象の英文がありません"
            return
        }

        var generatedWords = 0
        var failedBlocks = 0
        for (index, block) in blocks.enumerated() {
            if Task.isCancelled { break }
            progressText = "\(index + 1) / \(blocks.count) ブロック"

            let text = block.englishText
            let words = pendingContentWords(of: text, modelContext: modelContext)
            guard !words.isEmpty else { continue }

            do {
                let senses = try await ClaudeAPIService.blockWordSenses(blockText: text, words: words)
                let requested = Set(words)
                for (word, sense) in senses where requested.contains(word) {
                    let entry = WordSenseCacheEntry(
                        key: WordSenseLookup.cacheKey(word: word, blockText: text),
                        word: word,
                        posJa: sense.posJa,
                        meaningJa: sense.meaningJa
                    )
                    modelContext.insert(entry)
                    generatedWords += 1
                }
                try? modelContext.save()
            } catch {
                failedBlocks += 1
            }
        }

        if Task.isCancelled {
            resultText = "中断しました(生成済み \(generatedWords) 語は保存されています)"
        } else if failedBlocks > 0 {
            resultText = "完了: \(generatedWords) 語を生成(\(failedBlocks) ブロックは失敗。もう一度実行すると失敗分だけ再試行します)"
        } else {
            resultText = "完了: \(generatedWords) 語を生成しました"
        }
    }

    /// ブロック内の内容語のうち、まだキャッシュされていないもの
    private func pendingContentWords(of text: String, modelContext: ModelContext) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for token in WordTokenizer.tokenize(text) {
            let word = token.normalized
            guard word.count >= 2,
                  word.rangeOfCharacter(from: .letters) != nil,
                  !EnglishFunctionWords.set.contains(word),
                  !seen.contains(word) else { continue }
            seen.insert(word)
            if WordSenseLookup.cached(word: word, blockText: text, modelContext: modelContext) == nil {
                words.append(word)
            }
        }
        return words
    }
}
