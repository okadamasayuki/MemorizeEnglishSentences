import CryptoKit
import Foundation
import UIKit

/// 各英文ブロックの「元スクショ(教材ページ画像)」を Documents/page_images から読み出す。
/// Claude Code が page_images フォルダ(manifest.json + <ページ番号>.jpg)を端末へ直接投入する。
enum PageImageStore {
    private static var manifestCache: [String: String]?
    /// ブロック英文→ハッシュのメモ(スクロール中に毎描画で SHA256 を計算しないため)
    private static var keyCache: [String: String] = [:]

    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("page_images")
    }

    /// block 英文ハッシュ → ページ番号 のマニフェスト(読み込めるまではキャッシュしない)
    private static func manifest() -> [String: String] {
        if let cached = manifestCache { return cached }
        let url = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        manifestCache = map
        return map
    }

    private static func key(forBlockText text: String) -> String {
        if let hit = keyCache[text] { return hit }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let key = String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
        if keyCache.count > 8000 { keyCache.removeAll(keepingCapacity: true) }
        keyCache[text] = key
        return key
    }

    /// このブロックに対応する元スクショがあるか
    static func hasImage(forBlockText text: String) -> Bool {
        manifest()[key(forBlockText: text)] != nil
    }

    /// このブロックに対応する元スクショを読み込む
    static func image(forBlockText text: String) -> UIImage? {
        guard let page = manifest()[key(forBlockText: text)] else { return nil }
        let url = dir.appendingPathComponent("\(page).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
