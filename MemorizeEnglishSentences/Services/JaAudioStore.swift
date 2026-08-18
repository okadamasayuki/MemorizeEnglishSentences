import CryptoKit
import Foundation

/// 事前生成した和訳音声を Documents/ja_audio から読み出す。
/// Claude Code が Mac 側で合成(VOICEVOX)して端末へ直接投入する。
/// ファイル名: <sha256(ブロック英文.trim).hex[:16]>_<文番号>.m4a(文番号は文ペアの0始まり)
enum JaAudioStore {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ja_audio")
    }

    private static func key(forBlockText text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// この文の和訳音声(無ければ nil = TTSフォールバック)
    static func url(forBlockText text: String, segmentIndex: Int) -> URL? {
        let url = dir.appendingPathComponent("\(key(forBlockText: text))_\(segmentIndex).m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
