import CryptoKit
import Foundation

/// 1単語分の再生タイミング(英文内のNSRangeと開始/終了秒)
struct AudioWordTiming {
    let range: NSRange
    let start: Double
    let end: Double
}

/// 各英文ブロックの「教材音声(MP3)+単語タイミング」を Documents/block_audio から読み出す。
/// Claude Code が block_audio フォルダ(timings.json + <ハッシュ>.mp3)を端末へ直接投入する。
/// キーは PageImageStore と同じ sha256(英文trim)[:16]。
enum BlockAudioStore {
    private struct Entry: Decodable {
        let w: [[Double]]      // [loc, len, start, end](loc/lenはUTF-16オフセット)
        let sil: [[Double]]?   // 無音区間 [start, end](音量解析による。息継ぎ除去に使う)
    }

    private static var cache: [String: Entry]?

    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("block_audio")
    }

    private static func manifest() -> [String: Entry] {
        if let cached = cache { return cached }
        let url = dir.appendingPathComponent("timings.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        cache = map
        return map
    }

    private static func key(forBlockText text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// このブロックに教材音声があるか
    static func hasAudio(forBlockText text: String) -> Bool {
        let k = key(forBlockText: text)
        guard manifest()[k] != nil else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(k).mp3").path)
    }

    /// このブロックの音声ファイルURLと単語タイミング・無音区間を返す
    static func item(forBlockText text: String) -> (url: URL, words: [AudioWordTiming], silences: [(start: Double, end: Double)])? {
        let k = key(forBlockText: text)
        guard let entry = manifest()[k] else { return nil }
        let url = dir.appendingPathComponent("\(k).mp3")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let words: [AudioWordTiming] = entry.w.compactMap { row in
            guard row.count == 4 else { return nil }
            return AudioWordTiming(
                range: NSRange(location: Int(row[0]), length: Int(row[1])),
                start: row[2], end: row[3]
            )
        }
        let silences: [(start: Double, end: Double)] = (entry.sil ?? []).compactMap { row in
            guard row.count == 2 else { return nil }
            return (row[0], row[1])
        }
        return (url, words, silences)
    }
}
