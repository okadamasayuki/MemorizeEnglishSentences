import AVFoundation
import Foundation
import SwiftData

/// Mac(Claude Code)との橋渡し。
/// 起動時に登録済みの英文を Documents へ書き出し(Mac 側が devicectl で取得)、
/// Mac 側が置いた修正ファイルがあれば取り込んで英文を直す。
enum MacBridge {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 端末にインストールされている読み上げボイスの一覧を書き出す(声の選定用)
    static func exportVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") || $0.language.hasPrefix("en-US") }
            .map {
                [
                    "identifier": $0.identifier,
                    "name": $0.name,
                    "language": $0.language,
                    "quality": String($0.quality.rawValue),
                ]
            }
        if let data = try? JSONSerialization.data(withJSONObject: voices, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent("voices.json"))
        }
    }

    /// 登録済み英文の書き出し(Claude Code がチェックに使う)
    static func exportPassages(context: ModelContext) {
        let descriptor = FetchDescriptor<Block>()
        guard let blocks = try? context.fetch(descriptor) else { return }
        let items: [[String: String]] = blocks.map {
            [
                "purpose": $0.passage?.purpose.rawValue ?? "",
                "english": $0.englishText,
                "japanese": $0.japaneseText ?? "",
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent("passages_export.json"))
        }
    }

    /// Claude Code が置いた import_passages.json を音読タブへ取り込む。
    /// 形式: [{"title": タイトル, "blocks": [{"english": 英文, "japanese": 和訳(省略可)}]}]
    /// 同じタイトルの音読の文章が既にあれば重複させない。適用後はファイルを削除する。
    static func importPassagesIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("import_passages.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let descriptor = FetchDescriptor<Passage>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingTitles = Set(existing.filter { $0.purpose == .reading }.map(\.title))

        // 一覧(作成日の新しい順)にファイルの並びどおり上から表示されるよう createdAt をずらす
        let base = Date.now
        for (offset, item) in list.enumerated() {
            guard let title = item["title"] as? String,
                  let blocks = item["blocks"] as? [[String: Any]],
                  !existingTitles.contains(title) else { continue }
            let passage = Passage(title: title, createdAt: base.addingTimeInterval(-Double(offset)))
            passage.purpose = .reading
            context.insert(passage)
            for (index, blockItem) in blocks.enumerated() {
                guard let english = blockItem["english"] as? String, !english.isEmpty else { continue }
                let block = Block(
                    index: index,
                    englishText: english,
                    japaneseText: blockItem["japanese"] as? String
                )
                block.passage = passage
                context.insert(block)
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)
    }

    /// Claude Code が置いた word_senses.json(文中での単語の意味の事前生成データ)を取り込む。
    /// 形式: [{"key": 単語|ブロックハッシュ, "word": 単語, "pos": 品詞, "meaning": 訳語}]
    /// 取り込み後はファイルを削除し、結果を word_senses_result.json に書き出す。
    static func importWordSensesIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("word_senses.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }

        let descriptor = FetchDescriptor<WordSenseCacheEntry>()
        let existing = Set(((try? context.fetch(descriptor)) ?? []).map(\.key))
        var imported = 0
        for item in list {
            guard let key = item["key"],
                  let word = item["word"],
                  let pos = item["pos"],
                  let meaning = item["meaning"],
                  !existing.contains(key) else { continue }
            context.insert(WordSenseCacheEntry(key: key, word: word, posJa: pos, meaningJa: meaning))
            imported += 1
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)

        let result: [String: Int] = ["imported": imported, "totalInFile": list.count]
        if let out = try? JSONSerialization.data(withJSONObject: result) {
            try? out.write(to: documents.appendingPathComponent("word_senses_result.json"))
        }
    }

    /// Claude Code が置いた delete_passages.json を適用する。
    /// 形式: [ブロック英文の先頭文字列] — 先頭一致するブロックを含む音読の文章を削除する。
    /// 適用後はファイルを削除する。
    static func applyDeletionsIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("delete_passages.json")
        guard let data = try? Data(contentsOf: url),
              let prefixes = try? JSONSerialization.jsonObject(with: data) as? [String],
              !prefixes.isEmpty else { return }

        let descriptor = FetchDescriptor<Passage>()
        if let passages = try? context.fetch(descriptor) {
            for passage in passages where passage.purpose == .reading {
                let hit = passage.blocks.contains { block in
                    prefixes.contains { block.englishText.hasPrefix($0) }
                }
                if hit { context.delete(passage) }
            }
            try? context.save()
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Claude Code が置いた corrections.json を取り込む。
    /// 形式: [{"old": 修正前の英文, "new": 修正後の英文}]
    /// 適用後はファイルを削除する。
    static func applyCorrectionsIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("corrections.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }

        let descriptor = FetchDescriptor<Block>()
        guard let blocks = try? context.fetch(descriptor) else { return }
        for correction in list {
            guard let old = correction["old"], let new = correction["new"], old != new else { continue }
            for block in blocks where block.englishText == old {
                block.englishText = new
                // 修正前の英文から作った和訳は古くなるので、消して再翻訳させる
                block.japaneseText = nil
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)
    }
}
