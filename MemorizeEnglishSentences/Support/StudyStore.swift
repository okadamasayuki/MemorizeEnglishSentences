import Foundation

/// 「歩きながら英文をチェック → あとで単語を選ぶ → 単語リストを再生(シス単風)」用のデータ。
/// Documents/study.json に保存する。学習データ(SwiftData)とは独立。
///
/// 大事に貯めたチェック/単語が消えないよう、保存のたびに study.json.bak も書き、
/// 読み込みに失敗したら .bak から復旧する。さらに壊れたファイルは study.json.corrupt に
/// 退避してから上書きするので、いきなり空で潰してしまうことがない。
final class StudyStore: ObservableObject {
    static let shared = StudyStore()

    /// あとで見返す英文(再生中にワンタップでチェックした文)
    struct FlaggedSentence: Identifiable, Codable, Equatable {
        var id = UUID()
        var en: String
        var ja: String
        /// この文が入っていたブロック全文(教材音声の特定と、文中の単語の意味引きに使う)
        var blockEn: String = ""
        var addedAt = Date()

        // 将来フィールドが増えても古い study.json を壊さないよう、
        // 足りないキーは既定値で補って読む(欠損キーでデコード失敗→全消し を防ぐ)
        init(id: UUID = UUID(), en: String, ja: String, blockEn: String = "", addedAt: Date = Date()) {
            self.id = id; self.en = en; self.ja = ja; self.blockEn = blockEn; self.addedAt = addedAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            en = (try? c.decode(String.self, forKey: .en)) ?? ""
            ja = (try? c.decode(String.self, forKey: .ja)) ?? ""
            blockEn = (try? c.decode(String.self, forKey: .blockEn)) ?? ""
            addedAt = (try? c.decode(Date.self, forKey: .addedAt)) ?? Date()
        }
    }
    /// 覚える単語(チェックした英文から選んだ、意味と結びついていない単語)
    struct StudyWord: Identifiable, Codable, Equatable {
        var id = UUID()
        var word: String
        var meaning: String
        var addedAt = Date()

        init(id: UUID = UUID(), word: String, meaning: String, addedAt: Date = Date()) {
            self.id = id; self.word = word; self.meaning = meaning; self.addedAt = addedAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            word = (try? c.decode(String.self, forKey: .word)) ?? ""
            meaning = (try? c.decode(String.self, forKey: .meaning)) ?? ""
            addedAt = (try? c.decode(Date.self, forKey: .addedAt)) ?? Date()
        }
    }

    @Published private(set) var flagged: [FlaggedSentence] = []
    @Published private(set) var words: [StudyWord] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("study.json")
    }
    private var backupURL: URL { fileURL.appendingPathExtension("bak") }
    private var corruptURL: URL { fileURL.appendingPathExtension("corrupt") }

    private struct Payload: Codable {
        var flagged: [FlaggedSentence]
        var words: [StudyWord]
    }

    init() { load() }

    // MARK: - 英文チェック(歩きながら)

    /// この英文が既にチェック済みか
    func isFlagged(en: String) -> Bool {
        flagged.contains { $0.en == en }
    }

    /// 英文チェックのオン/オフ(再生中のワンタップ用)。
    /// blockEn にこの文が入っていたブロック全文を渡すと、あとで教材音声の再生や
    /// 文脈に合った単語の意味引きに使える。
    func toggleFlag(en: String, ja: String, blockEn: String = "") {
        let trimmed = en.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = flagged.firstIndex(where: { $0.en == trimmed }) {
            flagged.remove(at: i)
        } else {
            flagged.insert(FlaggedSentence(en: trimmed, ja: ja, blockEn: blockEn), at: 0)
        }
        save()
    }

    func removeFlagged(_ id: UUID) {
        flagged.removeAll { $0.id == id }
        save()
    }

    // MARK: - 覚える単語

    func hasWord(_ word: String) -> Bool {
        let w = word.lowercased()
        return words.contains { $0.word.lowercased() == w }
    }

    /// 単語の追加/削除(チェックした英文で単語をタップして選ぶ)
    func toggleWord(_ word: String, meaning: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        if let i = words.firstIndex(where: { $0.word.lowercased() == w.lowercased() }) {
            words.remove(at: i)
        } else {
            words.insert(StudyWord(word: w, meaning: meaning), at: 0)
        }
        save()
    }

    func removeWord(_ id: UUID) {
        words.removeAll { $0.id == id }
        save()
    }

    /// 単語の意味を後から埋める(和訳が空だったものの補完に使う)
    func setMeaning(_ id: UUID, meaning: String) {
        let m = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty, let i = words.firstIndex(where: { $0.id == id }) else { return }
        words[i].meaning = m
        save()
    }

    // MARK: - 永続化(消えない工夫つき)

    private func decodePayload(_ url: URL) -> Payload? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func load() {
        // ① 本体を読む
        if let p = decodePayload(fileURL) {
            flagged = p.flagged
            words = p.words
            return
        }
        // ② 本体が読めない。バックアップから復旧を試みる
        if let p = decodePayload(backupURL) {
            flagged = p.flagged
            words = p.words
            // 壊れた本体は退避してから、良品のバックアップで本体を作り直す
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: corruptURL)
                try? FileManager.default.moveItem(at: fileURL, to: corruptURL)
            }
            save()
            return
        }
        // ③ どちらも読めない。本体があるなら壊れている可能性があるので、
        //    空で上書きして消してしまわないよう corrupt へ退避だけしておく
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: corruptURL)
            try? FileManager.default.copyItem(at: fileURL, to: corruptURL)
        }
        // 初回起動などでファイルが無いだけなら、空のままで問題ない
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Payload(flagged: flagged, words: words)) else { return }
        // 本体を書いてから、同じ中身をバックアップにも書く(次回の復旧用)
        try? data.write(to: fileURL, options: .atomic)
        try? data.write(to: backupURL, options: .atomic)
    }
}
