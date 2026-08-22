import CryptoKit
import Foundation

/// 事前生成した和訳音声を Documents/ja_audio から読み出す。
/// Claude Code が Mac 側で合成(VOICEVOX)して端末へ直接投入する。
/// ファイル名: <sha256(ブロック英文.trim).hex[:16]>_<文番号>.m4a(文番号は文ペアの0始まり)
///
/// 声の比較用に Documents/ja_audio_variants/<声ID>/ に別話者のセットも置ける。
/// 選択中の声(UserDefaults "jaVoiceVariant"、空=既定)を優先し、
/// ファイルが無ければ既定セット → TTS の順でフォールバックする。
enum JaAudioStore {
    /// 選べる声(表示名, フォルダID)。フォルダIDが空 = 既定の ja_audio。
    /// 比較の結果、雀松朱司(男性)に一本化(他の声は容量削減のため削除・2026-08-22)
    static let voices: [(name: String, id: String)] = [
        ("雀松朱司(男性)", ""),
    ]

    static var selectedVariant: String {
        get { UserDefaults.standard.string(forKey: "jaVoiceVariant") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "jaVoiceVariant") }
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var defaultDir: URL {
        documents.appendingPathComponent("ja_audio")
    }

    private static func variantDir(_ id: String) -> URL {
        documents.appendingPathComponent("ja_audio_variants").appendingPathComponent(id)
    }

    private static func key(forBlockText text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// この文の和訳音声(無ければ nil = TTSフォールバック)。選択中の声を優先する
    static func url(forBlockText text: String, segmentIndex: Int) -> URL? {
        let file = "\(key(forBlockText: text))_\(segmentIndex).m4a"
        let variant = selectedVariant
        if !variant.isEmpty {
            let url = variantDir(variant).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let url = defaultDir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
