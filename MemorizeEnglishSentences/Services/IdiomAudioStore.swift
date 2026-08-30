import CryptoKit
import Foundation

/// 熟語タブの音声(和訳=VOICEVOX、英文=Kokoro TTS af_heart)を Documents/idiom_audio から読み出す。
/// Claude Code が exampleJa/example のテキストハッシュ名で投入する。
/// ファイル名: 和訳=<sha256(exampleJa.trim)[:16]>.m4a / 英文=<sha256(example.trim)[:16]>.m4a
enum IdiomAudioStore {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("idiom_audio")
    }
    private static func key(_ text: String) -> String {
        let n = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = SHA256.hash(data: Data(n.utf8))
        return String(d.map { String(format: "%02x", $0) }.joined().prefix(16))
    }
    /// 和訳(VOICEVOX)の音声。無ければ nil(呼び出し側が内蔵TTSにフォールバック)
    static func jaURL(_ exampleJa: String) -> URL? {
        let u = dir.appendingPathComponent("\(key(exampleJa)).m4a")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    /// 英文(Kokoro)の音声。無ければ nil
    static func enURL(_ example: String) -> URL? {
        let u = dir.appendingPathComponent("\(key(example)).m4a")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}
