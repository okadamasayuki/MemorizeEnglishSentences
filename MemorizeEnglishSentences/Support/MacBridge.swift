import Foundation
import SwiftData

/// Mac(Claude Code)との橋渡し。
/// 起動時に登録済みの英文を Documents へ書き出し(Mac 側が devicectl で取得)、
/// Mac 側が置いた修正ファイルがあれば取り込んで英文を直す。
enum MacBridge {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
        // 同じ用途(音読/暗記)内でタイトルが重複していれば取り込まない
        let existingTitles = Set(existing.map { "\($0.purposeRaw)|\($0.title)" })

        // 一覧(作成日の新しい順)にファイルの並びどおり上から表示されるよう createdAt をずらす
        let base = Date.now
        for (offset, item) in list.enumerated() {
            guard let title = item["title"] as? String,
                  let blocks = item["blocks"] as? [[String: Any]] else { continue }
            // "purpose": "recall" を指定すると暗記タブへ入る(省略時は音読)
            let purpose: PassagePurpose = (item["purpose"] as? String == "recall") ? .recall : .reading
            guard !existingTitles.contains("\(purpose.rawValue)|\(title)") else { continue }
            let passage = Passage(title: title, createdAt: base.addingTimeInterval(-Double(offset)))
            passage.purpose = purpose
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

    /// 学習状態(覚えた!・並び順・しおり・調べた単語履歴)を learning_state.json に書き出す。
    /// 万一データが消えた時に Mac 側から復元できるようにする保険(起動のたびに最新化)。
    static func exportLearningState(context: ModelContext) {
        var out: [String: Any] = [:]
        // 暗記: 各文章の状態と並び順(英文で紐づける)
        if let passages = try? context.fetch(FetchDescriptor<Passage>()) {
            out["recall"] = passages.filter { $0.purpose == .recall }.map {
                [
                    "english": $0.englishFullText,
                    "status": $0.memorizationStatusRaw,
                    "sortIndex": $0.sortIndex,
                ] as [String: Any]
            }
        }
        // 音読: しおりの付いたブロック
        if let blocks = try? context.fetch(FetchDescriptor<Block>()) {
            out["bookmarks"] = blocks.filter(\.isMarked).map(\.englishText)
        }
        // 文ごとの再生回数設定(×0スキップ・×2繰り返し等)もバックアップに含める
        if let repeats = UserDefaults.standard.dictionary(forKey: "sentenceRepeatCounts") as? [String: [Int]] {
            out["sentenceRepeats"] = repeats
        }
        // ブロック全体の繰り返し回数(全項目共通の設定)
        out["blockRepeatGlobal"] = SentenceRepeatStore.globalBlockCount
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent("learning_state.json"))
        }
    }

    /// 登録済み熟語の書き出し(Claude Code が投入元との完全一致チェックに使う)
    static func exportIdioms(context: ModelContext) {
        let descriptor = FetchDescriptor<Idiom>(sortBy: [SortDescriptor(\.number)])
        guard let idioms = try? context.fetch(descriptor) else { return }
        let items: [[String: Any]] = idioms.map {
            [
                "number": $0.number,
                "phrase": $0.phrase,
                "meaning": $0.meaning,
                "example": $0.example,
                "exampleJa": $0.exampleJa,
                "level": $0.level,
                "idiomTokensJSON": $0.idiomTokensJSON,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent("idioms_export.json"))
        }
    }

    /// Claude Code が置いた import_idioms.json を熟語タブへ取り込む。
    /// 形式: [{"number", "phrase", "meaning", "example", "exampleJa", "level", "idiomTokens": [Int]}]
    /// 既存番号は上書き更新(upsert)なので、意味・和訳の修正を後から反映できる。
    /// 適用後はファイルを削除し、結果を import_idioms_result.json に書き出す。
    static func importIdiomsIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("import_idioms.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let descriptor = FetchDescriptor<Idiom>()
        // 番号は級をまたぐと重複するので「級|番号」で照合する
        var existing: [String: Idiom] = [:]
        for idiom in (try? context.fetch(descriptor)) ?? [] { existing["\(idiom.level)|\(idiom.number)"] = idiom }

        var inserted = 0
        var updated = 0
        for item in list {
            guard let number = item["number"] as? Int,
                  let phrase = item["phrase"] as? String,
                  let meaning = item["meaning"] as? String,
                  let example = item["example"] as? String else { continue }
            let exampleJa = item["exampleJa"] as? String ?? ""
            let level = item["level"] as? String ?? ""
            var tokensJSON = ""
            if let tokens = item["idiomTokens"] as? [Int],
               let encoded = try? JSONSerialization.data(withJSONObject: tokens) {
                tokensJSON = String(data: encoded, encoding: .utf8) ?? ""
            }
            if let idiom = existing["\(level)|\(number)"] {
                idiom.phrase = phrase
                idiom.meaning = meaning
                idiom.example = example
                idiom.exampleJa = exampleJa
                idiom.level = level
                idiom.idiomTokensJSON = tokensJSON
                updated += 1
            } else {
                let idiom = Idiom(
                    number: number, phrase: phrase, meaning: meaning,
                    example: example, exampleJa: exampleJa, level: level
                )
                idiom.idiomTokensJSON = tokensJSON
                context.insert(idiom)
                inserted += 1
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)

        let result: [String: Int] = ["inserted": inserted, "updated": updated, "totalInFile": list.count]
        if let out = try? JSONSerialization.data(withJSONObject: result) {
            try? out.write(to: documents.appendingPathComponent("import_idioms_result.json"))
        }
    }

    /// Claude Code が置いた word_senses.json(文中での単語の意味の事前生成データ)を取り込む。
    /// 形式: [{"key": 単語|ブロックハッシュ, "word": 単語, "pos": 品詞, "meaning": 訳語}]
    /// 取り込み後はファイルを削除し、結果を word_senses_result.json に書き出す。
    static func importWordSensesIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("word_senses.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }

        let descriptor = FetchDescriptor<WordSenseCacheEntry>()
        var existing: [String: WordSenseCacheEntry] = [:]
        for entry in (try? context.fetch(descriptor)) ?? [] {
            existing[entry.key] = entry
        }
        var imported = 0
        for item in list {
            guard let key = item["key"],
                  let word = item["word"],
                  let pos = item["pos"],
                  let meaning = item["meaning"] else { continue }
            if let entry = existing[key] {
                // 訳語の修正を反映できるよう、既存キーは上書き更新する
                if entry.posJa != pos || entry.meaningJa != meaning {
                    entry.posJa = pos
                    entry.meaningJa = meaning
                    entry.updatedAt = .now
                    imported += 1
                }
            } else {
                context.insert(WordSenseCacheEntry(key: key, word: word, posJa: pos, meaningJa: meaning))
                imported += 1
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)

        let result: [String: Int] = ["imported": imported, "totalInFile": list.count]
        if let out = try? JSONSerialization.data(withJSONObject: result) {
            try? out.write(to: documents.appendingPathComponent("word_senses_result.json"))
        }
    }

    /// Claude Code が置いた sentence_pairs.json(英文↔和訳の文ごとのペア)を取り込む。
    /// 形式: [{"key": ブロック英文ハッシュ, "pairs": [{"en": 英文, "ja": 和訳}]}]
    /// 既存キーは上書き更新する。適用後はファイルを削除し、結果を sentence_pairs_result.json に書き出す。
    static func importSentencePairsIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("sentence_pairs.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let descriptor = FetchDescriptor<SentencePairCacheEntry>()
        var existing: [String: SentencePairCacheEntry] = [:]
        for entry in (try? context.fetch(descriptor)) ?? [] { existing[entry.key] = entry }

        var imported = 0
        for item in list {
            guard let key = item["key"] as? String,
                  let pairs = item["pairs"] as? [[String: String]],
                  // キー順を固定して、毎回の再取り込みで無駄に更新扱いにならないようにする
                  let json = try? JSONSerialization.data(withJSONObject: pairs, options: [.sortedKeys]),
                  let jsonString = String(data: json, encoding: .utf8) else { continue }
            if let entry = existing[key] {
                if entry.pairsJSON != jsonString {
                    entry.pairsJSON = jsonString
                    entry.updatedAt = .now
                    imported += 1
                }
            } else {
                context.insert(SentencePairCacheEntry(key: key, pairsJSON: jsonString))
                imported += 1
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)
        // 取り込み直したので、一覧表示用のメモを捨てて次回から新しいペアを引かせる
        Task { @MainActor in SentencePairLookup.invalidateCache() }

        let result: [String: Int] = ["imported": imported, "totalInFile": list.count]
        if let out = try? JSONSerialization.data(withJSONObject: result) {
            try? out.write(to: documents.appendingPathComponent("sentence_pairs_result.json"))
        }
    }

    /// Claude Code が置いた translations.json(ブロック全文の和訳)を取り込む。
    /// 形式: [{"english": 英文(完全一致), "japanese": 和訳}]
    /// 既存の和訳(Apple翻訳製など)も上書きする。適用後はファイルを削除し、
    /// 結果を translations_result.json に書き出す。
    static func applyTranslationsIfAny(context: ModelContext) {
        let url = documents.appendingPathComponent("translations.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }

        let descriptor = FetchDescriptor<Block>()
        let blocks = (try? context.fetch(descriptor)) ?? []
        var byEnglish: [String: [Block]] = [:]
        for block in blocks { byEnglish[block.englishText, default: []].append(block) }

        var applied = 0
        for item in list {
            guard let english = item["english"], let japanese = item["japanese"], !japanese.isEmpty else { continue }
            for block in byEnglish[english] ?? [] where block.japaneseText != japanese {
                block.japaneseText = japanese
                applied += 1
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)

        let result: [String: Int] = ["applied": applied, "totalInFile": list.count]
        if let out = try? JSONSerialization.data(withJSONObject: result) {
            try? out.write(to: documents.appendingPathComponent("translations_result.json"))
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
