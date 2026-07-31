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
    private var rate: Float { [AVSpeechUtteranceDefaultSpeechRate, 0.57, 0.64][speedIndex] }

    func toggleSpeed() {
        speedIndex = (speedIndex + 1) % 3
    }

    func play(_ words: [VocabWord]) {
        stop()
        guard !words.isEmpty else { return }
        queue = words.map { ($0.persistentModelID, $0.english, $0.japanese) }
        index = 0
        phase = 0
        isPlaying = true
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

        let session = AVAudioSession.sharedInstance()
        if !SpeechRecognitionService.isAnyRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])

        let utterance: AVSpeechUtterance
        if phase == 0 {
            utterance = AVSpeechUtterance(string: item.english)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.postUtteranceDelay = 0.1
        } else {
            utterance = AVSpeechUtterance(string: item.japanese)
            utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            utterance.postUtteranceDelay = 0.25
        }
        utterance.rate = rate
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
