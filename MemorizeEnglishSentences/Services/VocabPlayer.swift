import AVFoundation
import Foundation
import SwiftData

/// 単語タブの連続再生。リストの順に「英単語 → 和訳」を読み上げていく。
/// 再生中の単語 ID を公開して一覧のハイライトに使う。速度は 1×/2×/3× を切り替え。
@MainActor
final class VocabPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VocabPlayer()

    @Published var currentID: PersistentIdentifier?
    @Published var isPlaying = false
    @Published var speedIndex = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [(id: PersistentIdentifier, english: String, japanese: String)] = []
    private var index = 0
    /// 0 = 英単語を読んでいる, 1 = 和訳を読んでいる
    private var phase = 0

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    var speedLabel: String { ["1×", "2×", "3×"][speedIndex] }
    /// AVSpeechUtterance の rate は線形でないため、体感で速くなる値を割り当てる
    private var englishRate: Float { [AVSpeechUtteranceDefaultSpeechRate, 0.57, 0.64][speedIndex] }
    /// 日本語は速くすると不明瞭になりやすいので、英語より控えめに上げる
    private var japaneseRate: Float { [AVSpeechUtteranceDefaultSpeechRate, 0.55, 0.60][speedIndex] }

    /// 品質の高い声を選ぶ(既定の compact 声は聞き取りにくい)。
    /// 英語は premium だと息継ぎ音(「すっ」という音)が入るため enhanced を優先する。
    private static func bestVoice(for language: String, preferPremium: Bool) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let ordered: [AVSpeechSynthesisVoiceQuality] = preferPremium ? [.premium, .enhanced] : [.enhanced, .premium]
        for quality in ordered {
            if let voice = candidates.first(where: { $0.quality == quality }) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    private lazy var englishVoice = Self.bestVoice(for: "en-US", preferPremium: false)
    private lazy var japaneseVoice = Self.bestVoice(for: "ja-JP", preferPremium: true)

    func toggleSpeed() {
        speedIndex = (speedIndex + 1) % 3
    }

    /// 連続再生を開始する。from を指定するとその単語から始める
    func play(_ words: [VocabWord], from start: VocabWord? = nil) {
        stop()
        guard !words.isEmpty else { return }
        queue = words.map { ($0.persistentModelID, $0.english, $0.japanese) }
        index = start.flatMap { started in
            queue.firstIndex { $0.id == started.persistentModelID }
        } ?? 0
        phase = 0
        isPlaying = true

        // セッション設定は再生開始時の 1 回だけ(毎回設定し直すとノイズが乗る)
        let session = AVAudioSession.sharedInstance()
        if !SpeechRecognitionService.isAnyRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])

        speakCurrent()
    }

    func stop() {
        isPlaying = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentID = nil
        queue = []
    }

    private func speakCurrent() {
        guard index < queue.count else {
            stop()
            return
        }
        let item = queue[index]
        currentID = item.id

        let utterance: AVSpeechUtterance
        if phase == 0 {
            utterance = AVSpeechUtterance(string: item.english)
            utterance.voice = englishVoice
            utterance.rate = englishRate
            utterance.postUtteranceDelay = 0.1
        } else {
            utterance = AVSpeechUtterance(string: item.japanese)
            utterance.voice = japaneseVoice
            utterance.rate = japaneseRate
            utterance.postUtteranceDelay = 0.25
        }
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    private func advance() {
        if phase == 0, !queue[index].japanese.isEmpty {
            phase = 1
        } else {
            phase = 0
            index += 1
        }
        speakCurrent()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isPlaying else { return }
            self.advance()
        }
    }
}
