import Foundation

/// アプリの利用期限(埋め込みプロビジョニングプロファイルの失効日)を取得する。
/// 無料の開発者証明書では署名から7日で失効し、その日を過ぎると起動できなくなる。
/// embedded.mobileprovision(CMS署名付き)の中に平文で埋まっている plist を取り出して
/// ExpirationDate を読む。
enum AppExpiry {
    /// 利用期限。取得できなければ nil。
    /// ツールバー表示のたびに参照されるため、起動後最初の1回だけ読み取ってキャッシュする
    /// (ファイル読込+plist解析を毎描画で行うとスクロールがカクつく)。
    static let expirationDate: Date? = loadExpirationDate()

    private static func loadExpirationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // バイナリCMSの中から <plist ...>...</plist> の範囲を抜き出す
        guard let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let date = plist["ExpirationDate"] as? Date else { return nil }
        return date
    }

    /// 期限までの残り日数(切り捨て。期限当日は0、過ぎたら負)
    static var daysRemaining: Int? {
        guard let exp = expirationDate else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: exp)
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }

    /// 「2026年8月19日」形式
    static var expirationText: String? {
        guard let exp = expirationDate else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: exp)
    }
}
