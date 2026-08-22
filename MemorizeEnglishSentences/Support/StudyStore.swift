import Foundation

/// 「歩きながら英文をチェック → あとで単語を選ぶ → 単語リストを再生(シス単風)」用のデータ。
/// Documents/study.json に保存する。学習データ(SwiftData)とは独立。
final class StudyStore: ObservableObject {
    static let shared = StudyStore()

    /// あとで見返す英文(再生中にワンタップでチェックした文)
    struct FlaggedSentence: Identifiable, Codable, Equatable {
        var id = UUID()
        var en: String
        var ja: String
        var addedAt = Date()
    }
    /// 覚える単語(チェックした英文から選んだ、意味と結びついていない単語)
    struct StudyWord: Identifiable, Codable, Equatable {
        var id = UUID()
        var word: String
        var meaning: String
        var addedAt = Date()
    }

    @Published private(set) var flagged: [FlaggedSentence] = []
    @Published private(set) var words: [StudyWord] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("study.json")
    }

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

    /// 英文チェックのオン/オフ(再生中のワンタップ用)
    func toggleFlag(en: String, ja: String) {
        let trimmed = en.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = flagged.firstIndex(where: { $0.en == trimmed }) {
            flagged.remove(at: i)
        } else {
            flagged.insert(FlaggedSentence(en: trimmed, ja: ja), at: 0)
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

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        flagged = p.flagged
        words = p.words
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Payload(flagged: flagged, words: words)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
