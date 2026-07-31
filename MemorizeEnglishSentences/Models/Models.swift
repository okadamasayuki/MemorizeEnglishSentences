import Foundation
import SwiftData

/// 文章がどちらのタブに属するか(音読と暗記は独立したデータ)
enum PassagePurpose: String, Codable {
    case reading
    case recall
}

/// 暗記の習熟ステータス
enum MemorizationStatus: String, Codable, CaseIterable, Identifiable {
    case needsReview
    case normal
    case memorized

    var id: String { rawValue }

    var labelJa: String {
        switch self {
        case .needsReview: "要復習"
        case .normal: "普通"
        case .memorized: "覚えた!"
        }
    }

    var iconName: String {
        switch self {
        case .needsReview: "exclamationmark.triangle.fill"
        case .normal: "minus.circle.fill"
        case .memorized: "checkmark.seal.fill"
        }
    }
}

@Model
final class Passage {
    var title: String
    var createdAt: Date
    /// MemorizationStatus の rawValue(既定は「普通」)
    var memorizationStatusRaw: String = MemorizationStatus.normal.rawValue
    /// PassagePurpose の rawValue(既存データは既定で音読)
    var purposeRaw: String = PassagePurpose.reading.rawValue

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

    var memorizationStatus: MemorizationStatus {
        get { MemorizationStatus(rawValue: memorizationStatusRaw) ?? .normal }
        set { memorizationStatusRaw = newValue.rawValue }
    }

    var purpose: PassagePurpose {
        get { PassagePurpose(rawValue: purposeRaw) ?? .reading }
        set { purposeRaw = newValue.rawValue }
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

