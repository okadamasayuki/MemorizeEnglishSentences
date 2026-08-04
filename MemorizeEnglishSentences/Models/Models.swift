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
        case .normal: "どちらでもない"
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

/// 熟語タブの 1 項目(熟語+意味+例文)
@Model
final class Idiom {
    /// 見出し語番号(2101 など)。並び順に使う
    @Attribute(.unique) var number: Int
    /// 熟語(例: "abide by ~")
    var phrase: String
    /// 意味(和訳。[= 類義語] を含む)
    var meaning: String
    /// 例文(英語)
    var example: String
    /// 例文の和訳
    var exampleJa: String
    /// 星印(単語タブと同じ。付けた熟語だけに絞り込める)
    var isStarred: Bool = false
    /// しおり(どこまで進めたかの目印。全体で1か所)
    var isBookmarked: Bool = false
    /// (旧UIの名残。スキーマ互換のため残す。未使用)
    var memorizationStatusRaw: String = "normal"

    init(number: Int, phrase: String, meaning: String, example: String, exampleJa: String) {
        self.number = number
        self.phrase = phrase
        self.meaning = meaning
        self.example = example
        self.exampleJa = exampleJa
    }
}

/// 単語タブの 1 項目(英語フレーズ+和訳)
@Model
final class VocabWord {
    /// 表示順(音声の収録順)
    var index: Int
    var english: String
    var japanese: String
    /// 星印(お気に入り)
    var isStarred: Bool = false

    init(index: Int, english: String, japanese: String) {
        self.index = index
        self.english = english
        self.japanese = japanese
    }
}

@Model
final class Passage {
    var title: String
    var createdAt: Date
    /// MemorizationStatus の rawValue(既定は「どちらでもない」)
    var memorizationStatusRaw: String = MemorizationStatus.normal.rawValue
    /// PassagePurpose の rawValue(既存データは既定で音読)
    var purposeRaw: String = PassagePurpose.reading.rawValue
    /// 一覧の手動並び順(小さいほど上。同値は作成日の新しい順)
    var sortIndex: Int = 0

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
    /// どこまで音読したかの目印(しおり)。全体で 1 か所だけ true にする
    var isMarked: Bool = false
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

/// 文脈つき単語意味のキャッシュ(同じ文の同じ単語で再課金しない)
@Model
final class WordSenseCacheEntry {
    /// "単語|文のハッシュ" 形式の一意キー
    @Attribute(.unique) var key: String
    var word: String
    var posJa: String
    var meaningJa: String
    var updatedAt: Date

    init(key: String, word: String, posJa: String, meaningJa: String, updatedAt: Date = .now) {
        self.key = key
        self.word = word
        self.posJa = posJa
        self.meaningJa = meaningJa
        self.updatedAt = updatedAt
    }
}

/// ブロックを「英文1文↔和訳1文」のペアに分けたデータ(Claude Code が事前生成)。
/// 音読タブで英文と和訳を文ごとに交互表示するのに使う。
@Model
final class SentencePairCacheEntry {
    /// ブロック英文のハッシュ(sha256(englishText.trim).hex[:16])
    @Attribute(.unique) var key: String
    /// [["英文","和訳"], ...] を JSON エンコードした文字列
    var pairsJSON: String
    var updatedAt: Date

    init(key: String, pairsJSON: String, updatedAt: Date = .now) {
        self.key = key
        self.pairsJSON = pairsJSON
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

