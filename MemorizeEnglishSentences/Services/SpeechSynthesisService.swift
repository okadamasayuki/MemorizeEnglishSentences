import AVFoundation
import Foundation

/// AVSpeechSynthesizer wrapper。
/// synthesizer はシングルトンで長寿命保持(ローカル変数だと解放されて無音になる)。
final class SpeechSynthesisService {
    static let shared = SpeechSynthesisService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, slow: Bool = false) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.3 : AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
