import Foundation
import SwiftData

/// ユーザーの音声教材から抽出した単語(英語フレーズ+和訳)を一度だけ投入する
enum VocabSeedData {
    /// (英語, 和訳)。音声の収録順。抽出が終わり次第ここに入る。
    static let entries: [(String, String)] = []

    static func seedIfNeeded(context: ModelContext) {
        let key = "didSeedVocab_v1"
        guard !entries.isEmpty, !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<VocabWord>()
        let existing = Set((try? context.fetch(descriptor))?.map(\.english) ?? [])
        for (index, pair) in entries.enumerated() where !existing.contains(pair.0) {
            context.insert(VocabWord(index: index, english: pair.0, japanese: pair.1))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
