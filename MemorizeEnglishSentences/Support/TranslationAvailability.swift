import Foundation
import Translation

/// Apple 純正 Translation フレームワーク (en → ja) の利用可否チェック。
/// ⚠️ Translation フレームワークは iOS シミュレータ非対応 — 動作確認は実機 (iOS 18+) 必須。
enum TranslationAvailability {
    static let english = Locale.Language(identifier: "en")
    static let japanese = Locale.Language(identifier: "ja")

    static func status() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: english, to: japanese)
    }

    static func statusMessageJa(_ status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed:
            "英日翻訳の言語データはダウンロード済みです。"
        case .supported:
            "英日翻訳は利用できますが、言語データのダウンロードが必要です。初回翻訳時にダウンロードの確認が表示されます。"
        case .unsupported:
            "この端末では英日翻訳を利用できません。"
        @unknown default:
            "翻訳の利用可否を確認できませんでした。"
        }
    }
}
