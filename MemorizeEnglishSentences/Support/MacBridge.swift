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
            }
        }
        try? context.save()
        try? FileManager.default.removeItem(at: url)
    }
}
