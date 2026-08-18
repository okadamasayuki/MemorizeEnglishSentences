import Foundation

/// アプリ自体への改善要望のひとつ。
struct Improvement: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
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

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(Improvement(text: trimmed), at: 0)
        save()
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
        save()
    }

    func remove(_ id: UUID) {
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
