import CryptoKit
import Foundation

/// 復習タブで「もう覚えた」とチェックした文を覚えておく。
///
/// 文の識別は英文のハッシュ(sha256(英文.trim)[:16])。学習データ本体とは
/// 役目が違うので Documents 直下の別ファイルに持つ(端末を複製すれば iPad にも移る)。
final class MemorizedSentenceStore: ObservableObject {
    static let shared = MemorizedSentenceStore()

    @Published private(set) var memorized: Set<String> = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memorized_sentences.json")
    }

    init() { load() }

    /// 英文からチェック用のキーを作る(音声・画像などと同じ方式)
    static func key(for english: String) -> String {
        let normalized = english.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    func isMemorized(_ key: String) -> Bool { memorized.contains(key) }

    func toggle(_ key: String) {
        if memorized.contains(key) { memorized.remove(key) } else { memorized.insert(key) }
        save()
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        memorized = Set(decoded)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(memorized)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
