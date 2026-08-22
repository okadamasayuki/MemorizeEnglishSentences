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
    private func diskURL(for word: String) -> URL {
        let digest = SHA256.hash(data: Data(word.utf8))
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

    /// 発音する。posJa(名詞/動詞など)が分かればヘテロニムを品詞に合わせて発音する。
    /// 失敗時は onFallback を呼ぶ(内蔵TTS用)
    func speak(_ text: String, posJa: String? = nil, onFallback: @escaping () -> Void) {
        var word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        // ヘテロニムは品詞に応じてキャリアフレーズに置き換える
        let lower = word.lowercased()
        if Self.heteronyms.contains(lower), let pos = posJa {
            if pos.contains("動詞") { word = "to \(lower)" }
            else if pos.contains("名詞") { word = "the \(lower)" }
        }

        // 取得済み(メモリ)ならそのまま鳴らす
        if let data = cache[word] {
            play(data, fallbackText: word, onFallback: onFallback)
            return
        }
        // 事前ダウンロード済み(ディスク)ならオフラインでもGoogle音声で鳴らす
        let disk = diskURL(for: word)
        if let data = try? Data(contentsOf: disk), data.count > 200 {
            cache[word] = data
            play(data, fallbackText: word, onFallback: onFallback)
            return
        }
        // オフラインでディスクにも無ければ、待たずに即・内蔵音声
        if !isOnline {
            onFallback()
            return
        }
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=\(encoded)") else {
            onFallback()
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 6)
        // ブラウザ風のUAでないと弾かれることがあるため付ける
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            guard let self, ok, let data, data.count > 200 else {
                DispatchQueue.main.async { onFallback() }
                return
            }
            self.cache[word] = data
            DispatchQueue.main.async { self.play(data, fallbackText: word, onFallback: onFallback) }
        }.resume()
    }

    private func play(_ data: Data, fallbackText: String, onFallback: @escaping () -> Void) {
        do {
            // 再生専用にセッションを整える(録音中は触らない)
            if !SpeechRecognitionService.isAnyRecording {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            let p = try AVAudioPlayer(data: data)
            player = p
            p.play()
        } catch {
            onFallback()
        }
    }
}
