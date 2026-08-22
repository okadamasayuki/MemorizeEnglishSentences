import AVFoundation
import CryptoKit
import Foundation
import Network

/// Google 翻訳と同じ発音音声を鳴らす。
/// 単語をGoogleのTTSエンドポイントでmp3として取得して再生する。
/// (Google翻訳アプリの「発音」ボタンと同じ声。オフラインや取得失敗時は
///  端末内蔵の読み上げ(SpeechSynthesisService)に即フォールバックする。
///  内蔵TTSはオフラインでも動くので、機内モードでも発音は使える)
final class GoogleTTS: NSObject {
    static let shared = GoogleTTS()

    private var player: AVAudioPlayer?
    /// 再生が終わったときに一度だけ呼ぶ(シス単風の 英→和→英 の連鎖に使う)
    private var onFinished: (() -> Void)?
    /// 取得済みmp3のキャッシュ(同じ単語を何度も取りに行かない。過去に聴いた語はオフラインでも鳴る)
    private var cache: [String: Data] = [:]
    /// ネット接続の見張り(オフラインを即判定して待ち時間をなくす)
    private let monitor = NWPathMonitor()
    private var isOnline = true

    private override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "googletts.net"))
    }

    /// 事前ダウンロードした発音mp3の置き場(Documents/word_audio/<sha16>.mp3)。
    /// Claude Code が全単語・熟語分を投入する。これがあればオフラインでもGoogle音声で鳴る
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("word_audio")
    }
    /// ディスク/メモリのキー。英語は従来どおり単語そのもの(事前DL資産と互換)、
    /// それ以外の言語は "lang:テキスト" にして英語と衝突させない
    private func cacheKey(_ text: String, lang: String) -> String {
        lang == "en" ? text : "\(lang):\(text)"
    }
    private func diskURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
        return Self.dir.appendingPathComponent("\(name).mp3")
    }

    /// 品詞で発音が変わる語(use=名詞/juːs/・動詞/juːz/, record など)。
    /// 単語だけだと発音が固定になるため、名詞は "the X"、動詞は "to X" の
    /// 実在フレーズで読ませて、その文での品詞に合った発音にする。
    private static let heteronyms: Set<String> = [
        "use","record","present","subject","produce","contract","conflict","contrast",
        "increase","decrease","progress","project","refuse","export","insult","protest",
        "address","contest","impact","upset","reject","research","construct","graduate",
    ]

    /// 発音する。lang="en"は英単語(既定・事前DL資産つき)、lang="ja"は日本語(意味の読み上げ)など。
    /// posJa(名詞/動詞など)が分かればヘテロニムを品詞に合わせて発音する(英語のみ)。
    /// 失敗時は onFallback を呼ぶ(内蔵TTS用)。onFinished は再生が終わったら一度だけ呼ぶ
    /// (シス単風の 英→和→英 の連鎖に使う。フォールバック時も鳴り終わり相当で呼ぶ)。
    func speak(_ text: String, lang: String = "en", posJa: String? = nil, rate: Float = 1.0,
               onFallback: @escaping () -> Void, onFinished: (() -> Void)? = nil) {
        var word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { onFinished?(); return }
        // ヘテロニムは品詞に応じてキャリアフレーズに置き換える(英語のみ)
        if lang == "en" {
            let lower = word.lowercased()
            if Self.heteronyms.contains(lower), let pos = posJa {
                if pos.contains("動詞") { word = "to \(lower)" }
                else if pos.contains("名詞") { word = "the \(lower)" }
            }
        }
        let ckey = cacheKey(word, lang: lang)

        // 取得済み(メモリ)ならそのまま鳴らす
        if let data = cache[ckey] {
            play(data, fallbackText: word, rate: rate, onFallback: onFallback, onFinished: onFinished)
            return
        }
        // 事前ダウンロード済み/一度取得済み(ディスク)ならオフラインでもGoogle音声で鳴らす
        let disk = diskURL(forKey: ckey)
        if let data = try? Data(contentsOf: disk), data.count > 200 {
            cache[ckey] = data
            play(data, fallbackText: word, rate: rate, onFallback: onFallback, onFinished: onFinished)
            return
        }
        // オフラインでディスクにも無ければ、待たずに即・内蔵音声
        if !isOnline {
            onFallback()
            finishAfterFallback(word, rate: rate, onFinished)
            return
        }
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=\(lang)&client=tw-ob&q=\(encoded)") else {
            onFallback()
            finishAfterFallback(word, rate: rate, onFinished)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 6)
        // ブラウザ風のUAでないと弾かれることがあるため付ける
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            guard let self, ok, let data, data.count > 200 else {
                DispatchQueue.main.async { onFallback(); self?.finishAfterFallback(word, rate: rate, onFinished) }
                return
            }
            self.cache[ckey] = data
            // 次回・オフラインでも鳴らせるようディスクにも残す(日本語の意味などの再取得を防ぐ)
            try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            try? data.write(to: disk, options: .atomic)
            DispatchQueue.main.async { self.play(data, fallbackText: word, rate: rate, onFallback: onFallback, onFinished: onFinished) }
        }.resume()
    }

    /// 今鳴っている発音を止める(シス単風プレイヤーの一時停止・曲送り用)。
    /// 予約していた完了通知も破棄して、古い連鎖が動かないようにする。
    func stop() {
        onFinished = nil
        player?.stop()
        player = nil
    }

    /// 内蔵音声にフォールバックしたときの、鳴り終わり相当の見積り時間で onFinished を呼ぶ
    private func finishAfterFallback(_ word: String, rate: Float = 1.0, _ onFinished: (() -> Void)?) {
        guard let onFinished else { return }
        // 語長からおおよその読み上げ時間を見積る(短くても最低0.6秒)。倍速時は短く
        let secs = max(0.4, (Double(word.count) * 0.09 + 0.35) / Double(max(0.5, rate)))
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) { onFinished() }
    }

    private func play(_ data: Data, fallbackText: String, rate: Float = 1.0,
                      onFallback: @escaping () -> Void, onFinished: (() -> Void)? = nil) {
        do {
            // 再生専用にセッションを整える(録音中は触らない)
            if !SpeechRecognitionService.isAnyRecording {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            let p = try AVAudioPlayer(data: data)
            self.onFinished = onFinished
            p.delegate = self
            // 倍速再生(音程は保つ)。1.0以外のときだけ有効化
            if rate != 1.0 {
                p.enableRate = true
                p.rate = rate
            }
            player = p
            p.play()
        } catch {
            onFallback()
            finishAfterFallback(fallbackText, onFinished)
        }
    }
}

extension GoogleTTS: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let cb = onFinished
        onFinished = nil
        cb?()
    }
}
