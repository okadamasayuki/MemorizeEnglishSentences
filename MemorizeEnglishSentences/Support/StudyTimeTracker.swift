import Foundation

/// アプリを使っている時間(=勉強時間)を累計するトラッカー。
/// アプリがアクティブな間だけ計測し、UserDefaults に永続化する。
@MainActor
final class StudyTimeTracker {
    static let shared = StudyTimeTracker()

    private let key = "totalStudySeconds"
    private var sessionStart: Date?

    private init() {}

    /// 保存済み + 計測中セッションを合わせた現在の累計勉強時間(秒)
    var currentTotalSeconds: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: key)
        if let sessionStart {
            return saved + Date().timeIntervalSince(sessionStart)
        }
        return saved
    }

    func sessionStarted() {
        guard sessionStart == nil else { return }
        sessionStart = Date()
    }

    func sessionEnded() {
        guard let start = sessionStart else { return }
        let saved = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(saved + Date().timeIntervalSince(start), forKey: key)
        sessionStart = nil
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)時間\(minutes)分"
        }
        return "\(minutes)分"
    }
}
