import Foundation
import SwiftData

@Model
final class Passage {
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Block.passage)
    var blocks: [Block] = []

    @Relationship(deleteRule: .cascade, inverse: \RecallAttempt.passage)
    var attempts: [RecallAttempt] = []

    init(title: String, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
    }

    /// SwiftData は配列順序を保持しないため index でソートして使う
    var orderedBlocks: [Block] {
        blocks.sorted { $0.index < $1.index }
    }

    var englishFullText: String {
        orderedBlocks.map(\.englishText).joined(separator: " ")
    }

    var japaneseFullText: String {
        orderedBlocks.compactMap(\.japaneseText).joined(separator: "\n")
    }

    var latestAttempt: RecallAttempt? {
        attempts.max { $0.date < $1.date }
    }
}

@Model
final class Block {
    var index: Int
    var englishText: String
    /// nil = 未翻訳(閲覧時に遅延リトライ)
    var japaneseText: String?
    var passage: Passage?

    init(index: Int, englishText: String, japaneseText: String? = nil) {
        self.index = index
        self.englishText = englishText
        self.japaneseText = japaneseText
    }
}

@Model
final class WordCacheEntry {
    @Attribute(.unique) var word: String
    var japanese: String
    var updatedAt: Date

    init(word: String, japanese: String, updatedAt: Date = .now) {
        self.word = word
        self.japanese = japanese
        self.updatedAt = updatedAt
    }
}

@Model
final class RecallAttempt {
    var passage: Passage?
    var date: Date
    var recognizedText: String
    /// DiffResult を JSON エンコードしたもの(間違い分析の元データ)
    var opsJSON: String
    var accuracy: Double

    init(date: Date = .now, recognizedText: String, opsJSON: String, accuracy: Double) {
        self.date = date
        self.recognizedText = recognizedText
        self.opsJSON = opsJSON
        self.accuracy = accuracy
    }
}

@Model
final class SyntaxCacheEntry {
    @Attribute(.unique) var sentenceHash: String
    var sentence: String
    var resultJSON: String
    var updatedAt: Date

    init(sentenceHash: String, sentence: String, resultJSON: String, updatedAt: Date = .now) {
        self.sentenceHash = sentenceHash
        self.sentence = sentence
        self.resultJSON = resultJSON
        self.updatedAt = updatedAt
    }
}
