import Foundation

/// Claude Code からの対応結果(要望ごとの「原因と直し方」のまとめ)。
/// Mac 側が Documents/improve_results.json へ書き込み、改善タブの「対応済み」欄に出る。
struct ImprovementResult: Identifiable, Codable, Equatable {
    var id = UUID()
    /// 要望の要約(1行)
    var title: String
    /// 原因と対応内容のまとめ
    var summary: String
    var completedAt = Date()
}

/// 対応結果の読み書き(ファイルが正、削除もファイルへ反映)
final class ImprovementResultStore: ObservableObject {
    static let shared = ImprovementResultStore()

    @Published private(set) var results: [ImprovementResult] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improve_results.json")
    }

    init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ImprovementResult].self, from: data) else {
            results = []
            return
        }
        // 対応済みは1日(24時間)で自動的に消す
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let fresh = decoded.filter { $0.completedAt > cutoff }
        results = fresh.sorted { $0.completedAt > $1.completedAt }
        // 期限切れを消したらファイルにも反映する
        if fresh.count != decoded.count, let out = try? JSONEncoder().encode(results) {
            try? out.write(to: fileURL, options: .atomic)
        }
    }

    func remove(_ id: UUID) {
        results.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 対応済みを一括で全消去する
    func removeAll() {
        results = []
        try? JSONEncoder().encode([ImprovementResult]()).write(to: fileURL, options: .atomic)
    }
}

/// アプリ自体への改善要望のひとつ。
struct Improvement: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// 添付(写真・動画)のファイル名。実体は Documents/improve_media/ に置く
    var attachments: [String]? = nil
}

/// 改善要望を端末に保管する。
///
/// 出先で思いついたことを放り込んでおき、家に帰って Mac が点いているときに
/// 送るまでの置き場。学習データとは役目が違うので、別のファイルに持つ。
final class ImprovementStore: ObservableObject {
    /// 他の画面(音声プレイヤーの🚩など)からも同じ一覧に書き込めるよう共有する
    static let shared = ImprovementStore()

    @Published private(set) var items: [Improvement] = []

    /// Documents 直下に置く。「ファイル」アプリからも見えるので、
    /// 送る仕組みが壊れたときでも中身を取り出せる。
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improvements.json")
    }

    init() {
        load()
    }

    /// 添付ファイル(写真・動画)の置き場
    static var mediaDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("improve_media")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 追加した要望の id を返す(プレイヤーの報告ボタンを押し直して取り消せるように)。
    /// 中身が空で何も追加しなかった場合は nil。
    @discardableResult
    func add(_ text: String, attachments: [String]? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !(attachments ?? []).isEmpty else { return nil }
        let item = Improvement(text: trimmed.isEmpty ? "(添付のみ)" : trimmed,
                               attachments: attachments)
        items.insert(item, at: 0)
        save()
        return item.id
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
        save()
    }

    func remove(_ id: UUID) {
        // 添付の実体ファイルも一緒に片付ける
        if let item = items.first(where: { $0.id == id }) {
            for name in item.attachments ?? [] {
                try? FileManager.default.removeItem(at: Self.mediaDir.appendingPathComponent(name))
            }
        }
        items.removeAll { $0.id == id }
        save()
    }

    // MARK: - 永続化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Improvement].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
