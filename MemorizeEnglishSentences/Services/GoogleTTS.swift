import AVFoundation
import Foundation

/// Google 翻訳と同じ発音音声を鳴らす。
/// 単語をGoogleのTTSエンドポイントでmp3として取得して再生する。
/// (Google翻訳アプリの「発音」ボタンと同じ声。ネット不通などで失敗したら
///  端末内蔵の読み上げ(SpeechSynthesisService)にフォールバックする)
final class GoogleTTS: NSObject {
    static let shared = GoogleTTS()

    private var player: AVAudioPlayer?
    /// 取得済みmp3のキャッシュ(同じ単語を何度も取りに行かない)
    private var cache: [String: Data] = [:]

    /// 英語(tl=en)として発音する。失敗時は onFallback を呼ぶ(内蔵TTS用)
    func speak(_ text: String, onFallback: @escaping () -> Void) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        if let data = cache[word] {
            play(data, fallbackText: word, onFallback: onFallback)
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
