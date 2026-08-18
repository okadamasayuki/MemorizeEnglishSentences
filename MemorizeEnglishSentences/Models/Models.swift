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

/// 熟語タブの 1 項目(音読特化)。例文を読み上げながら熟語の意味を覚える。
/// 一意性は「級+番号」の組(級をまたぐと番号が重複する: 2級1601-1700 と 準1級1601-1700)。
@Model
final class Idiom {
    /// 見出し語番号(2101 など)。並び順に使う。級をまたぐと重複しうる
    var number: Int
    /// 熟語(例: "abide by ~")
    var phrase: String
    /// 意味(和訳。[= 類義語] を含む)
    var meaning: String
    /// 例文(英語)
    var example: String
    /// 例文の和訳
    var exampleJa: String
    /// 星印(旧UIの名残。スキーマ互換のため残す。未使用)
    var isStarred: Bool = false
    /// しおり(どこまで進めたかの目印。全体で1か所)
    var isBookmarked: Bool = false
    /// (旧UIの名残。スキーマ互換のため残す。未使用)
    var memorizationStatusRaw: String = "normal"
    /// 級(例: "準1級" / "1級")。熟語タブでこの単位に絞り込んで表示する
    var level: String = ""
    /// 例文中の熟語部分のトークン番号(空白区切り・0始まり)のJSON配列。
    /// Mac 側で活用形も考慮して算出済み。強調表示と長押し判定に使う
    var idiomTokensJSON: String = ""

    init(number: Int, phrase: String, meaning: String, example: String, exampleJa: String, level: String = "") {
        self.number = number
        self.phrase = phrase
        self.meaning = meaning
        self.example = example
        self.exampleJa = exampleJa
        self.level = level
    }

    /// JSON文字列→トークン番号集合のメモ(一覧の描画のたびにデコードしないため)
    private static var tokenIndexCache: [String: Set<Int>] = [:]

    /// 例文中の熟語部分のトークン番号(デコード済み)
    var idiomTokenIndexes: Set<Int> {
        if let hit = Self.tokenIndexCache[idiomTokensJSON] { return hit }
        guard let data = idiomTokensJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        let set = Set(list)
        if Self.tokenIndexCache.count > 4000 { Self.tokenIndexCache.removeAll(keepingCapacity: true) }
        Self.tokenIndexCache[idiomTokensJSON] = set
        return set
    }
}

/// (旧)履歴タブの1項目。タブは廃止済みだが、@Model を削除すると
/// SwiftData のマイグレーションでクラッシュするため、定義だけ残している(データは削除済み)。
@Model
final class LookedUpWord {
    @Attribute(.unique) var word: String
    /// 調べた時に表示していた和訳(空のこともある)
    var meaning: String
    /// 最後に調べた日時(新しい順の並びに使う)
    var lookedUpAt: Date
    /// お気に入り(❤️)。右スワイプで登録
    var isFavorite: Bool = false
    /// 長押しで調べた回数(間違えた時はカウントしない)
    var count: Int = 1

    init(word: String, meaning: String, lookedUpAt: Date) {
        self.word = word
        self.meaning = meaning
        self.lookedUpAt = lookedUpAt
    }
}

/// (旧)単語タブの 1 項目。タブは廃止済みだが、@Model を削除すると
/// SwiftData のマイグレーションでクラッシュするため、定義だけ残している(データは削除済み)。
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

