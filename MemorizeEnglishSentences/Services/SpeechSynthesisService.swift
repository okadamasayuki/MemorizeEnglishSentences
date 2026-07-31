import AVFoundation
import Foundation
import SwiftData

/// AVSpeechSynthesizer wrapper。
/// synthesizer はシングルトンで長寿命保持(ローカル変数だと解放されて無音になる)。
/// ブロック読み上げ中は、いま読んでいる文字範囲を公開して単語ハイライトに使う。
final class SpeechSynthesisService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesisService()

    private let synthesizer = AVSpeechSynthesizer()

    /// 読み上げ中のブロック(nil なら単語発音などの単発読み上げ)
    @Published var speakingBlockID: PersistentIdentifier?
    /// いま読んでいる文字範囲(utterance 文字列内の NSRange)
    @Published var speakingRange: NSRange?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 単語などの単発読み上げ(ハイライトなし)
    func speak(_ text: String, slow: Bool = false) {
        stop()
        startUtterance(text, slow: slow)
    }

    /// ブロック全文の読み上げ(読んでいる単語のハイライト付き)
    func speakBlock(_ text: String, id: PersistentIdentifier) {
        stop()
        speakingBlockID = id
        startUtterance(text, slow: false)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingBlockID = nil
        speakingRange = nil
    }

    private func startUtterance(_ text: String, slow: Bool) {
        let session = AVAudioSession.sharedInstance()
        // 実際に録音中のときだけ playAndRecord のまま触らない(切り替えると無音になる)。
        // 録音していなければ、たとえ録音用の設定が残っていても
        // 再生専用に切り替えてフル音量のスピーカーで鳴らす。
        if !SpeechRecognitionService.isAnyRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.3 : AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async {
            self.speakingRange = characterRange
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speakingBlockID = nil
            self.speakingRange = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speakingBlockID = nil
            self.speakingRange = nil
        }
    }
}
